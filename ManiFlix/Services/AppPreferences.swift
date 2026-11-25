import Foundation
import SwiftUI
import Combine

enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case oled
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "Tự động"
        case .light: return "Sáng"
        case .dark: return "Tối"
        case .oled: return "Đen OLED"
        case .custom: return "Tuỳ chỉnh"
        }
    }

    var colorSchemeOverride: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark, .oled, .custom: return .dark
        }
    }
}

struct ThemePreset: Identifiable, Hashable {
    let id: String
    let name: String
    let mode: ThemeMode
    let accentHex: String
    let bgHex: String
    let surfaceHex: String

    static let presets: [ThemePreset] = [
        ThemePreset(id: "apple-dark", name: "Apple Music Tối", mode: .dark, accentHex: "#FA2D48", bgHex: "#121214", surfaceHex: "#1C1C1E"),
        ThemePreset(id: "pure-light", name: "Trắng Tinh Khôi", mode: .light, accentHex: "#FA2D48", bgHex: "#F4F4F7", surfaceHex: "#FFFFFF"),
        ThemePreset(id: "midnight-indigo", name: "Midnight Indigo", mode: .custom, accentHex: "#5E5CE6", bgHex: "#0B1020", surfaceHex: "#151C32"),
        ThemePreset(id: "forest-emerald", name: "Forest Emerald", mode: .custom, accentHex: "#30D158", bgHex: "#0B1612", surfaceHex: "#14241D"),
        ThemePreset(id: "cyberpunk-rose", name: "Cyberpunk Rose", mode: .custom, accentHex: "#FF2D55", bgHex: "#16091A", surfaceHex: "#26112E")
    ]
}

enum SpatialAudioMode: String, CaseIterable, Identifiable {
    case automatic
    case fixed
    case headTracked
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Tự động"
        case .fixed: return "Không gian cố định"
        case .headTracked: return "Theo chuyển động đầu"
        case .off: return "Tắt (Stereo)"
        }
    }

    var badge: String {
        switch self {
        case .automatic: return "Spatial"
        case .fixed: return "Fixed"
        case .headTracked: return "Head Tracked"
        case .off: return "Stereo"
        }
    }
}

enum SoundProfileMode: String, CaseIterable, Identifiable {
    case cinema
    case dialogue
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cinema: return "Điện ảnh"
        case .dialogue: return "Rõ lời thoại"
        case .standard: return "Mặc định"
        }
    }
}

enum AudioPitchAlgorithmMode: String, CaseIterable, Identifiable {
    case spectral
    case timeDomain

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spectral: return "Giữ chi tiết âm (Spectral)"
        case .timeDomain: return "Nhẹ CPU (Time Domain)"
        }
    }
}

enum IntroSkipBehavior: String, CaseIterable, Identifiable {
    case button
    case auto
    case off

    var id: String { rawValue }

    var title: String {
        switch self {
        case .button: return "Hiện nút bỏ qua"
        case .auto: return "Tự động bỏ qua"
        case .off: return "Tắt"
        }
    }
}

enum ExternalPlayerOption: String, CaseIterable, Identifiable {
    case internalPlayer = "internal"
    case vlc = "vlc"
    case outplayer = "outplayer"
    case infuse = "infuse"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalPlayer: return "Trình phát tích hợp"
        case .vlc: return "VLC"
        case .outplayer: return "Outplayer"
        case .infuse: return "Infuse"
        }
    }
}

enum WidgetFeedMode: String, CaseIterable, Identifiable {
    case smart
    case continueWatching
    case forYou
    case latest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: return "Thông minh (Xem tiếp + Đề xuất)"
        case .continueWatching: return "Đang xem gần đây"
        case .forYou: return "Đề xuất cho bạn"
        case .latest: return "Phim mới cập nhật"
        }
    }
}

