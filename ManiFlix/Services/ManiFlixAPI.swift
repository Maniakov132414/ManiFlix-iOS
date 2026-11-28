import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case badStatus(Int, String)
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL máy chủ không hợp lệ."
        case .badStatus(let code, let msg): return "Lỗi máy chủ HTTP \(code): \(msg)"
        case .decodingFailed(let detail): return "Lỗi giải mã dữ liệu: \(detail)"
        }
    }
}

actor APIMemoryCache {
    private struct Entry {
        let data: Data
        let expiresAt: Date
    }

    private var entries: [String: Entry] = [:]
    private var inflight: [String: Task<Data, Error>] = [:]
    private let maxEntries = 160

    func get(key: String) -> Data? {
        guard let item = entries[key] else { return nil }
        if Date() >= item.expiresAt {
            entries.removeValue(forKey: key)
            return nil
        }
        return item.data
    }

    func set(_ data: Data, for key: String, ttl: TimeInterval) {
        guard ttl > 0 else { return }
        if entries.count >= maxEntries {
            let now = Date()
            entries = entries.filter { $0.value.expiresAt > now }
            if entries.count >= maxEntries, let oldest = entries.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                entries.removeValue(forKey: oldest)
            }
        }
        entries[key] = Entry(data: data, expiresAt: Date().addingTimeInterval(ttl))
    }

    func fetchCoalesced(
        key: String,
        ttl: TimeInterval,
        forceRefresh: Bool,
        loader: @escaping @Sendable () async throws -> Data
    ) async throws -> Data {
        if !forceRefresh, let hit = get(key: key) {
            return hit
        }
        if !forceRefresh, let existing = inflight[key] {
            return try await existing.value
        }

        let task = Task<Data, Error> {
            try await loader()
        }
        inflight[key] = task
        do {
            let data = try await task.value
            inflight.removeValue(forKey: key)
            if ttl > 0 {
                set(data, for: key, ttl: ttl)
            }
            return data
        } catch {
            inflight.removeValue(forKey: key)
            throw error
        }
    }
}

final class ManiFlixAPI {
    static let shared = ManiFlixAPI()
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let memoryCache = APIMemoryCache()

    private init() {
        let urlCache = URLCache(
            memoryCapacity: 64 * 1024 * 1024,
            diskCapacity: 256 * 1024 * 1024,
            diskPath: "ManiFlixAPICache"
        )
        let config = URLSessionConfiguration.default
        config.urlCache = urlCache
        config.requestCachePolicy = .useProtocolCachePolicy
        config.httpMaximumConnectionsPerHost = 12
        config.timeoutIntervalForRequest = 16
        config.timeoutIntervalForResource = 32
        self.session = URLSession(configuration: config)
    }

    private var baseURL: String {
        AppPreferences.shared.normalizedBaseURL
    }

    func cleanM3U8URL(from rawM3U8: String, extraParams: [String: String] = [:]) -> URL? {
        guard var comps = URLComponents(string: "\(baseURL)/api/clean-m3u8") else { return nil }
        var items = [
            URLQueryItem(name: "url", value: rawM3U8),
            URLQueryItem(name: "sub", value: AppPreferences.shared.defaultSubtitleLang)
        ]
        for (k, v) in extraParams {
            items.append(URLQueryItem(name: k, value: v))
        }
        comps.queryItems = items
        return comps.url
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        token: String? = nil,
        cacheTTL: TimeInterval = 0,
        forceRefresh: Bool = false
    ) async throws -> T {
        guard var comps = URLComponents(string: "\(baseURL)\(path)") else {
            throw APIError.invalidURL
        }
        if !query.isEmpty {
            comps.queryItems = query
        }
        guard let url = comps.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("ManiFlix/2.0.2", forHTTPHeaderField: "User-Agent")
        if forceRefresh {
            req.cachePolicy = .reloadIgnoringLocalCacheData
        }

        if let token = token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let capturedSession = self.session
        let capturedReq = req
        let executeFetch: @Sendable () async throws -> Data = {
            let (data, response) = try await capturedSession.data(for: capturedReq)
            guard let http = response as? HTTPURLResponse else {
                throw APIError.badStatus(0, "Không nhận được phản hồi HTTP")
            }
            guard (200..<300).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
                throw APIError.badStatus(http.statusCode, msg)
            }
            return data
        }

        let data: Data
        if method == "GET" && body == nil && cacheTTL > 0 {
            let tokKey = (token?.isEmpty == false) ? String(token!.hashValue) : "guest"
            let key = "\(url.absoluteString)|\(tokKey)"
            data = try await memoryCache.fetchCoalesced(
                key: key,
                ttl: cacheTTL,
                forceRefresh: forceRefresh,
                loader: executeFetch
            )
        } else {
            data = try await executeFetch()
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }

    func fetchBootstrapDiscover(token: String? = nil, forceRefresh: Bool = false) async throws -> BootstrapDiscoverResponse {
        let ttl: TimeInterval = (token?.isEmpty == false) ? 20 : 60
        return try await request(
            path: "/api/bootstrap/discover",
            token: token,
            cacheTTL: ttl,
            forceRefresh: forceRefresh
        )
    }

