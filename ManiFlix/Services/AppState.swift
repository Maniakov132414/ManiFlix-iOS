import Foundation
import SwiftUI
import Combine

struct ActivePlaybackSession: Identifiable {
    let id = UUID()
    let movie: MovieDetail
    let servers: [EpisodeServer]
    let serverIndex: Int
    let episodeIndex: Int
    let startTime: Double
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var authToken: String {
        didSet { UserDefaults.standard.set(authToken, forKey: "auth.token") }
    }
    @Published var currentUser: UserInfo?
    @Published var favorites: [FavoriteEntry] = []
    @Published var history: [HistoryEntry] = []
    @Published var showAuthSheet = false
    @Published var isPlayerPresented = false
    @Published var activeEngine: PlayerEngine?
    @Published var deepLinkSlug: String?

    private init() {
        self.authToken = UserDefaults.standard.string(forKey: "auth.token") ?? ""
    }

    var isLoggedIn: Bool {
        !authToken.isEmpty && currentUser != nil
    }

    func bootstrapSession() async {
        guard !authToken.isEmpty else { return }
        do {
            let me = try await ManiFlixAPI.shared.fetchMe(token: authToken)
            self.currentUser = me.user
            await refreshLibrary()
        } catch {
            if case APIError.badStatus(let code, _) = error, code == 401 {
                logout()
            }
        }
    }

    func refreshLibrary() async {
        guard !authToken.isEmpty else { return }
        async let histTask = ManiFlixAPI.shared.fetchHistory(token: authToken)
        async let favTask = ManiFlixAPI.shared.fetchFavorites(token: authToken)
        if let h = try? await histTask { self.history = h.history ?? [] }
        if let f = try? await favTask { self.favorites = f.favorites ?? [] }
    }

    func handleAuthSuccess(token: String, user: UserInfo?) async {
        self.authToken = token
        self.currentUser = user
        self.showAuthSheet = false
        await refreshLibrary()
    }

    func logout() {
        authToken = ""
        currentUser = nil
        favorites = []
        history = []
    }

    func isFavorite(slug: String) -> Bool {
        favorites.contains(where: { $0.slug == slug })
    }

    func toggleFavorite(movie: MovieDetail) async {
        guard !authToken.isEmpty else {
            showAuthSheet = true
            return
        }
        do {
            let res = try await ManiFlixAPI.shared.toggleFavorite(token: authToken, movie: movie)
            if let list = res.favorites {
                self.favorites = list
            } else {
                await refreshLibrary()
            }
            Haptics.notify(.success)
        } catch {
            Haptics.notify(.error)
        }
    }

    func savedResumeTime(slug: String, episodeIndex: Int) -> Double {
        if let match = history.first(where: { $0.slug == slug && ($0.episodeIndex ?? 0) == episodeIndex }) {
            let cur = match.currentTime ?? 0
            let dur = match.duration ?? 0
            if cur > 10 && (dur <= 0 || cur < dur - 20) {
                return cur
            }
        }
        return 0
    }

    func recordProgress(movie: MovieDetail, episodeIndex: Int, episodeName: String, currentTime: Double, duration: Double) async {
        let localEntry = HistoryEntry(
            slug: movie.slug,
            name: movie.name,
            poster: movie.poster_url ?? movie.thumb_url,
            episodeIndex: episodeIndex,
            episodeName: episodeName,
            currentTime: currentTime,
            duration: duration,
            updatedAt: Date().timeIntervalSince1970 * 1000
        )
        history.removeAll(where: { $0.slug == movie.slug })
        history.insert(localEntry, at: 0)

        guard !authToken.isEmpty else { return }
        await ManiFlixAPI.shared.saveHistory(
            token: authToken,
            slug: movie.slug,
            name: movie.name,
            poster: movie.poster_url ?? movie.thumb_url ?? "",
            episodeIndex: episodeIndex,
            episodeName: episodeName,
            currentTime: currentTime,
            duration: duration
        )
    }

    func deleteHistory(slug: String) async {
        history.removeAll(where: { $0.slug == slug })
        guard !authToken.isEmpty else { return }
        await ManiFlixAPI.shared.deleteHistory(token: authToken, slug: slug)
    }

    func startPlayback(movie: MovieDetail, servers: [EpisodeServer], serverIndex: Int, episodeIndex: Int) {
        let ep = servers[safe: serverIndex]?.server_data[safe: episodeIndex]
        let prefs = AppPreferences.shared
        if prefs.externalPlayer != .internalPlayer, let ep = ep, let m3u8 = ep.link_m3u8, !m3u8.isEmpty {
            let targetURL: String
            if prefs.preferredSource == .cleanFirst, let clean = ManiFlixAPI.shared.cleanM3U8URL(from: m3u8)?.absoluteString {
                targetURL = clean
            } else {
                targetURL = m3u8
            }
            if ExternalPlayerLauncher.open(url: targetURL, option: prefs.externalPlayer) {
                return
            }
        }

        // Reuse existing engine if user re-opens same episode from PiP
        if let existing = activeEngine,
           existing.movie.slug == movie.slug,
           existing.serverIndex == serverIndex,
           existing.episodeIndex == episodeIndex {
            isPlayerPresented = true
            return
        }

        activeEngine?.shutdown()
        let resume = savedResumeTime(slug: movie.slug, episodeIndex: episodeIndex)
        let engine = PlayerEngine(
            movie: movie,
            servers: servers,
            serverIndex: serverIndex,
            episodeIndex: episodeIndex,
            resumeTime: resume
        )
        activeEngine = engine
        isPlayerPresented = true
    }

    func dismissPlayerKeepPiPIfNeeded() {
        isPlayerPresented = false
        if let engine = activeEngine, !engine.isPiPActive {
            engine.shutdown()
            activeEngine = nil
        }
    }

    func stopPlaybackCompletely() {
        isPlayerPresented = false
        activeEngine?.shutdown()
        activeEngine = nil
    }
}

enum ExternalPlayerLauncher {
    @discardableResult
    static func open(url: String, option: ExternalPlayerOption) -> Bool {
        let encoded = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        let deepURLString: String
        switch option {
        case .internalPlayer:
            return false
        case .vlc:
            deepURLString = "vlc-x-callback://x-callback-url/stream?url=\(encoded)"
        case .outplayer:
            deepURLString = "outplayer://\(url)"
        case .infuse:
            deepURLString = "infuse://x-callback-url/play?url=\(encoded)"
        }
        guard let deepURL = URL(string: deepURLString), UIApplication.shared.canOpenURL(deepURL) else {
            return false
        }
        UIApplication.shared.open(deepURL)
        return true
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
