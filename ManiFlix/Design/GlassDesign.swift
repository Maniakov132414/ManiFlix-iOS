import SwiftUI
import UIKit

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
    static func background(oled: Bool) -> Color {
        oled ? .black : Color(red: 0.071, green: 0.071, blue: 0.078)
    }

    static func surface(oled: Bool) -> Color {
        oled ? Color(red: 0.10, green: 0.10, blue: 0.11) : Color(red: 0.125, green: 0.125, blue: 0.141)
    }
}

struct AmbientArtworkBackground: View {
    let url: URL?
    let oled: Bool
    var height: CGFloat = 390
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        if prefs.ambientArtworkEnabled, let artworkURL = url {
            ZStack(alignment: .top) {
                CachedAsyncImage(url: artworkURL)
                    .frame(maxWidth: .infinity)
                    .frame(height: height)
                    .blur(radius: 62)
                    .saturation(1.28)
                    .opacity(oled ? 0.34 : 0.44)
                    .mask(
                        LinearGradient(
                            stops: [
                                .init(color: .white, location: 0.0),
                                .init(color: .white.opacity(0.65), location: 0.52),
                                .init(color: .clear, location: 1.0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
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
                    .fill(tint != nil ? tint!.opacity(0.20) : Color.white.opacity(0.07))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(tint != nil ? 0.25 : 0.08), lineWidth: 0.6)
            )
    }
}

struct AdaptiveGlassCapsuleModifier: ViewModifier {
    let interactive: Bool
    let tint: Color?
    @ObservedObject private var prefs = AppPreferences.shared

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *), prefs.glassStyle.shouldUseLiquidGlass {
            if let tint = tint {
                content
                    .glassEffect(.regular.tint(tint.opacity(0.32)).interactive(interactive), in: .capsule)
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
                    .fill(tint != nil ? tint!.opacity(0.88) : Color.white.opacity(0.09))
                    .background(
                        Capsule().fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(tint != nil ? 0.24 : 0.11), lineWidth: 0.6)
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
}

final class ImageCacheStore {
    static let shared = ImageCacheStore()
    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 240
        cache.totalCostLimit = 96 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url.absoluteString as NSString)
    }

    func store(_ image: UIImage, for url: URL) {
        cache.setObject(image, forKey: url.absoluteString as NSString)
    }
}

struct CachedAsyncImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill

    @State private var loadedImage: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let uiImage = loadedImage {
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
                    Color(white: 0.1)
                    Image(systemName: "film")
                        .font(.callout)
                        .foregroundColor(Color(white: 0.35))
                }
            } else {
                Color(white: 0.09)
            }
        }
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        failed = false
        guard let url = url else {
            failed = true
            return
        }
        if let cached = ImageCacheStore.shared.image(for: url) {
            loadedImage = cached
            return
        }
        do {
            var request = URLRequest(url: url)
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                failed = true
                return
            }
            if let img = UIImage(data: data) {
                ImageCacheStore.shared.store(img, for: url)
                await MainActor.run { loadedImage = img }
            } else {
                failed = true
            }
        } catch {
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
