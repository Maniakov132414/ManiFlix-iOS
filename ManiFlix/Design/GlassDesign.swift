import SwiftUI
import UIKit
import ImageIO

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "#", with: "")
            .uppercased()
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        switch cleaned.count {
        case 6:
            let r = Double((value & 0xFF0000) >> 16) / 255.0
            let g = Double((value & 0x00FF00) >> 8) / 255.0
            let b = Double(value & 0x0000FF) / 255.0
            self.init(.sRGB, red: r, green: g, blue: b, opacity: 1.0)
        case 8:
            let a = Double((value & 0xFF000000) >> 24) / 255.0
            let r = Double((value & 0x00FF0000) >> 16) / 255.0
            let g = Double((value & 0x0000FF00) >> 8) / 255.0
            let b = Double(value & 0x000000FF) / 255.0
            self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
        default:
            self.init(.sRGB, red: 0.98, green: 0.176, blue: 0.282, opacity: 1.0)
        }
    }

    var luminance: Double {
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
        }
        var white: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &a) {
            return Double(white)
        }
        return 0.0
    }

    func toHexString() -> String {
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        if uiColor.getRed(&r, green: &g, blue: &b, alpha: &a) {
            return String(
                format: "#%02X%02X%02X",
                Int(round(min(max(r, 0), 1) * 255)),
                Int(round(min(max(g, 0), 1) * 255)),
                Int(round(min(max(b, 0), 1) * 255))
            )
        }
        var white: CGFloat = 0
        if uiColor.getWhite(&white, alpha: &a) {
            let v = Int(round(min(max(white, 0), 1) * 255))
            return String(format: "#%02X%02X%02X", v, v, v)
        }
        return "#121214"
    }
}

enum AccentPreset: String, CaseIterable, Identifiable {
    case crimson
    case amber
    case sky
    case violet
    case emerald

    var id: String { rawValue }

    var label: String {
        switch self {
        case .crimson: return "Đỏ"
        case .amber: return "Cam"
        case .sky: return "Xanh dương"
        case .violet: return "Tím"
        case .emerald: return "Xanh lá"
        }
    }

    var hexString: String {
        switch self {
        case .crimson: return "#FA2D48"
        case .amber: return "#FF6448"
        case .sky: return "#0A84FF"
        case .violet: return "#5E5CE6"
        case .emerald: return "#30D158"
        }
    }

    var color: Color {
        switch self {
        case .crimson: return Color(red: 0.98, green: 0.176, blue: 0.282) // Apple Music #FA2D48
        case .amber: return Color(red: 1.0, green: 0.392, blue: 0.282)
        case .sky: return Color(red: 0.039, green: 0.518, blue: 1.0)
        case .violet: return Color(red: 0.369, green: 0.361, blue: 0.902)
        case .emerald: return Color(red: 0.188, green: 0.820, blue: 0.345)
        }
    }
}

enum GlassUIStyle: String, CaseIterable, Identifiable {
    case adaptive
    case liquid
    case legacy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .adaptive: return "Tự động"
        case .liquid: return "Trong suốt"
        case .legacy: return "Đơn giản"
        }
    }

    var shouldUseLiquidGlass: Bool {
        switch self {
        case .legacy:
            return false
        case .adaptive, .liquid:
            if #available(iOS 26.0, *) {
                return true
            }
            return false
        }
    }
}

enum ManiFlixTheme {
    static var accentColor: Color {
        AppPreferences.shared.currentAccentColor
    }

    static func isLight(_ scheme: ColorScheme) -> Bool {
        switch AppPreferences.shared.themeMode {
        case .light:
            return true
        case .dark, .oled:
            return false
        case .system:
            return scheme == .light
        case .custom:
            return Color(hex: AppPreferences.shared.customBgHex).luminance > 0.55
        }
    }