final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    private let defaults = UserDefaults.standard
    private var isSyncingTheme = false
    let baseURL = "https://phim.maniakov.bond"

    @Published var glassStyle: GlassUIStyle {
        didSet { defaults.set(glassStyle.rawValue, forKey: "pref.glassStyle") }
    }
    @Published var themeMode: ThemeMode {
        didSet {
            defaults.set(themeMode.rawValue, forKey: "pref.themeMode")
            guard !isSyncingTheme else { return }
            isSyncingTheme = true
            oledBlackEnabled = (themeMode == .oled)
            switch themeMode {
            case .system: activeThemePresetId = "system"
            case .light: activeThemePresetId = "pure-light"
            case .dark: activeThemePresetId = "apple-dark"
            case .oled: activeThemePresetId = "oled"
            case .custom:
                if ["system", "pure-light", "apple-dark", "oled"].contains(activeThemePresetId) {
                    activeThemePresetId = "custom"
                }
            }
            isSyncingTheme = false
        }
    }
    @Published var oledBlackEnabled: Bool {
        didSet {
            defaults.set(oledBlackEnabled, forKey: "pref.oledBlack")
            guard !isSyncingTheme else { return }
            isSyncingTheme = true
            if oledBlackEnabled {
                themeMode = .oled
                activeThemePresetId = "oled"
            } else if themeMode == .oled {
                themeMode = .dark
                activeThemePresetId = "apple-dark"
            }
            isSyncingTheme = false
        }
    }
    @Published var customAccentHex: String {
        didSet {
            defaults.set(customAccentHex, forKey: "pref.customAccentHex")
            guard !isSyncingTheme else { return }
            if let matched = AccentPreset.allCases.first(where: { $0.hexString.caseInsensitiveCompare(customAccentHex) == .orderedSame }) {
                isSyncingTheme = true
                accentPreset = matched
                isSyncingTheme = false
            }
        }
    }
    @Published var customBgHex: String {
        didSet { defaults.set(customBgHex, forKey: "pref.customBgHex") }
    }
    @Published var customSurfaceHex: String {
        didSet { defaults.set(customSurfaceHex, forKey: "pref.customSurfaceHex") }
    }
    @Published var activeThemePresetId: String {
        didSet { defaults.set(activeThemePresetId, forKey: "pref.activeThemePresetId") }
    }
    @Published var ambientArtworkEnabled: Bool {
        didSet { defaults.set(ambientArtworkEnabled, forKey: "pref.ambientArtwork") }
    }
    @Published var accentPreset: AccentPreset {
        didSet {
            defaults.set(accentPreset.rawValue, forKey: "pref.accentPreset")
            guard !isSyncingTheme else { return }
            isSyncingTheme = true
            customAccentHex = accentPreset.hexString
            isSyncingTheme = false
        }
    }
    @Published var gridColumnsPhone: Int {
        didSet { defaults.set(gridColumnsPhone, forKey: "pref.gridColumnsPhone") }
    }
    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "pref.hapticsEnabled") }
    }

    @Published var spatialAudioMode: SpatialAudioMode {
        didSet { defaults.set(spatialAudioMode.rawValue, forKey: "pref.spatialAudioMode") }
    }
    @Published var soundProfile: SoundProfileMode {
        didSet { defaults.set(soundProfile.rawValue, forKey: "pref.soundProfile") }
    }
    @Published var pitchAlgorithm: AudioPitchAlgorithmMode {
        didSet { defaults.set(pitchAlgorithm.rawValue, forKey: "pref.pitchAlgorithm") }
    }
    @Published var comfortGain: Double {
        didSet { defaults.set(comfortGain, forKey: "pref.comfortGain") }
    }

    @Published var autoRotateLandscape: Bool {
        didSet { defaults.set(autoRotateLandscape, forKey: "pref.autoRotateLandscape") }
    }
    @Published var autoPiP: Bool {
        didSet { defaults.set(autoPiP, forKey: "pref.autoPiP") }
    }
    @Published var doubleTapSeekSeconds: Int {
        didSet { defaults.set(doubleTapSeekSeconds, forKey: "pref.doubleTapSeekSeconds") }
    }
    @Published var longPressSpeed: Double {
        didSet { defaults.set(longPressSpeed, forKey: "pref.longPressSpeed") }
    }
    @Published var forwardBufferSeconds: Double {
        didSet { defaults.set(forwardBufferSeconds, forKey: "pref.forwardBufferSeconds") }
    }
    @Published var autoCutAds: Bool {
        didSet { defaults.set(autoCutAds, forKey: "pref.autoCutAds") }
    }
    @Published var introSkipBehavior: IntroSkipBehavior {
        didSet { defaults.set(introSkipBehavior.rawValue, forKey: "pref.introSkipBehavior") }
    }
    @Published var autoNextEpisode: Bool {
        didSet { defaults.set(autoNextEpisode, forKey: "pref.autoNextEpisode") }
    }
    @Published var externalPlayer: ExternalPlayerOption {
        didSet { defaults.set(externalPlayer.rawValue, forKey: "pref.externalPlayer") }
    }
    @Published var widgetFeedMode: WidgetFeedMode {
        didSet {
            defaults.set(widgetFeedMode.rawValue, forKey: "pref.widgetFeedMode")
            Task { @MainActor in
                WidgetSyncBridge.shared.syncFromCurrentState(force: true)
            }
        }
    }

    private init() {
        let ud = UserDefaults.standard
        #if LEGACY_UI_DEFAULT
        let defaultGlass: GlassUIStyle = .legacy
        let defaultThemeMode: ThemeMode = .oled
        #else
        let defaultGlass: GlassUIStyle = .adaptive
        let defaultThemeMode: ThemeMode = .system
        #endif

        let resolvedMode: ThemeMode
        if let savedMode = ud.string(forKey: "pref.themeMode"),
           let parsed = ThemeMode(rawValue: savedMode) {
            resolvedMode = parsed
        } else if ud.object(forKey: "pref.oledBlack") != nil {
            resolvedMode = ud.bool(forKey: "pref.oledBlack") ? .oled : .dark
        } else {
            resolvedMode = defaultThemeMode
        }

        let savedAccentPreset = AccentPreset(rawValue: ud.string(forKey: "pref.accentPreset") ?? "") ?? .crimson
        let savedAccentHex = ud.string(forKey: "pref.customAccentHex") ?? savedAccentPreset.hexString
        let savedBgHex = ud.string(forKey: "pref.customBgHex") ?? "#121214"
        let savedSurfaceHex = ud.string(forKey: "pref.customSurfaceHex") ?? "#1C1C1E"
        let savedPresetId = ud.string(forKey: "pref.activeThemePresetId") ?? (resolvedMode == .oled ? "oled" : (resolvedMode == .system ? "system" : "apple-dark"))

        self.glassStyle = GlassUIStyle(rawValue: ud.string(forKey: "pref.glassStyle") ?? "") ?? defaultGlass
        self.themeMode = resolvedMode
        self.oledBlackEnabled = (resolvedMode == .oled)
        self.customAccentHex = savedAccentHex
        self.customBgHex = savedBgHex
        self.customSurfaceHex = savedSurfaceHex
        self.activeThemePresetId = savedPresetId
        self.ambientArtworkEnabled = ud.object(forKey: "pref.ambientArtwork") as? Bool ?? true
        self.accentPreset = AccentPreset.allCases.first(where: { $0.hexString.caseInsensitiveCompare(savedAccentHex) == .orderedSame }) ?? savedAccentPreset
        let cols = ud.integer(forKey: "pref.gridColumnsPhone")
        self.gridColumnsPhone = (cols == 2 || cols == 3) ? cols : 3
        self.hapticsEnabled = ud.object(forKey: "pref.hapticsEnabled") as? Bool ?? true

        self.spatialAudioMode = SpatialAudioMode(rawValue: ud.string(forKey: "pref.spatialAudioMode") ?? "") ?? .automatic
        self.soundProfile = SoundProfileMode(rawValue: ud.string(forKey: "pref.soundProfile") ?? "") ?? .cinema
        self.pitchAlgorithm = AudioPitchAlgorithmMode(rawValue: ud.string(forKey: "pref.pitchAlgorithm") ?? "") ?? .spectral
        let gain = ud.double(forKey: "pref.comfortGain")
        self.comfortGain = gain > 0.1 ? gain : 1.0

        self.autoRotateLandscape = ud.object(forKey: "pref.autoRotateLandscape") as? Bool ?? false
        self.autoPiP = ud.object(forKey: "pref.autoPiP") as? Bool ?? true
        let seek = ud.integer(forKey: "pref.doubleTapSeekSeconds")
        self.doubleTapSeekSeconds = [5, 10, 15, 30].contains(seek) ? seek : 10
        let speed = ud.double(forKey: "pref.longPressSpeed")
        self.longPressSpeed = speed >= 1.25 ? speed : 2.0
        let buf = ud.double(forKey: "pref.forwardBufferSeconds")
        self.forwardBufferSeconds = buf >= 5 ? buf : 45
        self.autoCutAds = ud.object(forKey: "pref.autoCutAds") as? Bool ?? true
        self.introSkipBehavior = IntroSkipBehavior(rawValue: ud.string(forKey: "pref.introSkipBehavior") ?? "") ?? .button
        self.autoNextEpisode = ud.object(forKey: "pref.autoNextEpisode") as? Bool ?? true
        self.externalPlayer = ExternalPlayerOption(rawValue: ud.string(forKey: "pref.externalPlayer") ?? "") ?? .internalPlayer
        self.widgetFeedMode = WidgetFeedMode(rawValue: ud.string(forKey: "pref.widgetFeedMode") ?? "") ?? .smart
    }

    var normalizedBaseURL: String {
        baseURL
    }

    var currentAccentColor: Color {
        Color(hex: customAccentHex)
    }

    var resolvedColorScheme: ColorScheme? {
        switch themeMode {
        case .system: return nil
        case .light: return .light
        case .dark, .oled: return .dark
        case .custom:
            return Color(hex: customBgHex).luminance > 0.55 ? .light : .dark
        }
    }

    var effectiveBgHexForSync: String {
        switch themeMode {
        case .light: return "#F4F4F7"
        case .oled: return "#000000"
        case .dark, .system: return "#121214"
        case .custom: return customBgHex
        }
    }

    var effectiveSurfaceHexForSync: String {
        switch themeMode {
        case .light: return "#FFFFFF"
        case .oled: return "#19191C"
        case .dark, .system: return "#1C1C1E"
        case .custom: return customSurfaceHex
        }
    }

    func applyPreset(_ preset: ThemePreset) {
        isSyncingTheme = true
        themeMode = preset.mode
        oledBlackEnabled = (preset.mode == .oled)
        customAccentHex = preset.accentHex
        customBgHex = preset.bgHex
        customSurfaceHex = preset.surfaceHex
        activeThemePresetId = preset.id
        if let matched = AccentPreset.allCases.first(where: { $0.hexString.caseInsensitiveCompare(preset.accentHex) == .orderedSame }) {
            accentPreset = matched
        }
        isSyncingTheme = false
    }

    func applyServerTheme(_ config: UserThemeConfig) {
        isSyncingTheme = true
        defer { isSyncingTheme = false }

        if let accent = config.accent, !accent.isEmpty {
            customAccentHex = accent
            if let matched = AccentPreset.allCases.first(where: { $0.hexString.caseInsensitiveCompare(accent) == .orderedSame }) {
                accentPreset = matched
            }
        }
        if let bg = config.bg, !bg.isEmpty {
            customBgHex = bg
        }
        if let surface = config.surface, !surface.isEmpty {
            customSurfaceHex = surface
        }
        if let pid = config.presetId, !pid.isEmpty {
            activeThemePresetId = pid
            if let preset = ThemePreset.presets.first(where: { $0.id == pid }) {
                themeMode = preset.mode
                oledBlackEnabled = (preset.mode == .oled)
            } else if pid == "system" {
                themeMode = .system
                oledBlackEnabled = false
            } else if pid == "oled" || config.bg == "#000000" {
                themeMode = .oled
                oledBlackEnabled = true
            } else if pid == "pure-light" {
                themeMode = .light
                oledBlackEnabled = false
            } else if pid == "apple-dark" {
                themeMode = .dark
                oledBlackEnabled = false
            } else {
                themeMode = .custom
                oledBlackEnabled = false
            }
        }
    }

    func resetToDefaults() {
        isSyncingTheme = true
        #if LEGACY_UI_DEFAULT
        glassStyle = .legacy
        themeMode = .oled
        oledBlackEnabled = true
        activeThemePresetId = "oled"
        #else
        glassStyle = .adaptive
        themeMode = .system
        oledBlackEnabled = false
        activeThemePresetId = "system"
        #endif
        customAccentHex = "#FA2D48"
        customBgHex = "#121214"
        customSurfaceHex = "#1C1C1E"
        ambientArtworkEnabled = true
        accentPreset = .crimson
        isSyncingTheme = false

        gridColumnsPhone = 3
        hapticsEnabled = true
        spatialAudioMode = .automatic
        soundProfile = .cinema
        pitchAlgorithm = .spectral
        comfortGain = 1.0
        autoRotateLandscape = false
        autoPiP = true
        doubleTapSeekSeconds = 10
        longPressSpeed = 2.0
        forwardBufferSeconds = 45
        autoCutAds = true
        introSkipBehavior = .button
        autoNextEpisode = true
        externalPlayer = .internalPlayer
        widgetFeedMode = .smart
    }
}
