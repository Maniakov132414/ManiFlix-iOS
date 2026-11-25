import Foundation
import AVFoundation
import CoreMotion
import Combine

final class AudioSpatialEngine: ObservableObject {
    static let shared = AudioSpatialEngine()

    @Published private(set) var outputRouteName: String = "Loa thiết bị"
    @Published private(set) var outputPortType: String = "BuiltInSpeaker"
    @Published private(set) var isHeadphoneOutput: Bool = false
    @Published private(set) var isAirPlayOutput: Bool = false
    @Published private(set) var isSpatialEligibleRoute: Bool = false
    @Published private(set) var isHeadTrackingHardwareReady: Bool = false
    @Published private(set) var lastStatusMessage: String = "Sẵn sàng"

    private let motionManager = CMHeadphoneMotionManager()
    private var cancellables = Set<AnyCancellable>()

    private init() {
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshRouteDiagnostics()
            }
            .store(in: &cancellables)

        refreshRouteDiagnostics()
    }

    func configureAudioSession(for prefs: AppPreferences = .shared) {
        let session = AVAudioSession.sharedInstance()
        let mode: AVAudioSession.Mode
        switch prefs.soundProfile {
        case .cinema:
            mode = .moviePlayback
        case .dialogue:
            mode = .spokenAudio
        case .standard:
            mode = .default
        }

        do {
            try session.setCategory(.playback, mode: mode, policy: .longFormVideo, options: [])
            try session.setActive(true)
            lastStatusMessage = "AVAudioSession active (\(mode.rawValue))"
        } catch {
            do {
                try session.setCategory(.playback, mode: mode, options: [])
                try session.setActive(true)
                lastStatusMessage = "AVAudioSession fallback (\(mode.rawValue))"
            } catch {
                lastStatusMessage = "AudioSession error: \(error.localizedDescription)"
            }
        }

        refreshRouteDiagnostics()
    }

    func applySettings(to item: AVPlayerItem, player: AVPlayer, prefs: AppPreferences = .shared) {
        // Spatialization formats
        switch prefs.spatialAudioMode {
        case .off:
            item.allowedAudioSpatializationFormats = []
        case .fixed, .headTracked:
            item.allowedAudioSpatializationFormats = [.multichannel]
        case .automatic:
            item.allowedAudioSpatializationFormats = [.monoAndStereo, .multichannel]
        }

        // Pitch algorithm for fast playback & dialogue clarity
        switch prefs.pitchAlgorithm {
        case .spectral:
            item.audioTimePitchAlgorithm = .spectral
        case .timeDomain:
            item.audioTimePitchAlgorithm = .timeDomain
        }

        item.preferredForwardBufferDuration = prefs.forwardBufferSeconds
        player.volume = Float(min(max(prefs.comfortGain, 0.25), 1.0))

        // AirPlay external playback stays seamless when enabled
        player.allowsExternalPlayback = true
        player.usesExternalPlaybackWhileExternalScreenIsActive = true
    }

    func refreshRouteDiagnostics() {
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs
        if let first = outputs.first {
            outputRouteName = first.portName
            outputPortType = first.portType.rawValue

            let headphonePorts: [AVAudioSession.Port] = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE, .headphones, .usbAudio]
            isHeadphoneOutput = headphonePorts.contains(first.portType)
            isAirPlayOutput = (first.portType == .airPlay)
            isSpatialEligibleRoute = (first.portType == .bluetoothA2DP || first.portType == .headphones || first.portType == .builtInSpeaker)
        } else {
            outputRouteName = "Không rõ đầu ra"
            outputPortType = "Unknown"
            isHeadphoneOutput = false
            isAirPlayOutput = false
            isSpatialEligibleRoute = false
        }

        isHeadTrackingHardwareReady = motionManager.isDeviceMotionAvailable
    }

    var activeSpatialSummary: String {
        let mode = AppPreferences.shared.spatialAudioMode
        if mode == .off {
            return "Stereo Gốc"
        }
        if isHeadTrackingHardwareReady && mode == .headTracked {
            return "Spatial • Head Tracked"
        }
        if isHeadphoneOutput {
            return "Apple Spatial (\(outputRouteName))"
        }
        if isAirPlayOutput {
            return "AirPlay Audio (\(outputRouteName))"
        }
        return mode.badge
    }
}