    static func background(scheme: ColorScheme) -> Color {
        switch AppPreferences.shared.themeMode {
        case .oled:
            return .black
        case .dark:
            return Color(red: 0.071, green: 0.071, blue: 0.078)
        case .light:
            return Color(red: 0.957, green: 0.957, blue: 0.969)
        case .system:
            return scheme == .light
                ? Color(red: 0.957, green: 0.957, blue: 0.969)
                : Color(red: 0.071, green: 0.071, blue: 0.078)
        case .custom:
            return Color(hex: AppPreferences.shared.customBgHex)
        }
    }

    static func surface(scheme: ColorScheme) -> Color {
        switch AppPreferences.shared.themeMode {
        case .oled:
            return Color(red: 0.10, green: 0.10, blue: 0.11)
        case .dark:
            return Color(red: 0.125, green: 0.125, blue: 0.141)
        case .light:
            return .white
        case .system:
            return scheme == .light
                ? .white
                : Color(red: 0.125, green: 0.125, blue: 0.141)
        case .custom:
            return Color(hex: AppPreferences.shared.customSurfaceHex)
        }
    }

    static func primaryText(_ scheme: ColorScheme) -> Color {
        isLight(scheme) ? Color(red: 0.09, green: 0.09, blue: 0.11) : .white
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        isLight(scheme) ? Color(red: 0.36, green: 0.36, blue: 0.42) : Color(white: 0.65)
    }

    static func cardStroke(_ scheme: ColorScheme) -> Color {
        isLight(scheme) ? Color.black.opacity(0.08) : Color.white.opacity(0.10)
    }

    static func cardFill(_ scheme: ColorScheme) -> Color {
        isLight(scheme) ? Color.black.opacity(0.045) : Color.white.opacity(0.075)
    }

    static func adaptiveGridColumnCount(width: CGFloat) -> Int {
        if width >= 1100 { return 6 }
        if width >= 840 { return 5 }
        if width >= 560 { return 4 }
        return AppPreferences.shared.gridColumnsPhone
    }

    static func background(oled: Bool) -> Color {
        oled ? .black : Color(red: 0.071, green: 0.071, blue: 0.078)
    }

    static func surface(oled: Bool) -> Color {
        oled ? Color(red: 0.10, green: 0.10, blue: 0.11) : Color(red: 0.125, green: 0.125, blue: 0.141)
    }
}

struct AmbientArtworkBackground: View {
    let url: URL?
    var oled: Bool = false
    var height: CGFloat = 390
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if prefs.ambientArtworkEnabled, let artworkURL = url {
            let light = ManiFlixTheme.isLight(colorScheme)
            let bg = ManiFlixTheme.background(scheme: colorScheme)
            ZStack(alignment: .top) {
                CachedPosterImage(url: artworkURL, maxPixelSize: 64)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .blur(radius: 22)
                    .saturation(light ? 1.12 : 1.28)
                    .opacity(light ? 0.24 : (prefs.themeMode == .oled || oled ? 0.34 : 0.44))
                    .overlay(
                        LinearGradient(
                            stops: [
                                .init(color: bg.opacity(light ? 0.28 : 0.0), location: 0.0),
                                .init(color: bg.opacity(light ? 0.65 : 0.40), location: 0.58),
                                .init(color: bg, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .drawingGroup(opaque: false)
                    .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
        }
    }
}

@available(iOS 16.0, *)
struct WrappingFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 8
    var verticalSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 360
        var curX: CGFloat = 0
        var curY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            if curX > 0 && curX + size.width > maxWidth {
                curX = 0
                curY += rowHeight + verticalSpacing
                rowHeight = 0
            }
            curX += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: curY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var curX = bounds.minX
        var curY = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if curX > bounds.minX && curX + size.width > bounds.maxX + 0.5 {
                curX = bounds.minX
                curY += rowHeight + verticalSpacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: curX, y: curY),
                proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
            )
            curX += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct AdaptiveGlassCardModifier: ViewModifier {
    let cornerRadius: CGFloat
    let interactive: Bool
    let tint: Color?
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), prefs.glassStyle.shouldUseLiquidGlass {
            if let tint = tint {
                content
                    .glassEffect(.regular.tint(tint.opacity(0.28)).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
            } else {
                content
                    .glassEffect(.regular.interactive(interactive), in: .rect(cornerRadius: cornerRadius))
            }
        } else {
            fallbackCard(content)
        }
        #else
        fallbackCard(content)
        #endif
    }

    @ViewBuilder
    private func fallbackCard(_ content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(tint != nil ? tint!.opacity(0.20) : ManiFlixTheme.cardFill(colorScheme))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(tint != nil ? tint!.opacity(0.32) : ManiFlixTheme.cardStroke(colorScheme), lineWidth: 0.6)
            )
    }
}

struct AdaptiveGlassCapsuleModifier: ViewModifier {
    let interactive: Bool
    let tint: Color?
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), prefs.glassStyle.shouldUseLiquidGlass {
            if let tint = tint {
                content
                    .glassEffect(.regular.tint(tint.opacity(0.78)).interactive(interactive), in: .capsule)
            } else {
                content
                    .glassEffect(.regular.interactive(interactive), in: .capsule)
            }
        } else {
            fallbackCapsule(content)
        }
        #else
        fallbackCapsule(content)
        #endif
    }

    @ViewBuilder
    private func fallbackCapsule(_ content: Content) -> some View {
        content
            .background(
                Capsule()
                    .fill(tint != nil ? tint!.opacity(0.88) : ManiFlixTheme.cardFill(colorScheme))
                    .background(
                        Capsule().fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(tint != nil ? tint!.opacity(0.30) : ManiFlixTheme.cardStroke(colorScheme), lineWidth: 0.6)
            )
    }
}

