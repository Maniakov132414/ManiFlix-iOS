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
    let _id: FlexibleString?
    let name: String
    let slug: String
    let origin_name: String?
    let poster_url: String?
    let thumb_url: String?
    let year: FlexibleInt?
    let type: String?
    let quality: String?
    let lang: String?
    var sub_langs: [String]? = nil
    var vi_name: String? = nil
    var en_name: String? = nil
    var romaji_name: String? = nil
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

    func localizedPrimaryTitle(_ uiLang: String) -> String {
        TitleLocalizer.resolve(
            uiLang: uiLang,
            name: name,
            originName: origin_name,
            viName: vi_name,
            enName: en_name,
            romajiName: romaji_name,
            slug: slug
        ).primary
    }

    func localizedSecondaryTitle(_ uiLang: String) -> String? {
        let sec = TitleLocalizer.resolve(
            uiLang: uiLang,
            name: name,
            originName: origin_name,
            viName: vi_name,
            enName: en_name,
            romajiName: romaji_name,
            slug: slug
        ).secondary
        return sec.isEmpty ? nil : sec
    }
}

struct MovieDetailResponse: Codable {
    let status: Bool?
    let msg: String?
    let movie: MovieDetail?
    let episodes: [EpisodeServer]?
}

struct MovieDetail: Codable, Hashable {
    let _id: FlexibleString?
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
    var sub_langs: [String]? = nil
    var vi_name: String? = nil
    var en_name: String? = nil
    var romaji_name: String? = nil
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

    func localizedPrimaryTitle(_ uiLang: String) -> String {
        TitleLocalizer.resolve(
            uiLang: uiLang,
            name: name,
            originName: origin_name,
            viName: vi_name,
            enName: en_name,
            romajiName: romaji_name,
            slug: slug
        ).primary
    }

    func localizedSecondaryTitle(_ uiLang: String) -> String? {
        let sec = TitleLocalizer.resolve(
            uiLang: uiLang,
            name: name,
            originName: origin_name,
            viName: vi_name,
            enName: en_name,
            romajiName: romaji_name,
            slug: slug
        ).secondary
        return sec.isEmpty ? nil : sec
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
    let baseTitleVi: String?
    let baseTitleEn: String?
    let baseTitleRomaji: String?
    let seasons: [FranchiseSeason]?

    func localizedHeader(uiLang: String, count: Int) -> String {
        let isEn = uiLang == "en"
        let rawBase = isEn
            ? ((baseTitleEn ?? "").isEmpty ? (baseTitle ?? "") : (baseTitleEn ?? ""))
            : ((baseTitleVi ?? "").isEmpty ? (baseTitle ?? "") : (baseTitleVi ?? ""))
        let cleanBase = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanBase.isEmpty {
            return isEn ? "Franchise (\(count) parts)" : "Các phần phim (\(count))"
        }
        return isEn ? "Franchise: \(cleanBase) • \(count) parts" : "Các phần phim: \(cleanBase) • \(count) phần"
    }
}

struct FranchiseSeason: Codable, Identifiable, Hashable {
    var id: String { slug }
    let sortIndex: FlexibleInt?
    let name: String?
    let nameVi: String?
    let nameEn: String?
    let vi_name: String?
    let en_name: String?
    let romaji_name: String?
    let isRecap: Bool?
    let fullTitle: String?
    let originName: String?
    let slug: String
    let year: FlexibleInt?
    let seasonNumber: FlexibleInt?
    let movieNumber: FlexibleInt?
    let poster: String?
    let quality: String?
    let lang: String?
    let episodeCurrent: String?

