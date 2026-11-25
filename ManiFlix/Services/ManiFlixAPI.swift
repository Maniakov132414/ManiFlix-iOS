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

final class ManiFlixAPI {
    static let shared = ManiFlixAPI()
    private let session: URLSession
    private let decoder = JSONDecoder()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 18
        config.timeoutIntervalForResource = 35
        self.session = URLSession(configuration: config)
    }

    private var baseURL: String {
        AppPreferences.shared.normalizedBaseURL
    }

    func cleanM3U8URL(from rawM3U8: String) -> URL? {
        guard var comps = URLComponents(string: "\(baseURL)/api/clean-m3u8") else { return nil }
        comps.queryItems = [URLQueryItem(name: "url", value: rawM3U8)]
        return comps.url
    }

    private func request<T: Decodable>(
        path: String,
        method: String = "GET",
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil,
        token: String? = nil
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
        req.setValue("ManiFlix-iOS/1.0.0", forHTTPHeaderField: "User-Agent")

        if let token = token, !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.badStatus(0, "Không nhận được phản hồi HTTP")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.badStatus(http.statusCode, msg)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decodingFailed(error.localizedDescription)
        }
    }

    func fetchMovies(page: Int = 1) async throws -> MoviesPageResponse {
        try await request(path: "/api/movies", query: [URLQueryItem(name: "page", value: "\(page)")])
    }

    func fetchCategory(type: String, page: Int = 1) async throws -> CategoryPageResponse {
        try await request(
            path: "/api/category",
            query: [
                URLQueryItem(name: "type", value: type),
                URLQueryItem(name: "page", value: "\(page)")
            ]
        )
    }

    func searchMovies(query: String, page: Int = 1) async throws -> SearchResponse {
        try await request(
            path: "/api/search",
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "page", value: "\(page)")
            ]
        )
    }

    func fetchMovieDetail(slug: String) async throws -> MovieDetailResponse {
        let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        return try await request(path: "/api/movie/\(encoded)")
    }

    func fetchFranchise(slug: String) async throws -> FranchiseResponse {
        try await request(
            path: "/api/franchise",
            query: [URLQueryItem(name: "slug", value: slug)]
        )
    }

    func fetchAdsMarkers(slug: String, ep: String) async throws -> AdsResponse {
        let encodedSlug = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        return try await request(
            path: "/api/ads/\(encodedSlug)",
            query: [URLQueryItem(name: "ep", value: ep)]
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

    func fetchAppVersion() async throws -> AppVersionResponse {
        try await request(path: "/api/app/version")
    }
}
