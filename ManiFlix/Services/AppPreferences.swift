import Foundation
import Combine

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

final class AppPreferences: ObservableObject {
    static let shared = AppPreferences()
    private let defaults = UserDefaults.standard
    let baseURL = "https://phim.maniakov.bond"

    @Published var glassStyle: GlassUIStyle {
        didSet { defaults.set(glassStyle.rawValue, forKey: "pref.glassStyle") }
    }
    @Published var oledBlackEnabled: Bool {
        didSet { defaults.set(oledBlackEnabled, forKey: "pref.oledBlack") }
    }
    @Published var ambientArtworkEnabled: Bool {
        didSet { defaults.set(ambientArtworkEnabled, forKey: "pref.ambientArtwork") }
    }
    @Published var accentPreset: AccentPreset {
        didSet { defaults.set(accentPreset.rawValue, forKey: "pref.accentPreset") }
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

    private init() {
        #if LEGACY_UI_DEFAULT
        let defaultGlass: GlassUIStyle = .legacy
        let defaultOled = true
        #else
        let defaultGlass: GlassUIStyle = .adaptive
        let defaultOled = false
        #endif
        self.glassStyle = GlassUIStyle(rawValue: defaults.string(forKey: "pref.glassStyle") ?? "") ?? defaultGlass
        self.oledBlackEnabled = defaults.object(forKey: "pref.oledBlack") as? Bool ?? defaultOled
        self.ambientArtworkEnabled = defaults.object(forKey: "pref.ambientArtwork") as? Bool ?? true
        self.accentPreset = AccentPreset(rawValue: defaults.string(forKey: "pref.accentPreset") ?? "") ?? .crimson
        let cols = defaults.integer(forKey: "pref.gridColumnsPhone")
        self.gridColumnsPhone = (cols == 2 || cols == 3) ? cols : 3
        self.hapticsEnabled = defaults.object(forKey: "pref.hapticsEnabled") as? Bool ?? true

        self.spatialAudioMode = SpatialAudioMode(rawValue: defaults.string(forKey: "pref.spatialAudioMode") ?? "") ?? .automatic
        self.soundProfile = SoundProfileMode(rawValue: defaults.string(forKey: "pref.soundProfile") ?? "") ?? .cinema
        self.pitchAlgorithm = AudioPitchAlgorithmMode(rawValue: defaults.string(forKey: "pref.pitchAlgorithm") ?? "") ?? .spectral
        let gain = defaults.double(forKey: "pref.comfortGain")
        self.comfortGain = gain > 0.1 ? gain : 1.0

        self.autoRotateLandscape = defaults.object(forKey: "pref.autoRotateLandscape") as? Bool ?? false
        self.autoPiP = defaults.object(forKey: "pref.autoPiP") as? Bool ?? true
        let seek = defaults.integer(forKey: "pref.doubleTapSeekSeconds")
        self.doubleTapSeekSeconds = [5, 10, 15, 30].contains(seek) ? seek : 10
        let speed = defaults.double(forKey: "pref.longPressSpeed")
        self.longPressSpeed = speed >= 1.25 ? speed : 2.0
        let buf = defaults.double(forKey: "pref.forwardBufferSeconds")
        self.forwardBufferSeconds = buf >= 5 ? buf : 45
        self.autoCutAds = defaults.object(forKey: "pref.autoCutAds") as? Bool ?? true
        self.introSkipBehavior = IntroSkipBehavior(rawValue: defaults.string(forKey: "pref.introSkipBehavior") ?? "") ?? .button
        self.autoNextEpisode = defaults.object(forKey: "pref.autoNextEpisode") as? Bool ?? true
        self.externalPlayer = ExternalPlayerOption(rawValue: defaults.string(forKey: "pref.externalPlayer") ?? "") ?? .internalPlayer
    }

    var normalizedBaseURL: String {
        baseURL
    }

    func resetToDefaults() {
        #if LEGACY_UI_DEFAULT
        glassStyle = .legacy
        oledBlackEnabled = true
        #else
        glassStyle = .adaptive
        oledBlackEnabled = false
        #endif
        ambientArtworkEnabled = true
        accentPreset = .crimson
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
    }
}