    var displayFullTitle: String {
        let short = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !short.isEmpty { return short }
        let full = (fullTitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return full.isEmpty ? slug : full
    }

    func localizedLabel(uiLang: String, meta: FranchiseResponse? = nil, allSeasons: [FranchiseSeason] = []) -> String {
        let isEn = uiLang == "en"
        let explicit = (isEn ? (nameEn ?? name) : (nameVi ?? name))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallbackRaw = explicit.isEmpty ? ((fullTitle ?? slug).trimmingCharacters(in: .whitespacesAndNewlines)) : explicit
        let hasSeason2 = allSeasons.contains { ($0.seasonNumber?.value ?? 0) >= 2 }
        return TitleLocalizer.stripFranchisePrefix(
            label: fallbackRaw,
            uiLang: uiLang,
            prefixes: [meta?.baseTitleVi, meta?.baseTitleEn, meta?.baseTitleRomaji, meta?.baseTitle].compactMap { $0 },
            hasSeason2: hasSeason2
        )
    }
}

enum TitleLocalizer {
    private static let viDiacriticsPattern = "[àáạảãâầấậẩẫăằắặẳẵèéẹẻẽêềếệểễìíịỉĩòóọỏõôồốộổỗơờớợởỡùúụủũưừứựửữỳýỵỷỹđ]"
    private static let cjkCharPattern = "[\\u3040-\\u30ff\\u3400-\\u9fff\\uac00-\\ud7af]"
    private static let pureCJKPattern = "^[\\u3040-\\u30ff\\u3400-\\u9fff\\uac00-\\ud7af\\s\\d:!\\-–·.,'()]+$"
    private static let romajiTokenPattern = "\\b(no|wa|ga|wo|ni|kara|made|tachi|monogatari|kyoukai|kanata|shoujo|shounen|sekai|kimi|boku|ore|mahou|tensei|isekai|kuromukuro|shinonome|gekijou|saiban|kako|mirai|yaiba|kimetsu|shingeki|kyojin|jujutsu|kaisen|shippuuden|sousou|frieren|kusuriya|hitorigoto|dandadan)\\b"