extension View {
    func adaptiveGlassCard(cornerRadius: CGFloat = 14, interactive: Bool = false, tint: Color? = nil) -> some View {
        modifier(AdaptiveGlassCardModifier(cornerRadius: cornerRadius, interactive: interactive, tint: tint))
    }

    func adaptiveGlassCapsule(interactive: Bool = true, tint: Color? = nil) -> some View {
        modifier(AdaptiveGlassCapsuleModifier(interactive: interactive, tint: tint))
    }

    @ViewBuilder
    func adaptiveHiddenScrollBackground() -> some View {
        if #available(iOS 16.0, *) {
            self.scrollContentBackground(.hidden)
        } else {
            self
        }
    }

    @ViewBuilder
    func adaptiveSoftScrollEdge() -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .all)
        } else {
            self
        }
        #else
        self
        #endif
    }

    func readContainerWidth(_ width: Binding<CGFloat>) -> some View {
        background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: ContainerWidthPreferenceKey.self, value: geo.size.width)
            }
        )
        .onPreferenceChange(ContainerWidthPreferenceKey.self) { newWidth in
            if newWidth > 0 && abs(width.wrappedValue - newWidth) > 1 {
                width.wrappedValue = newWidth
            }
        }
    }
}

private struct ContainerWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = UIScreen.main.bounds.width
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

actor ImageFetchCoalescer {
    private var inflight: [String: Task<UIImage?, Never>] = [:]

    func load(
        key: String,
        url: URL,
        maxPixelSize: CGFloat,
        session: URLSession,
        downsample: @escaping @Sendable (Data, CGFloat) -> UIImage?
    ) async -> UIImage? {
        if let existing = inflight[key] {
            return await existing.value
        }
        let task = Task<UIImage?, Never> {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            request.cachePolicy = .returnCacheDataElseLoad
            guard let (data, response) = try? await session.data(for: request) else { return nil }
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            return await Task.detached(priority: .userInitiated) {
                downsample(data, maxPixelSize)
            }.value
        }
        inflight[key] = task
        let img = await task.value
        inflight.removeValue(forKey: key)
        return img
    }
}

final class ImageCacheStore {
    static let shared = ImageCacheStore()
    private let cache = NSCache<NSString, UIImage>()
    private let coalescer = ImageFetchCoalescer()
    let urlSession: URLSession