    func fetchMovies(page: Int = 1) async throws -> MoviesPageResponse {
        try await request(path: "/api/movies", query: [URLQueryItem(name: "page", value: "\(page)")], cacheTTL: 60)
    }

    func fetchCategory(type: String, page: Int = 1) async throws -> CategoryPageResponse {
        try await request(
            path: "/api/category",
            query: [
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "page", value: "\(page)")
            ],
            cacheTTL: 60
        )
    }

    func fetchGenre(slug: String, page: Int = 1) async throws -> CategoryPageResponse {
        try await request(
            path: "/api/the-loai",
            query: [
                URLQueryItem(name: "slug", value: slug),
                URLQueryItem(name: "page", value: "\(page)")
            ],
            cacheTTL: 60
        )
    }

    func searchMovies(query: String, page: Int = 1) async throws -> SearchResponse {
        try await request(
            path: "/api/search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: "\(page)")
            ],
            cacheTTL: 60
        )
    }

    func fetchMovieDetail(slug: String) async throws -> MovieDetailResponse {
        let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        return try await request(path: "/api/movie/\(encoded)", cacheTTL: 180)
    }

    func fetchFranchise(slug: String) async throws -> FranchiseResponse {
        try await request(
            path: "/api/franchise",
            query: [URLQueryItem(name: "slug", value: slug)],
            cacheTTL: 180
        )
    }

    func fetchAdsMarkers(slug: String, ep: String, titleHint: String = "") async throws -> AdsResponse {
        let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        let digitsOnly = ep.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        let cleanEp = digitsOnly.isEmpty ? (ep.isEmpty ? "1" : ep) : String(Int(digitsOnly) ?? 1)
        let encodedEp = cleanEp.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "1"
        var query: [URLQueryItem] = []
        if !titleHint.isEmpty {
            query.append(URLQueryItem(name: "title", value: titleHint))
        }
        return try await request(
            path: "/api/ads/\(encodedSlug)/\(encodedEp)",
            query: query,
            cacheTTL: 180
        )
    }

    func login(username: String, password: String) async throws -> AuthResponse {
        try await request(
            path: "/api/auth/login",
            method: "POST",
            body: ["username": username, "password": password]
        )
    }

    func register(username: String, password: String, displayName: String) async throws -> AuthResponse {
        try await request(
            path: "/api/auth/register",
            method: "POST",
            body: ["username": username, "password": password, "displayName": displayName]
        )
    }

    func fetchMe(token: String) async throws -> MeResponse {
        try await request(path: "/api/auth/me", token: token)
    }

    func fetchHistory(token: String) async throws -> HistoryResponse {
        try await request(path: "/api/user/history", token: token)
    }

    func saveHistory(
        token: String,
        slug: String,
        name: String,
        poster: String,
        episodeIndex: Int,
        episodeName: String,
        currentTime: Double,
        duration: Double
    ) async {
        struct Ack: Codable { let success: Bool? }
        let body: [String: Any] = [
            "slug": slug,
            "name": name,
            "poster": poster,
            "episodeIndex": episodeIndex,
            "episodeName": episodeName,
            "currentTime": currentTime,
            "duration": duration
        ]
        _ = try? await request(path: "/api/user/history", method: "POST", body: body, token: token) as Ack
    }

    func deleteHistory(token: String, slug: String) async {
        struct Ack: Codable { let success: Bool? }
        _ = try? await request(path: "/api/user/history/delete", method: "POST", body: ["slug": slug], token: token) as Ack
    }

    func fetchFavorites(token: String) async throws -> FavoritesResponse {
        try await request(path: "/api/user/favorites", token: token)
    }

    func toggleFavorite(token: String, movie: MovieDetail) async throws -> FavoritesResponse {
        let body: [String: Any] = [
            "slug": movie.slug,
            "name": movie.name,
            "poster": movie.poster_url ?? movie.thumb_url ?? "",
            "year": movie.year?.value ?? 0,
            "quality": movie.quality ?? "HD",
            "lang": movie.lang ?? "Vietsub"
        ]
        return try await request(path: "/api/user/favorites/toggle", method: "POST", body: body, token: token)
    }

    func toggleFavoriteItem(token: String, item: MovieItem) async throws -> FavoritesResponse {
        let body: [String: Any] = [
            "slug": item.slug,
            "name": item.name,
            "poster": item.poster_url ?? item.thumb_url ?? "",
            "year": item.year?.value ?? 0,
            "quality": item.quality ?? "HD",
            "lang": item.lang ?? "Vietsub"
        ]
        return try await request(path: "/api/user/favorites/toggle", method: "POST", body: body, token: token)
    }

    func fetchAppVersion() async throws -> AppVersionResponse {
        try await request(path: "/api/app/version")
    }

    func saveUserTheme(token: String, presetId: String, accent: String, bg: String, surface: String) async throws {
        struct ThemeSaveAck: Codable { let success: Bool? }
        let body: [String: Any] = [
            "presetId": presetId,
            "accent": accent,
            "bg": bg,
            "surface": surface
        ]
        _ = try await request(path: "/api/user/theme", method: "POST", body: body, token: token) as ThemeSaveAck
    }
}
