import SwiftUI
import UIKit

enum AccentPreset: String, CaseIterable, Identifiable {
    case crimson
    case sky
    case violet
    case emerald
    case amber

    var id: String { rawValue }

    var label: String {
        switch self {
        case .crimson: return "Đỏ"
        case .sky: return "Xanh dương"
        case .violet: return "Tím"
        case .emerald: return "Xanh ngọc"
        case .amber: return "Vàng"
        }
    }

    var color: Color {
        switch self {
        case .crimson: return Color(red: 0.88, green: 0.11, blue: 0.16)
        case .sky: return Color(red: 0.22, green: 0.68, blue: 0.96)
        case .violet: return Color(red: 0.62, green: 0.36, blue: 0.95)
        case .emerald: return Color(red: 0.12, green: 0.74, blue: 0.53)
        case .amber: return Color(red: 0.94, green: 0.63, blue: 0.12)
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
        case .adaptive: return "Tự động theo hệ thống"
        case .liquid: return "Liquid Glass (iOS 26+)"
        case .legacy: return "Cổ điển (OLED tối giản)"
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
        oled ? .black : Color(red: 0.055, green: 0.058, blue: 0.068)
    }

    static func surface(oled: Bool) -> Color {
        oled ? Color(white: 0.08) : Color(red: 0.09, green: 0.095, blue: 0.11)
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
                    .glassEffect(.regular.tint(tint.opacity(0.22)).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
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
                    .fill(tint != nil ? tint!.opacity(0.18) : Color.white.opacity(0.06))
                    .background(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .fill(.ultraThinMaterial)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(tint != nil ? 0.22 : 0.09), lineWidth: 0.6)
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
                    .glassEffect(.regular.tint(tint.opacity(0.28)).interactive(interactive), in: .capsule)
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
                    .fill(tint != nil ? tint!.opacity(0.85) : Color.white.opacity(0.08))
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