    private init() {
        cache.countLimit = 150
        cache.totalCostLimit = 64 * 1024 * 1024

        let urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 128 * 1024 * 1024,
            diskPath: "ManiFlixImageCache"
        )
        let config = URLSessionConfiguration.default
        config.urlCache = urlCache
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 12
        self.urlSession = URLSession(configuration: config)
    }

    func cacheKey(for url: URL, maxPixelSize: CGFloat) -> NSString {
        "\(url.absoluteString)#\(Int(maxPixelSize))" as NSString
    }

    func image(for url: URL, maxPixelSize: CGFloat = 360) -> UIImage? {
        cache.object(forKey: cacheKey(for: url, maxPixelSize: maxPixelSize))
    }

    func store(_ image: UIImage, for url: URL, maxPixelSize: CGFloat = 360) {
        let pixelW = Int(image.size.width * image.scale)
        let pixelH = Int(image.size.height * image.scale)
        let cost = max(1, pixelW * pixelH * 4)
        cache.setObject(image, forKey: cacheKey(for: url, maxPixelSize: maxPixelSize), cost: cost)
    }

    func loadOrFetch(
        url: URL,
        maxPixelSize: CGFloat,
        downsample: @escaping @Sendable (Data, CGFloat) -> UIImage?
    ) async -> UIImage? {
        if let hit = image(for: url, maxPixelSize: maxPixelSize) {
            return hit
        }
        let key = cacheKey(for: url, maxPixelSize: maxPixelSize) as String
        if let decoded = await coalescer.load(
            key: key,
            url: url,
            maxPixelSize: maxPixelSize,
            session: urlSession,
            downsample: downsample
        ) {
            store(decoded, for: url, maxPixelSize: maxPixelSize)
            return decoded
        }
        return nil
    }
}

typealias CachedAsyncImage = CachedPosterImage

struct CachedPosterImage: View {
    let url: URL?
    var fallbackURL: URL? = nil
    var contentMode: ContentMode = .fill
    var maxPixelSize: CGFloat = 360

    @Environment(\.colorScheme) private var colorScheme
    @State private var loadedImage: UIImage?
    @State private var failed = false

    private var syncCachedImage: UIImage? {
        if let primary = url, let hit = ImageCacheStore.shared.image(for: primary, maxPixelSize: maxPixelSize) {
            return hit
        }
        if let fb = fallbackURL, let hit = ImageCacheStore.shared.image(for: fb, maxPixelSize: maxPixelSize) {
            return hit
        }
        return nil
    }

    var body: some View {
        let placeholderColor = ManiFlixTheme.isLight(colorScheme) ? Color.black.opacity(0.06) : Color(white: 0.09)
        let displayImage = loadedImage ?? syncCachedImage
        Group {
            if let uiImage = displayImage {
                if contentMode == .fill {
                    Color.clear
                        .overlay(
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                        )
                        .clipped()
                } else {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                }
            } else if failed {
                ZStack {
                    placeholderColor
                    Image(systemName: "film")
                        .font(.callout)
                        .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                }
            } else {
                placeholderColor
            }
        }
        .task(id: "\(url?.absoluteString ?? "")|\(fallbackURL?.absoluteString ?? "")#\(Int(maxPixelSize))") {
            await load()
        }
    }

    private static func downsample(data: Data, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            return UIImage(data: data)
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(16, Int(maxPixelSize))
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return UIImage(data: data)
        }
        return UIImage(cgImage: cgImage)
    }

    private func load() async {
        failed = false
        let targetSize = maxPixelSize
        if let syncHit = syncCachedImage {
            loadedImage = syncHit
            return
        }
        loadedImage = nil

        let candidates = [url, fallbackURL].compactMap { $0 }
        guard !candidates.isEmpty else {
            failed = true
            return
        }

        for candidate in candidates {
            if Task.isCancelled { return }
            if let img = await ImageCacheStore.shared.loadOrFetch(
                url: candidate,
                maxPixelSize: targetSize,
                downsample: Self.downsample
            ) {
                if Task.isCancelled { return }
                loadedImage = img
                return
            }
        }

        if !Task.isCancelled {
            failed = true
        }
    }
}

enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard AppPreferences.shared.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard AppPreferences.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(type)
    }
}
