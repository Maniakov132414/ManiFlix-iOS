import WidgetKit
import SwiftUI
import UIKit
import CryptoKit
import ImageIO

private let widgetCrimson = Color(red: 0.98, green: 0.176, blue: 0.282)
private let widgetBgColor = Color(red: 0.06, green: 0.06, blue: 0.07)

enum WidgetProviderMode {
    case smart
    case continueWatching
    case forYou
    case latest
}

private struct SyncedHistoryItem: Codable {
    let slug: String
    let name: String
    let poster: String?
    let episodeIndex: Int?
    let episodeName: String?
    let currentTime: Double?
    let duration: Double?
}

private struct SyncedFavoriteItem: Codable {
    let slug: String
    let name: String
    let poster: String?
}

private struct SyncedWidgetPayload: Codable {
    let history: [SyncedHistoryItem]?
    let favorites: [SyncedFavoriteItem]?
    let likedSlugs: [String]?
    let blockedSlugs: [String]?
    let widgetMode: String?
    let updatedAt: Double?
}

private struct SyncedWidgetEnvelope: Codable {
    let payload: SyncedWidgetPayload?
}

struct WidgetFilmItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let slug: String
    let quality: String
    let posterJPEG: Data?
    let progress: Double?
    let isResume: Bool
}

struct ManiFlixWidgetEntry: TimelineEntry {
    let date: Date
    let headerLabel: String
    let primarySectionTitle: String
    let items: [WidgetFilmItem]
    let secondarySectionTitle: String?
    let secondaryItems: [WidgetFilmItem]
    let isPlaceholder: Bool
}

struct ManiFlixTimelineProvider: TimelineProvider {
    let widgetKind: WidgetProviderMode

    private static let appGroupSuite = "group.bond.maniakov.maniflix"
    private static let localPayloadKey = "maniflix.widgetSyncPayload.v1"

    private static let skeletonItems: [WidgetFilmItem] = (0..<4).map { idx in
        WidgetFilmItem(
            id: "placeholder-\(idx)",
            title: "Đang cập nhật phim",
            subtitle: "Vietsub",
            slug: "",
            quality: "HD",
            posterJPEG: nil,
            progress: nil,
            isResume: false
        )
    }

    func placeholder(in context: Context) -> ManiFlixWidgetEntry {
        ManiFlixWidgetEntry(
            date: Date(),
            headerLabel: defaultHeaderTitle(for: widgetKind),
            primarySectionTitle: defaultHeaderTitle(for: widgetKind),
            items: Self.skeletonItems,
            secondarySectionTitle: nil,
            secondaryItems: [],
            isPlaceholder: true
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ManiFlixWidgetEntry) -> Void) {
        Task {
            let entry = await buildEntry(
                family: context.family,
                includeImages: !context.isPreview
            )
            completion(entry)
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ManiFlixWidgetEntry>) -> Void) {
        Task {
            let entry = await buildEntry(
                family: context.family,
                includeImages: true
            )
            let nextReload = Calendar.current.date(byAdding: .minute, value: 30, to: Date())
                ?? Date().addingTimeInterval(1800)
            completion(Timeline(entries: [entry], policy: .after(nextReload)))
        }
    }

    private func defaultHeaderTitle(for mode: WidgetProviderMode) -> String {
        switch mode {
        case .smart: return "Đang xem & Đề xuất"
        case .continueWatching: return "Đang xem gần đây"
        case .forYou: return "Đề xuất cho bạn"
        case .latest: return "Mới cập nhật"
        }
    }

    private func resolvedEffectiveMode(payload: SyncedWidgetPayload?) -> WidgetProviderMode {
        guard widgetKind == .smart else { return widgetKind }
        switch payload?.widgetMode {
        case "continueWatching": return .continueWatching
        case "forYou": return .forYou
        case "latest": return .latest
        default: return .smart
        }
    }