    static func hasViDiacritics(_ text: String) -> Bool {
        text.range(of: viDiacriticsPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isPureCJK(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        return s.range(of: cjkCharPattern, options: .regularExpression) != nil &&
               s.range(of: pureCJKPattern, options: .regularExpression) != nil
    }

    static func looksRomaji(_ text: String) -> Bool {
        let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !hasViDiacritics(s), !isPureCJK(s) else { return false }
        return s.range(of: romajiTokenPattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func splitCandidates(_ raw: String?) -> [String] {
        guard let raw = raw, !raw.isEmpty else { return [] }
        let normalized = raw
            .replacingOccurrences(of: " • ", with: "\n")
            .replacingOccurrences(of: " / ", with: "\n")
            .replacingOccurrences(of: " | ", with: "\n")
            .replacingOccurrences(of: "; ", with: "\n")
        return normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func normKey(_ text: String) -> String {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: "đ", with: "d")
            .replacingOccurrences(of: "Đ", with: "d")
        return folded.replacingOccurrences(of: "[^a-zA-Z0-9]+", with: "", options: .regularExpression).lowercased()
    }

    static func resolve(
        uiLang: String,
        name: String?,
        originName: String?,
        viName: String? = nil,
        enName: String? = nil,
        romajiName: String? = nil,
        slug: String = ""
    ) -> (primary: String, secondary: String) {
        let rawName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let origParts = splitCandidates(originName)
        let explicitVi = (viName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitEn = (enName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitRomaji = (romajiName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        let viTitle: String = {
            if !explicitVi.isEmpty { return explicitVi }
            if hasViDiacritics(rawName) { return rawName }
            if let found = origParts.first(where: { hasViDiacritics($0) }) { return found }
            return ""
        }()

        let romajiTitle: String = {
            if !explicitRomaji.isEmpty { return explicitRomaji }
            if looksRomaji(rawName) { return rawName }
            if let found = origParts.first(where: { looksRomaji($0) }) { return found }
            return ""
        }()

        let enTitle: String = {
            if !explicitEn.isEmpty && !isPureCJK(explicitEn) { return explicitEn }
            let allCands = ([rawName] + origParts).filter { !$0.isEmpty }
            if let cleanEn = allCands.first(where: { !hasViDiacritics($0) && !isPureCJK($0) && !looksRomaji($0) }) {
                return cleanEn
            }
            if !romajiTitle.isEmpty { return romajiTitle }
            return ""
        }()

        let safeFallback: String = {
            for cand in [enTitle, romajiTitle, viTitle, isPureCJK(rawName) ? "" : rawName] + origParts.filter({ !isPureCJK($0) }) + [rawName, slug] {
                if !cand.isEmpty { return cand }
            }
            return slug
        }()

        let isEn = (uiLang == "en")
        let primary: String
        let secCandidates: [String]

        if isEn {
            primary = !enTitle.isEmpty ? enTitle : (!romajiTitle.isEmpty ? romajiTitle : safeFallback)
            secCandidates = [romajiTitle, viTitle] + origParts + [rawName]
        } else {
            if !viTitle.isEmpty {
                primary = viTitle
                secCandidates = [enTitle, romajiTitle] + origParts + [rawName]
            } else {
                primary = !enTitle.isEmpty ? enTitle : (!romajiTitle.isEmpty ? romajiTitle : safeFallback)
                secCandidates = [romajiTitle] + origParts + [rawName]
            }
        }

        let pKey = normKey(primary)
        var seen = Set<String>([pKey])
        var picked: [String] = []
        for cand in secCandidates {
            let trimmed = cand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !isPureCJK(trimmed) else { continue }
            let k = normKey(trimmed)
            guard !k.isEmpty, !seen.contains(k) else { continue }
            seen.insert(k)
            picked.append(trimmed)
            if picked.count >= 2 { break }
        }
        return (primary, picked.joined(separator: " • "))
    }

    static func stripFranchisePrefix(label: String, uiLang: String, prefixes: [String], hasSeason2: Bool) -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return hasSeason2 ? (uiLang == "en" ? "Season 1" : "Phần 1") : "TV Series"
        }
        let sortedPrefixes = prefixes
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
            .sorted { $0.count > $1.count }

        for prefix in sortedPrefixes {
            if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                let idx = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
                var rest = String(trimmed[idx...]).trimmingCharacters(in: .whitespacesAndNewlines)
                while let first = rest.first, [":", "-", "–", "—", "·", "|", "/"].contains(String(first)) {
                    rest.removeFirst()
                    rest = rest.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                if rest.isEmpty {
                    return hasSeason2 ? (uiLang == "en" ? "Season 1" : "Phần 1") : "TV Series"
                }
                if uiLang == "en" {
                    rest = rest.replacingOccurrences(of: "^Phần\\s+(\\d+)", with: "Season $1", options: [.regularExpression, .caseInsensitive])
                }
                return rest
            }
        }
        return trimmed
    }

    static func sortFranchiseSeasons(_ seasons: [FranchiseSeason], baseTitle: String?) -> [FranchiseSeason] {
        guard seasons.count > 1 else { return seasons }
        if seasons.contains(where: { $0.sortIndex != nil }) {
            return seasons.enumerated().sorted { lhs, rhs in
                let li = lhs.element.sortIndex?.value ?? (1000 + lhs.offset)
                let ri = rhs.element.sortIndex?.value ?? (1000 + rhs.offset)
                return li != ri ? li < ri : lhs.offset < rhs.offset
            }.map(\.element)
        }
        let baseNorm = normKey(baseTitle ?? "")
        return seasons.enumerated().sorted { lhs, rhs in
            let a = lhs.element
            let b = rhs.element
            let aRoot = !baseNorm.isEmpty && (normKey(a.fullTitle ?? "") == baseNorm || (a.name ?? "") == "TV Series")
            let bRoot = !baseNorm.isEmpty && (normKey(b.fullTitle ?? "") == baseNorm || (b.name ?? "") == "TV Series")
            let ay = a.year?.value ?? 9999
            let by = b.year?.value ?? 9999
            if ay != by { return ay < by }
            if aRoot != bRoot { return aRoot }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
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
        if trimmed.hasPrefix("upload/") || trimmed.hasPrefix("uploads/") || trimmed.contains("/") {
            return URL(string: "https://phimimg.com/" + trimmed)
        }
        return URL(string: "https://phimimg.com/upload/vod/" + trimmed)
    }
}
