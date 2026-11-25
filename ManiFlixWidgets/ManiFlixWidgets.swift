import WidgetKit
import SwiftUI
import UIKit

struct WidgetFilmItem: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let slug: String
    let quality: String
    let posterJPEG: Data?
}

struct ManiFlixWidgetEntry: TimelineEntry {
    let date: Date
    let items: [WidgetFilmItem]
    let isPlaceholder: Bool
}

struct ManiFlixTimelineProvider: TimelineProvider {
    private static let skeletonItems: [WidgetFilmItem] = (0..<4).map { idx in
        WidgetFilmItem(
            id: "placeholder-\(idx)",
            title: "Đang cập nhật phim",
            subtitle: "Vietsub",
            slug: "",
            quality: "HD",
            posterJPEG: nil
        )
    }

    func placeholder(in context: Context) -> ManiFlixWidgetEntry {
        ManiFlixWidgetEntry(date: Date(), items: Self.skeletonItems, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ManiFlixWidgetEntry) -> Void) {
        Task {
            let live = await loadLatestFilms(limit: 4, includeImages: !context.isPreview)
            if live.isEmpty {
                completion(ManiFlixWidgetEntry(date: Date(), items: Self.skeletonItems, isPlaceholder: true))
            } else {
                completion(ManiFlixWidgetEntry(date: Date(), items: live, isPlaceholder: false))
            }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ManiFlixWidgetEntry>) -> Void) {
        Task {
            let live = await loadLatestFilms(limit: 4, includeImages: true)
            let entry = ManiFlixWidgetEntry(
                date: Date(),
                items: live.isEmpty ? Self.skeletonItems : live,
                isPlaceholder: live.isEmpty
            )
            let nextReload = Calendar.current.date(byAdding: .minute, value: 45, to: Date()) ?? Date().addingTimeInterval(2700)
            completion(Timeline(entries: [entry], policy: .after(nextReload)))
        }
    }

    private func loadLatestFilms(limit: Int, includeImages: Bool) async -> [WidgetFilmItem] {
        struct RawMovie: Decodable {
            let name: String
            let slug: String
            let origin_name: String?
            let quality: String?
            let episode_current: String?
            let poster_url: String?
            let thumb_url: String?
        }
        struct RawResponse: Decodable {
            let items: [RawMovie]?
        }

        guard let url = URL(string: "https://phim.maniakov.bond/api/movies?page=1") else { return [] }
        var req = URLRequest(url: url)
        req.timeoutInterval = 12
        req.setValue("ManiFlixWidget/1.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(RawResponse.self, from: data)
            let slice = Array((decoded.items ?? []).prefix(limit))

            var output: [WidgetFilmItem] = []
            for m in slice {
                var thumbData: Data? = nil
                if includeImages, let imgURL = resolvePoster(m.poster_url ?? m.thumb_url) {
                    thumbData = await fetchDownsampledJPEG(from: imgURL)
                }
                output.append(WidgetFilmItem(
                    id: m.slug,
                    title: m.name,
                    subtitle: m.episode_current ?? m.origin_name ?? "Mới cập nhật",
                    slug: m.slug,
                    quality: m.quality ?? "HD",
                    posterJPEG: thumbData
                ))
            }
            return output
        } catch {
            return []
        }
    }

    private func resolvePoster(_ raw: String?) -> URL? {
        guard var s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        if s.hasPrefix("http://") || s.hasPrefix("https://") { return URL(string: s) }
        if s.hasPrefix("/") { s.removeFirst() }
        if s.hasPrefix("uploads/") { return URL(string: "https://phimimg.com/" + s) }
        return URL(string: "https://phimimg.com/upload/vod/" + s)
    }

    private func fetchDownsampledJPEG(from url: URL) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 7
        guard let (data, _) = try? await URLSession.shared.data(for: req),
              let image = UIImage(data: data) else { return nil }
        let targetSize = CGSize(width: 120, height: 176)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return resized.jpegData(compressionQuality: 0.72)
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
            headerRow
            if let first = entry.items.first {
                Link(destination: deepLink(for: first.slug)) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            posterThumb(first.posterJPEG, width: 42, height: 60)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(first.quality)
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundColor(Color(white: 0.85))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.14))
                                    .cornerRadius(4)
                                Text(first.subtitle)
                                    .font(.system(size: 10))
                                    .foregroundColor(Color(white: 0.6))
                                    .lineLimit(2)
                            }
                        }
                        Spacer(minLength: 0)
                        Text(first.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }

    private var mediumLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            headerRow
            HStack(spacing: 10) {
                ForEach(entry.items.prefix(3)) { item in
                    Link(destination: deepLink(for: item.slug)) {
                        VStack(alignment: .leading, spacing: 5) {
                            ZStack(alignment: .topTrailing) {
                                posterThumb(item.posterJPEG, width: nil, height: 78)
                                Text(item.quality)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.72))
                                    .cornerRadius(4)
                                    .padding(4)
                            }
                            Text(item.title)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerRow
            ForEach(entry.items.prefix(4)) { item in
                Link(destination: deepLink(for: item.slug)) {
                    HStack(spacing: 10) {
                        posterThumb(item.posterJPEG, width: 44, height: 62)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(item.subtitle)
                                .font(.system(size: 11))
                                .foregroundColor(Color(white: 0.58))
                                .lineLimit(1)
                        }
                        Spacer()
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
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.06, green: 0.06, blue: 0.07))
    }

    private var headerRow: some View {
        HStack {
            Text("ManiFlix")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(white: 0.92))
            Text("• Mới cập nhật")
                .font(.system(size: 11))
                .foregroundColor(Color(white: 0.5))
            Spacer()
        }
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

    private func deepLink(for slug: String) -> URL {
        let encoded = slug.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? slug
        return URL(string: encoded.isEmpty ? "maniflix://home" : "maniflix://movie/\(encoded)")!
    }
}

struct ManiFlixLatestWidget: Widget {
    let kind = "ManiFlixHotWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ManiFlixTimelineProvider()) { entry in
            if #available(iOS 17.0, *) {
                ManiFlixWidgetView(entry: entry)
                    .containerBackground(Color(red: 0.06, green: 0.06, blue: 0.07), for: .widget)
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
        ManiFlixLatestWidget()
    }
}