    private func buildEntry(family: WidgetFamily, includeImages: Bool) async -> ManiFlixWidgetEntry {
        let payload = await loadSyncedPayload()
        let blocked = Set(payload?.blockedSlugs ?? [])
        let effectiveMode = resolvedEffectiveMode(payload: payload)

        let continueRaw = buildContinueItems(payload: payload, blocked: blocked)

        switch effectiveMode {
        case .latest:
            let latest = await fetchLatestItems(blocked: blocked, limit: 4, includeImages: includeImages)
            return makeSingleSectionEntry(
                headerLabel: "Mới cập nhật",
                items: latest
            )

        case .forYou:
            let forYou = await fetchForYouItems(payload: payload, blocked: blocked, limit: 4, includeImages: includeImages)
            return makeSingleSectionEntry(
                headerLabel: "Đề xuất cho bạn",
                items: forYou
            )

        case .continueWatching:
            if !continueRaw.isEmpty {
                let hydrated = await hydrateImages(for: Array(continueRaw.prefix(4)), includeImages: includeImages)
                return makeSingleSectionEntry(
                    headerLabel: "Đang xem gần đây",
                    items: hydrated
                )
            }
            let fallbackForYou = await fetchForYouItems(payload: payload, blocked: blocked, limit: 4, includeImages: includeImages)
            return makeSingleSectionEntry(
                headerLabel: "Đề xuất cho bạn",
                items: fallbackForYou
            )

        case .smart:
            let forYou = await fetchForYouItems(payload: payload, blocked: blocked, limit: 4, includeImages: includeImages)
            if continueRaw.isEmpty {
                return makeSingleSectionEntry(
                    headerLabel: "Đề xuất cho bạn",
                    items: forYou
                )
            }

            if family == .systemLarge {
                let topContinue = await hydrateImages(for: Array(continueRaw.prefix(2)), includeImages: includeImages)
                let topForYou = Array(forYou.prefix(2))
                return ManiFlixWidgetEntry(
                    date: Date(),
                    headerLabel: "Thông minh",
                    primarySectionTitle: "Đang xem gần đây",
                    items: topContinue,
                    secondarySectionTitle: topForYou.isEmpty ? nil : "Đề xuất cho bạn",
                    secondaryItems: topForYou,
                    isPlaceholder: false
                )
            }

            if family == .systemSmall {
                let topOne = await hydrateImages(for: Array(continueRaw.prefix(1)), includeImages: includeImages)
                return makeSingleSectionEntry(
                    headerLabel: "Đang xem gần đây",
                    items: topOne
                )
            }

            // systemMedium: 3 slots prioritizing Continue Watching + For You
            let continueSlice = await hydrateImages(for: Array(continueRaw.prefix(2)), includeImages: includeImages)
            let continueSlugs = Set(continueSlice.map(\.slug))
            let extraForYou = forYou.filter { !continueSlugs.contains($0.slug) }
            let combined = Array((continueSlice + extraForYou).prefix(3))
            return ManiFlixWidgetEntry(
                date: Date(),
                headerLabel: "Đang xem & Đề xuất",
                primarySectionTitle: "Đang xem & Đề xuất",
                items: combined,
                secondarySectionTitle: nil,
                secondaryItems: [],
                isPlaceholder: combined.isEmpty
            )
        }
    }

    private func makeSingleSectionEntry(headerLabel: String, items: [WidgetFilmItem]) -> ManiFlixWidgetEntry {
        if items.isEmpty {
            return ManiFlixWidgetEntry(
                date: Date(),
                headerLabel: headerLabel,
                primarySectionTitle: headerLabel,
                items: Self.skeletonItems,
                secondarySectionTitle: nil,
                secondaryItems: [],
                isPlaceholder: true
            )
        }
        return ManiFlixWidgetEntry(
            date: Date(),
            headerLabel: headerLabel,
            primarySectionTitle: headerLabel,
            items: items,
            secondarySectionTitle: nil,
            secondaryItems: [],
            isPlaceholder: false
        )
    }

