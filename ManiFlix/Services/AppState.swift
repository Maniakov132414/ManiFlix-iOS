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

struct BlockedMovieRecord: Codable, Identifiable, Hashable {
    var id: String { slug }
    let slug: String
    let name: String
    let poster: String?
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
    @Published var blockedMovies: [BlockedMovieRecord] = []
    @Published var likedSlugs: Set<String> = []
    @Published var showAuthSheet = false
    @Published var isPlayerPresented = false
    @Published var activeEngine: PlayerEngine?
    @Published var deepLinkSlug: String?
    @Published var globalBannerMessage: String?

    private let blockedKey = "prefs.blockedMovies.v1"
    private let likedKey = "prefs.likedSlugs.v1"
    private let localHistoryKey = "prefs.localHistory.v1"

    private init() {
        self.authToken = UserDefaults.standard.string(forKey: "auth.token") ?? ""
        if let data = UserDefaults.standard.data(forKey: blockedKey),
           let decoded = try? JSONDecoder().decode([BlockedMovieRecord].self, from: data) {
            self.blockedMovies = decoded
        }
        if let savedLikes = UserDefaults.standard.stringArray(forKey: likedKey) {
            self.likedSlugs = Set(savedLikes)
        }
        if let hData = UserDefaults.standard.data(forKey: localHistoryKey),
           let decodedHist = try? JSONDecoder().decode([HistoryEntry].self, from: hData) {
            self.history = decodedHist
        }
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
        if let h = try? await histTask, let serverHist = h.history {
            self.history = serverHist
            persistLocalHistory()
        }
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
    }

    func isFavorite(slug: String) -> Bool {
        favorites.contains(where: { $0.slug == slug })
    }

    func isBlocked(slug: String) -> Bool {
        blockedMovies.contains(where: { $0.slug == slug })
    }

    func hasHistory(slug: String) -> Bool {
        history.contains(where: { $0.slug == slug })
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

    func toggleFavoriteItem(_ item: MovieItem) async {
        guard !authToken.isEmpty else {
            showAuthSheet = true
            return
        }
        do {
            let wasFav = isFavorite(slug: item.slug)
            let res = try await ManiFlixAPI.shared.toggleFavoriteItem(token: authToken, item: item)
            if let list = res.favorites {
                self.favorites = list
            } else {
                await refreshLibrary()
            }
            Haptics.notify(.success)
            showBanner(wasFav ? "Đã xoá khỏi Tủ phim" : "Đã thêm vào Tủ phim")
        } catch {
            Haptics.notify(.error)
        }
    }

    func likeMovie(_ item: MovieItem) {
        likedSlugs.insert(item.slug)
        UserDefaults.standard.set(Array(likedSlugs), forKey: likedKey)
        Haptics.impact(.light)
        showBanner("Đã thích: sẽ gợi ý thêm phim tương tự")
    }

    func dislikeMovie(_ item: MovieItem) {
        likedSlugs.remove(item.slug)
        UserDefaults.standard.set(Array(likedSlugs), forKey: likedKey)
        Haptics.impact(.light)
        showBanner("Đã ghi nhận: giảm bớt phim tương tự")
    }

    func blockMovie(_ item: MovieItem) {
        guard !isBlocked(slug: item.slug) else { return }
        let rec = BlockedMovieRecord(slug: item.slug, name: item.name, poster: item.poster_url ?? item.thumb_url)
        blockedMovies.insert(rec, at: 0)
        persistBlocked()
        Haptics.notify(.warning)
        showBanner("Đã ẩn \"\(item.name)\" khỏi đề xuất")
    }

    func unblockMovie(slug: String) {
        blockedMovies.removeAll(where: { $0.slug == slug })
        persistBlocked()
        Haptics.impact(.light)
        showBanner("Đã bỏ ẩn phim")
    }

    private func persistBlocked() {
        if let data = try? JSONEncoder().encode(blockedMovies) {
            UserDefaults.standard.set(data, forKey: blockedKey)
        }
    }

    private func persistLocalHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: localHistoryKey)
        }
    }

    static func presentShareSheet(items: [Any]) {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }) ?? UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController ?? scene.windows.first?.rootViewController else {
            return
        }
        var top = root
        while let next = top.presentedViewController {
            top = next
        }
        if let pop = vc.popoverPresentationController {
            pop.sourceView = top.view
            pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
            pop.permittedArrowDirections = []
        }
        top.present(vc, animated: true)
    }

    func showBanner(_ text: String) {
        globalBannerMessage = text
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self.globalBannerMessage == text {
                self.globalBannerMessage = nil
            }
        }
    }

    func quickWatch(slug: String) async {
        showBanner("Đang mở trình phát...")
        do {
            let res = try await ManiFlixAPI.shared.fetchMovieDetail(slug: slug)
            if let movie = res.movie {
                let servers = res.episodes ?? []
                if let hist = history.first(where: { $0.slug == slug }) {
                    let epIdx = min(max(0, hist.episodeIndex ?? 0), max(0, (servers.first?.server_data.count ?? 1) - 1))
                    startPlayback(movie: movie, servers: servers, serverIndex: 0, episodeIndex: epIdx)
                } else {
                    startPlayback(movie: movie, servers: servers, serverIndex: 0, episodeIndex: 0)
                }
            }
        } catch {
            showBanner("Không tải được luồng phát")
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
        persistLocalHistory()

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
        persistLocalHistory()
        guard !authToken.isEmpty else { return }
        await ManiFlixAPI.shared.deleteHistory(token: authToken, slug: slug)
        showBanner("Đã xoá khỏi lịch sử xem")
    }

    func startPlayback(movie: MovieDetail, servers: [EpisodeServer], serverIndex: Int, episodeIndex: Int) {
        let ep = servers[safe: serverIndex]?.server_data[safe: episodeIndex]
        let prefs = AppPreferences.shared
        if prefs.externalPlayer != .internalPlayer, let ep = ep, let m3u8 = ep.link_m3u8, !m3u8.isEmpty {
            let targetURL = ManiFlixAPI.shared.cleanM3U8URL(from: m3u8)?.absoluteString ?? m3u8
            if ExternalPlayerLauncher.open(url: targetURL, option: prefs.externalPlayer) {
                return
            }
        }

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
        if let engine = activeEngine {
            if engine.closingExplicitly || !engine.isPiPActive {
                engine.shutdown()
                activeEngine = nil
            }
        }
    }

    func stopPlaybackCompletely() {
        activeEngine?.markClosingExplicitly()
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
