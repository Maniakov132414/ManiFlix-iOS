import Foundation
import UIKit
import CryptoKit
import WidgetKit

struct WidgetSyncHistoryItem: Codable {
    let slug: String
    let name: String
    let poster: String?
    let episodeIndex: Int
    let episodeName: String?
    let currentTime: Double
    let duration: Double
}

struct WidgetSyncFavoriteItem: Codable {
    let slug: String
    let name: String
    let poster: String?
}

struct WidgetSyncPayload: Codable {
    let history: [WidgetSyncHistoryItem]
    let favorites: [WidgetSyncFavoriteItem]
    let likedSlugs: [String]
    let blockedSlugs: [String]
    let widgetMode: String
    let updatedAt: Double
}

@MainActor
final class WidgetSyncBridge {
    static let shared = WidgetSyncBridge()

    static let appGroupSuite = "group.bond.maniakov.maniflix"
    static let localPayloadKey = "maniflix.widgetSyncPayload.v1"

    private var lastNetworkSyncAt: Date = .distantPast
    private var syncTask: Task<Void, Never>?

    private init() {}

    static func hashedVendorKey() -> String {
        let vendorId = UIDevice.current.identifierForVendor?.uuidString ?? "maniflix-default-device"
        let raw = "mf-wid:" + vendorId
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func syncFromCurrentState(force: Bool = false) {
        let state = AppState.shared
        let prefs = AppPreferences.shared

        let histItems: [WidgetSyncHistoryItem] = state.history.prefix(6).map { entry in
            WidgetSyncHistoryItem(
                slug: entry.slug,
                name: entry.name ?? entry.slug,
                poster: entry.poster,
                episodeIndex: entry.episodeIndex ?? 0,
                episodeName: entry.episodeName,
                currentTime: entry.currentTime ?? 0,
                duration: entry.duration ?? 0
            )
        }

        let favItems: [WidgetSyncFavoriteItem] = state.favorites.prefix(10).map { fav in
            WidgetSyncFavoriteItem(
                slug: fav.slug,
                name: fav.name ?? fav.slug,
                poster: fav.poster
            )
        }

        let payload = WidgetSyncPayload(
            history: histItems,
            favorites: favItems,
            likedSlugs: Array(state.likedSlugs.prefix(30)),
            blockedSlugs: state.blockedMovies.map(\.slug),
            widgetMode: prefs.widgetFeedMode.rawValue,
            updatedAt: Date().timeIntervalSince1970 * 1000
        )

        if let encoded = try? JSONEncoder().encode(payload) {
            UserDefaults(suiteName: Self.appGroupSuite)?.set(encoded, forKey: Self.localPayloadKey)
        }

        let now = Date()
        if !force && now.timeIntervalSince(lastNetworkSyncAt) < 15.0 {
            return
        }
        lastNetworkSyncAt = now
        WidgetCenter.shared.reloadAllTimelines()

        let key = Self.hashedVendorKey()
        let baseURL = prefs.normalizedBaseURL
        syncTask?.cancel()
        syncTask = Task.detached(priority: .utility) {
            await Self.postSyncPayload(baseURL: baseURL, key: key, payload: payload)
        }
    }

    private nonisolated static func postSyncPayload(baseURL: String, key: String, payload: WidgetSyncPayload) async {
        guard let url = URL(string: "\(baseURL)/api/widget-sync") else { return }
        struct Envelope: Encodable {
            let key: String
            let payload: WidgetSyncPayload
        }
        guard let body = try? JSONEncoder().encode(Envelope(key: key, payload: payload)) else { return }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("ManiFlix/2.0.2", forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        _ = try? await URLSession.shared.data(for: req)
    }
}