    private func hashedVendorKey() async -> String {
        let vendorId = await MainActor.run {
            UIDevice.current.identifierForVendor?.uuidString ?? "maniflix-default-device"
        }
        let raw = "mf-wid:" + vendorId
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func loadSyncedPayload() async -> SyncedWidgetPayload? {
        var localPayload: SyncedWidgetPayload?
        if let localData = UserDefaults(suiteName: Self.appGroupSuite)?.data(forKey: Self.localPayloadKey),
           let decoded = try? JSONDecoder().decode(SyncedWidgetPayload.self, from: localData) {
            localPayload = decoded
        }

        let key = await hashedVendorKey()
        guard let url = URL(string: "https://phim.maniakov.bond/api/widget-sync?key=\(key)") else {
            return localPayload
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 7
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue("ManiFlixWidget/1.1.1", forHTTPHeaderField: "User-Agent")

        if let (data, response) = try? await URLSession.shared.data(for: req),
           let http = response as? HTTPURLResponse,
           (200..<300).contains(http.statusCode) {
            let remotePayload: SyncedWidgetPayload? = {
                if let env = try? JSONDecoder().decode(SyncedWidgetEnvelope.self, from: data),
                   let p = env.payload {
                    return p
                }
                return try? JSONDecoder().decode(SyncedWidgetPayload.self, from: data)
            }()

            if let remote = remotePayload {
                if let local = localPayload, (local.updatedAt ?? 0) > (remote.updatedAt ?? 0) {
                    return local
                }
                return remote
            }
        }
        return localPayload
    }

    private func buildContinueItems(payload: SyncedWidgetPayload?, blocked: Set<String>) -> [WidgetFilmItem] {
        guard let history = payload?.history, !history.isEmpty else { return [] }
        return history
            .filter { !$0.slug.isEmpty && !blocked.contains($0.slug) }
            .map { h in
                let cur = h.currentTime ?? 0
                let dur = h.duration ?? 0
                let ratio = dur > 1 ? min(max(cur / dur, 0.02), 1.0) : 0.05
                let pct = dur > 1 ? Int(round(min(max(cur / dur, 0), 1) * 100)) : 0
                let epTitle = (h.episodeName?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
                    ?? "Tập \((h.episodeIndex ?? 0) + 1)"
                let subtitle = pct > 0 ? "\(epTitle) · \(pct)%" : epTitle
                return WidgetFilmItem(
                    id: "cont-\(h.slug)",
                    title: h.name,
                    subtitle: subtitle,
                    slug: h.slug,
                    quality: h.poster ?? "",
                    posterJPEG: nil,
                    progress: ratio,
                    isResume: true
                )
            }
    }

    private func hydrateImages(for items: [WidgetFilmItem], includeImages: Bool) async -> [WidgetFilmItem] {
        var result: [WidgetFilmItem] = []
        for item in items {
            var jpeg: Data?
            if includeImages, let imgURL = resolvePoster(item.quality) {
                jpeg = await fetchDownsampledJPEG(from: imgURL)
            }
            result.append(WidgetFilmItem(
                id: item.id,
                title: item.title,
                subtitle: item.subtitle,
                slug: item.slug,
                quality: "Tiếp tục",
                posterJPEG: jpeg,
                progress: item.progress,
                isResume: item.isResume
            ))
        }
        return result
    }

    private struct RawMovie: Decodable {
        let name: String
        let slug: String
        let origin_name: String?
        let type: String?
        let quality: String?
        let lang: String?
        let episode_current: String?
        let poster_url: String?
        let thumb_url: String?
    }

    private struct RawResponse: Decodable {
        let items: [RawMovie]?
    }

    private func fetchMovieList(urlString: String) async -> [RawMovie] {
        guard let url = URL(string: urlString) else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("ManiFlixWidget/1.1.1", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: req),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(RawResponse.self, from: data) else {
            return []
        }
        return decoded.items ?? []
    }

    private func fetchLatestItems(blocked: Set<String>, limit: Int, includeImages: Bool) async -> [WidgetFilmItem] {
        let raw = await fetchMovieList(urlString: "https://phim.maniakov.bond/api/movies?page=1")
        let filtered = raw.filter { !blocked.contains($0.slug) }
        return await convertRawMovies(Array(filtered.prefix(limit)), includeImages: includeImages, idPrefix: "lat")
    }

    private func fetchForYouItems(
        payload: SyncedWidgetPayload?,
        blocked: Set<String>,
        limit: Int,
        includeImages: Bool
    ) async -> [WidgetFilmItem] {
        async let seriesTask = fetchMovieList(urlString: "https://phim.maniakov.bond/api/category?type=phim-bo&page=1")
        async let animeTask = fetchMovieList(urlString: "https://phim.maniakov.bond/api/category?type=hoat-hinh&page=1")
        async let page2Task = fetchMovieList(urlString: "https://phim.maniakov.bond/api/movies?page=2")

        let (series, anime, page2) = await (seriesTask, animeTask, page2Task)
        let watchedSlugs = Set((payload?.history ?? []).map(\.slug))

        var tasteTokens = Set<String>()
        for h in payload?.history ?? [] {
            for tok in tokenize(h.name) { tasteTokens.insert(tok) }
            for tok in tokenize(h.slug) { tasteTokens.insert(tok) }
        }
        for f in payload?.favorites ?? [] {
            for tok in tokenize(f.name) { tasteTokens.insert(tok) }
            for tok in tokenize(f.slug) { tasteTokens.insert(tok) }
        }
        for s in payload?.likedSlugs ?? [] {
            for tok in tokenize(s) { tasteTokens.insert(tok) }
        }

        let prefersSeries = (payload?.history.map { $0.contains(where: { ($0.episodeIndex ?? 0) > 0 || ($0.episodeName ?? "").localizedCaseInsensitiveContains("tập") }) } ?? false)
        let combinedRaw = series + anime + page2

        var seen = Set<String>()
        var scored: [(movie: RawMovie, score: Int, order: Int)] = []
        for (idx, m) in combinedRaw.enumerated() {
            guard !m.slug.isEmpty,
                  seen.insert(m.slug).inserted,
                  !blocked.contains(m.slug),
                  !watchedSlugs.contains(m.slug) else {
                continue
            }
            var score = 0
            let movieTokens = tokenize(m.name).union(tokenize(m.origin_name ?? "")).union(tokenize(m.slug))
            let overlap = movieTokens.intersection(tasteTokens).count
            score += overlap * 6
            if prefersSeries && (m.type == "series" || (m.episode_current ?? "").localizedCaseInsensitiveContains("tập")) {
                score += 3
            }
            if (m.quality ?? "").localizedCaseInsensitiveContains("HD") {
                score += 1
            }
            scored.append((m, score, idx))
        }

        let ranked = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.order < rhs.order
        }
        let chosen = Array(ranked.prefix(limit).map(\.movie))
        if chosen.isEmpty {
            return await fetchLatestItems(blocked: blocked, limit: limit, includeImages: includeImages)
        }
        return await convertRawMovies(chosen, includeImages: includeImages, idPrefix: "rec")
    }

    private func tokenize(_ text: String) -> Set<String> {
        let parts = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 3 }
        return Set(parts)
    }

    private func convertRawMovies(_ movies: [RawMovie], includeImages: Bool, idPrefix: String) async -> [WidgetFilmItem] {
        var output: [WidgetFilmItem] = []
        for m in movies {
            var thumbData: Data?
            if includeImages, let imgURL = resolvePoster(m.poster_url ?? m.thumb_url) {
                thumbData = await fetchDownsampledJPEG(from: imgURL)
            }
            output.append(WidgetFilmItem(
                id: "\(idPrefix)-\(m.slug)",
                title: m.name,
                subtitle: m.episode_current ?? m.origin_name ?? "Đề xuất cho bạn",
                slug: m.slug,
                quality: m.quality ?? "HD",
                posterJPEG: thumbData,
                progress: nil,
                isResume: false
            ))
        }
        return output
    }

    private func resolvePoster(_ raw: String?) -> URL? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return URL(string: s) }
        if s.hasPrefix("/") { s.removeFirst() }
        if s.hasPrefix("upload/") || s.hasPrefix("uploads/") || s.contains("/") {
            return URL(string: "https://phimimg.com/" + s)
        }
        return URL(string: "https://phimimg.com/upload/vod/" + s)
    }

    private func fetchDownsampledJPEG(from url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 7
        guard let (data, _) = try? await URLSession.shared.data(for: req) else { return nil }
        let sourceOpts = [kCGImageSourceShouldCache: false] as CFDictionary
        if let src = CGImageSourceCreateWithData(data as CFData, sourceOpts) {
            let thumbOpts: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 220
            ]
            if let cgImg = CGImageSourceCreateThumbnailAtIndex(src, 0, thumbOpts as CFDictionary) {
                return UIImage(cgImage: cgImg).jpegData(compressionQuality: 0.75)
            }
        }
        guard let fallback = UIImage(data: data) else { return nil }
        return fallback.jpegData(compressionQuality: 0.72)
    }
}

