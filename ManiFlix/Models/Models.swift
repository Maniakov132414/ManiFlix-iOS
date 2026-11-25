import Foundation

struct FlexibleString: Codable, Hashable {
    let value: String

    init(_ value: String) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) {
            self.value = str
        } else if let intVal = try? container.decode(Int.self) {
            self.value = String(intVal)
        } else if let dblVal = try? container.decode(Double.self) {
            self.value = String(Int(dblVal))
        } else if container.decodeNil() {
            self.value = ""
        } else {
            self.value = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct FlexibleInt: Codable, Hashable {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            self.value = intVal
        } else if let strVal = try? container.decode(String.self), let parsed = Int(strVal.trimmingCharacters(in: .whitespacesAndNewlines)) {
            self.value = parsed
        } else if let dblVal = try? container.decode(Double.self) {
            self.value = Int(dblVal)
        } else {
            self.value = 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct MoviesPageResponse: Codable {
    let status: Bool?
    let msg: String?
    let items: [MovieItem]?
    let pagination: PaginationInfo?
}

struct CategoryPageResponse: Codable {
    let status: Bool?
    let titlePage: String?
    let items: [MovieItem]?
    let APP_DOMAIN_CDN_IMAGE: String?
}

struct SearchResponse: Codable {
    let items: [MovieItem]?
    let totalItems: Int?
    let hasMore: Bool?
}

struct PaginationInfo: Codable {
    let totalItems: Int?
    let totalItemsPerPage: Int?
    let currentPage: Int?
    let totalPages: Int?
}

struct MovieTag: Codable, Hashable, Identifiable {
    var id: String { slug ?? name ?? UUID().uuidString }
    let idRaw: FlexibleString?
    let name: String?
    let slug: String?

    enum CodingKeys: String, CodingKey {
        case idRaw = "id"
        case name, slug
    }
}

struct MovieItem: Codable, Identifiable, Hashable {
    var id: String { slug }
    let _id: String?
    let name: String
    let slug: String
    let origin_name: String?
    let poster_url: String?
    let thumb_url: String?
    let year: FlexibleInt?
    let type: String?
    let quality: String?
    let lang: String?
    let episode_current: String?
    let time: String?
    let category: [MovieTag]?
    let country: [MovieTag]?

    var displayPosterURL: URL? {
        ImageURLResolver.resolve(poster_url ?? thumb_url)
    }

    var displayThumbURL: URL? {
        ImageURLResolver.resolve(thumb_url ?? poster_url)
    }
}

struct MovieDetailResponse: Codable {
    let status: Bool?
    let msg: String?
    let movie: MovieDetail?
    let episodes: [EpisodeServer]?
}

struct MovieDetail: Codable, Hashable {
    let _id: String?
    let name: String
    let slug: String
    let origin_name: String?
    let content: String?
    let type: String?
    let status: String?
    let poster_url: String?
    let thumb_url: String?
    let trailer_url: String?
    let time: String?
    let episode_current: String?
    let episode_total: FlexibleString?
    let quality: String?
    let lang: String?
    let year: FlexibleInt?
    let actor: [String]?
    let director: [String]?
    let category: [MovieTag]?
    let country: [MovieTag]?

    var displayPosterURL: URL? {
        ImageURLResolver.resolve(poster_url ?? thumb_url)
    }

    var displayThumbURL: URL? {
        ImageURLResolver.resolve(thumb_url ?? poster_url)
    }

    var plainSynopsis: String {
        guard let raw = content else { return "" }
        return raw
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct EpisodeServer: Codable, Identifiable, Hashable {
    var id: String { server_name }
    let server_name: String
    let is_ai: Bool?
    let server_data: [EpisodeItem]
}

struct EpisodeItem: Codable, Identifiable, Hashable {
    var id: String { "\(slug)-\(name)" }
    let name: String
    let slug: String
    let filename: String?
    let link_embed: String?
    let link_m3u8: String?
}

struct FranchiseResponse: Codable {
    let status: Bool?
    let baseTitle: String?
    let seasons: [FranchiseSeason]?
}

struct FranchiseSeason: Codable, Identifiable, Hashable {
    var id: String { slug }
    let name: String?
    let isRecap: Bool?
    let fullTitle: String?
    let slug: String
    let year: FlexibleInt?
    let seasonNumber: FlexibleInt?
    let poster: String?
    let quality: String?
    let lang: String?
    let episodeCurrent: String?
}

struct AdsResponse: Codable {
    let success: Bool?
    let slug: String?
    let ep: String?
    let markers: [AdMarker]?
}

struct AdMarker: Codable, Identifiable, Hashable {
    var id: String { idRaw ?? "\(type ?? "mark")-\(start)-\(end)" }
    let idRaw: String?
    let type: String?
    let mode: String? // "cut", "skip", "mark"
    let start: Double
    let end: Double
    let openEnd: Bool?
    let label: String?
    let source: String?

    enum CodingKeys: String, CodingKey {
        case idRaw = "id"
        case type, mode, start, end, openEnd, label, source
    }
}

struct UserThemeConfig: Codable, Hashable {
    let presetId: String?
    let accent: String?
    let accent2: String?
    let bg: String?
    let surface: String?
}

struct UserInfo: Codable, Hashable {
    let username: String
    let displayName: String?
    let favoritesCount: Int?
    let historyCount: Int?
    let themeConfig: UserThemeConfig?
}

struct AuthResponse: Codable {
    let success: Bool?
    let error: String?
    let token: String?
    let user: UserInfo?
}

struct MeResponse: Codable {
    let user: UserInfo?
}

struct HistoryEntry: Codable, Identifiable, Hashable {
    var id: String { "\(slug)-\(episodeIndex ?? 0)" }
    let slug: String
    let name: String?
    let poster: String?
    let episodeIndex: Int?
    let episodeName: String?
    let currentTime: Double?
    let duration: Double?
    let updatedAt: Double?

    var displayPosterURL: URL? {
        ImageURLResolver.resolve(poster)
    }

    var progressRatio: Double {
        guard let cur = currentTime, let dur = duration, dur > 1 else { return 0 }
        return min(max(cur / dur, 0), 1)
    }
}

struct HistoryResponse: Codable {
    let history: [HistoryEntry]?
}

struct FavoriteEntry: Codable, Identifiable, Hashable {
    var id: String { slug }
    let slug: String
    let name: String?
    let poster: String?
    let year: FlexibleInt?
    let quality: String?
    let lang: String?
    let addedAt: Double?

    var displayPosterURL: URL? {
        ImageURLResolver.resolve(poster)
    }
}

struct FavoritesResponse: Codable {
    let favorites: [FavoriteEntry]?
}

struct AppVariantInfo: Codable, Identifiable, Hashable {
    var id: String { key }
    let key: String
    let name: String
    let minOS: String?
    let hasPlugins: Bool?
    let downloadUrl: String
}

struct AppVersionResponse: Codable {
    let latestVersion: String
    let minRequiredVersion: String?
    let mode: String?
    let forceUpdate: Bool?
    let title: String?
    let releaseNotes: String?
    let downloadUrl: String?
    let releasePageUrl: String?
    let altStoreSourceUrl: String?
    let variants: [AppVariantInfo]?
    let updatedAt: Double?
}

enum ImageURLResolver {
    static func resolve(_ raw: String?) -> URL? {
        guard var trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed)
        }
        if trimmed.hasPrefix("//") {
            return URL(string: "https:" + trimmed)
        }
        if trimmed.hasPrefix("/") {
            trimmed = String(trimmed.dropFirst())
        }
        if trimmed.hasPrefix("uploads/") {
            return URL(string: "https://phimimg.com/" + trimmed)
        }
        return URL(string: "https://phimimg.com/upload/vod/" + trimmed)
    }
}