struct ManiFlixWidgetView: View {
    let entry: ManiFlixWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallLayout
            case .systemLarge:
                largeLayout
            default:
                mediumLayout
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow(entry.headerLabel)
            if let first = entry.items.first {
                Link(destination: deepLink(for: first)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            posterThumb(first.posterJPEG, width: 42, height: 60)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(first.quality)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(first.isResume ? .white : Color(white: 0.85))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(first.isResume ? widgetCrimson : Color.white.opacity(0.14))
                                    .cornerRadius(4)
                                Text(first.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(white: 0.65))
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(first.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(first.progress == nil ? 2 : 1)

                        if let prog = first.progress {
                            crimsonProgressBar(prog)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(widgetBgColor)
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow(entry.headerLabel)
            HStack(spacing: 10) {
                ForEach(entry.items.prefix(3)) { item in
                    Link(destination: deepLink(for: item)) {
                        VStack(alignment: .leading, spacing: 4) {
                            ZStack(alignment: .topTrailing) {
                                ZStack(alignment: .bottom) {
                                    posterThumb(item.posterJPEG, width: nil, height: 76)
                                    if let prog = item.progress {
                                        crimsonProgressBar(prog)
                                            .padding(.horizontal, 4)
                                            .padding(.bottom, 4)
                                    }
                                }
                                Text(item.quality)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(item.isResume ? widgetCrimson.opacity(0.92) : Color.black.opacity(0.72))
                                    .cornerRadius(4)
                                    .padding(4)
                            }
                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(.system(size: 9.5))
                                .foregroundColor(Color(white: 0.58))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(widgetBgColor)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !entry.secondaryItems.isEmpty {
                headerRow(entry.primarySectionTitle)
                ForEach(entry.items.prefix(2)) { item in
                    largeRow(item)
                }

                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.8)
                    .padding(.vertical, 2)

                if let secTitle = entry.secondarySectionTitle {
                    sectionSubHeader(secTitle)
                }
                ForEach(entry.secondaryItems.prefix(2)) { item in
                    largeRow(item)
                }
            } else {
                headerRow(entry.primarySectionTitle)
                ForEach(entry.items.prefix(4)) { item in
                    largeRow(item)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(widgetBgColor)
    }

    private func largeRow(_ item: WidgetFilmItem) -> some View {
        Link(destination: deepLink(for: item)) {
            HStack(spacing: 10) {
                posterThumb(item.posterJPEG, width: 42, height: 58)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text(item.subtitle)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(white: 0.6))
                        .lineLimit(1)
                    if let prog = item.progress {
                        crimsonProgressBar(prog)
                            .padding(.top, 1)
                    }
                }
                Spacer()
                if item.isResume {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(widgetCrimson)
                        .clipShape(Circle())
                } else {
                    Text(item.quality)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(white: 0.85))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(5)
                }
            }
        }
    }

    private func headerRow(_ label: String) -> some View {
        HStack(spacing: 5) {
            Text("ManiFlix")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(widgetCrimson)
            Text("• \(label)")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(Color(white: 0.7))
                .lineLimit(1)
            Spacer()
        }
    }

    private func sectionSubHeader(_ label: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(white: 0.78))
            Spacer()
        }
    }

    private func crimsonProgressBar(_ value: Double) -> some View {
        ProgressView(value: min(max(value, 0), 1))
            .progressViewStyle(.linear)
            .tint(widgetCrimson)
            .background(Color.white.opacity(0.18))
            .cornerRadius(2)
            .scaleEffect(x: 1, y: 0.85, anchor: .center)
    }

    @ViewBuilder
    private func posterThumb(_ data: Data?, width: CGFloat?, height: CGFloat) -> some View {
        if let data = data, let uiImg = UIImage(data: data) {
            Image(uiImage: uiImg)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: width, height: height)
                .frame(maxWidth: width == nil ? .infinity : width)
                .clipped()
                .cornerRadius(7)
        } else {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color.white.opacity(0.08))
                .frame(width: width, height: height)
                .frame(maxWidth: width == nil ? .infinity : width)
        }
    }

    private func deepLink(for item: WidgetFilmItem) -> URL {
        let encoded = item.slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.slug
        if encoded.isEmpty {
            return URL(string: "maniflix://home")!
        }
        let suffix = item.isResume ? "?resume=1" : ""
        return URL(string: "maniflix://movie/\(encoded)\(suffix)")!
    }
}

struct ManiFlixSmartWidget: Widget {
    let kind = "ManiFlixHotWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ManiFlixTimelineProvider(widgetKind: .smart)) { entry in
            if #available(iOS 17.0, *) {
                ManiFlixWidgetView(entry: entry)
                    .containerBackground(widgetBgColor, for: .widget)
            } else {
                ManiFlixWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("ManiFlix Thông minh")
        .description("Tự động hiển thị phim đang xem gần đây và đề xuất cho bạn.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ManiFlixContinueWidget: Widget {
    let kind = "ManiFlixContinueWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ManiFlixTimelineProvider(widgetKind: .continueWatching)) { entry in
            if #available(iOS 17.0, *) {
                ManiFlixWidgetView(entry: entry)
                    .containerBackground(widgetBgColor, for: .widget)
            } else {
                ManiFlixWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Đang xem gần đây")
        .description("Tiếp tục xem nhanh phim đang theo dõi với thanh tiến độ.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ManiFlixForYouWidget: Widget {
    let kind = "ManiFlixForYouWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ManiFlixTimelineProvider(widgetKind: .forYou)) { entry in
            if #available(iOS 17.0, *) {
                ManiFlixWidgetView(entry: entry)
                    .containerBackground(widgetBgColor, for: .widget)
            } else {
                ManiFlixWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Đề xuất cho bạn")
        .description("Gợi ý phim hợp gu dựa trên lịch sử và tủ phim của bạn.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ManiFlixLatestOnlyWidget: Widget {
    let kind = "ManiFlixLatestOnlyWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ManiFlixTimelineProvider(widgetKind: .latest)) { entry in
            if #available(iOS 17.0, *) {
                ManiFlixWidgetView(entry: entry)
                    .containerBackground(widgetBgColor, for: .widget)
            } else {
                ManiFlixWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("Phim mới cập nhật")
        .description("Xem nhanh các phim vừa lên sóng trên ManiFlix.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct ManiFlixWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ManiFlixSmartWidget()
        ManiFlixContinueWidget()
        ManiFlixForYouWidget()
        ManiFlixLatestOnlyWidget()
    }
}
