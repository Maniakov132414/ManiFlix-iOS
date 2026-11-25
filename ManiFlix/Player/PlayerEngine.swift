import Foundation
import AVFoundation
import AVKit
import MediaPlayer
import Combine
import UIKit

enum PlayerAspectMode: String, CaseIterable {
    case fitSafe
    case ratio16x9
    case ratio4x3
    case ratio21x9
    case edgeFill

    var title: String {
        switch self {
        case .fitSafe: return "Gốc"
        case .ratio16x9: return "16:9"
        case .ratio4x3: return "4:3"
        case .ratio21x9: return "21:9"
        case .edgeFill: return "Tràn viền"
        }
    }

    var explicitRatio: CGFloat? {
        switch self {
        case .ratio16x9: return 16.0 / 9.0
        case .ratio4x3: return 4.0 / 3.0
        case .ratio21x9: return 21.0 / 9.0
        case .fitSafe, .edgeFill: return nil
        }
    }

    var layerGravity: AVLayerVideoGravity {
        switch self {
        case .fitSafe: return .resizeAspect
        case .ratio16x9, .ratio4x3, .ratio21x9: return .resize
        case .edgeFill: return .resizeAspectFill
        }
    }
}

@MainActor
final class PlayerEngine: NSObject, ObservableObject {
    @Published var movie: MovieDetail
    @Published var servers: [EpisodeServer]
    @Published var serverIndex: Int
    @Published var episodeIndex: Int

    @Published var isPlaying: Bool = false
    @Published var isBuffering: Bool = true
    @Published var isFailed: Bool = false
    @Published var errorMessage: String = ""
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var bufferedAhead: Double = 0
    @Published var playbackRate: Float = 1.0
    @Published var currentSourceLabel: String = "HLS"
    @Published var activeStreamURL: String = ""
    @Published var adMarkers: [AdMarker] = []
    @Published var activeSkipPrompt: AdMarker?
    @Published var activeOutroPrompt: AdMarker?
    @Published var undoSkipTime: Double?
    @Published var statusToast: String?
    @Published var isPiPActive: Bool = false
    @Published var isPiPPossible: Bool = false
    @Published var aspectMode: PlayerAspectMode = .fitSafe
    @Published var videoGravity: AVLayerVideoGravity = .resizeAspect
    @Published var flipHorizontal: Bool = false
    @Published var flipVertical: Bool = false
    var closingExplicitly: Bool = false

    let player = AVPlayer()
    let playerLayer = AVPlayerLayer()

    private var pipController: AVPictureInPictureController?
    private var pipPossibleObserver: NSKeyValueObservation?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var bufferObserver: NSKeyValueObservation?
    private var stallTimer: Task<Void, Never>?
    private var undoClearTask: Task<Void, Never>?
    private var promptAutoHideTask: Task<Void, Never>?
    private var shownPromptIds = Set<String>()
    private var endObserver: NSObjectProtocol?
    private var artworkImage: UIImage?
    private var remoteCommandsConfigured = false
    private var usingCleanSource = true
    private var didFailoverThisEpisode = false
    private var lastSavedProgressTimestamp: Double = -999
    private var skippedCutIds = Set<String>()
    private var dismissedSkipIds = Set<String>()
    private var userSeekedInsideAdIds = Set<String>()
    private var lastPlayPosSec: Double = 0
    private var pendingResumeSeconds: Double

    init(movie: MovieDetail, servers: [EpisodeServer], serverIndex: Int, episodeIndex: Int, resumeTime: Double) {
        self.movie = movie
        self.servers = servers
        self.serverIndex = serverIndex
        self.episodeIndex = episodeIndex
        self.pendingResumeSeconds = resumeTime
        super.init()

        playerLayer.player = player
        playerLayer.videoGravity = videoGravity

        AudioSpatialEngine.shared.configureAudioSession()
        configurePiPController()
        configureRemoteCommands()
        preloadPosterArtwork()
        loadCurrentEpisode()
    }

    var currentEpisode: EpisodeItem? {
        servers[safe: serverIndex]?.server_data[safe: episodeIndex]
    }

    var hasPreviousEpisode: Bool {
        episodeIndex > 0
    }

    var hasNextEpisode: Bool {
        let count = servers[safe: serverIndex]?.server_data.count ?? 0
        return episodeIndex + 1 < count
    }

    private func configurePiPController() {
        guard AVPictureInPictureController.isPictureInPictureSupported() else { return }
        let pip = AVPictureInPictureController(playerLayer: playerLayer)
        pip?.delegate = self
        if #available(iOS 14.2, *) {
            pip?.canStartPictureInPictureAutomaticallyFromInline = AppPreferences.shared.autoPiP
        }
        self.pipController = pip
        self.isPiPPossible = pip?.isPictureInPicturePossible ?? true

        pipPossibleObserver = pip?.observe(\.isPictureInPicturePossible, options: [.new, .initial]) { [weak self] ctrl, _ in
            Task { @MainActor in
                self?.isPiPPossible = ctrl.isPictureInPicturePossible
            }
        }
    }

    func syncAutoPiPPreference() {
        if #available(iOS 14.2, *) {
            pipController?.canStartPictureInPictureAutomaticallyFromInline = AppPreferences.shared.autoPiP
        }
    }

    func updateAspectMode(_ mode: PlayerAspectMode) {
        aspectMode = mode
        videoGravity = mode.layerGravity
        playerLayer.videoGravity = mode.layerGravity
    }

    func cycleAspectMode() {
        let all = PlayerAspectMode.allCases
        if let idx = all.firstIndex(of: aspectMode) {
            let next = all[(idx + 1) % all.count]
            updateAspectMode(next)
            showToast("Tỉ lệ: \(next.title)")
        }
    }

    func markClosingExplicitly() {
        closingExplicitly = true
        player.pause()
        isPlaying = false
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
    }

    func togglePiP() {
        guard let pip = pipController else { return }
        if pip.isPictureInPictureActive {
            pip.stopPictureInPicture()
        } else {
            pip.startPictureInPicture()
        }
    }

    func loadCurrentEpisode() {
        cleanupObservers()
        isFailed = false
        errorMessage = ""
        isBuffering = true
        activeSkipPrompt = nil
        activeOutroPrompt = nil
        undoSkipTime = nil
        skippedCutIds.removeAll()
        dismissedSkipIds.removeAll()
        shownPromptIds.removeAll()
        userSeekedInsideAdIds.removeAll()
        lastPlayPosSec = 0
        didFailoverThisEpisode = false

        guard let ep = currentEpisode else {
            isFailed = true
            isBuffering = false
            errorMessage = "Không tìm thấy tập phim."
            return
        }

        usingCleanSource = true
        startPlaybackStream(for: ep, useClean: true)

        let epKey = ep.slug.isEmpty ? "\(episodeIndex)" : ep.slug
        let titleHint = (movie.origin_name?.isEmpty == false ? movie.origin_name : movie.name) ?? movie.name
        Task {
            if let ads = try? await ManiFlixAPI.shared.fetchAdsMarkers(slug: movie.slug, ep: epKey, titleHint: titleHint) {
                self.adMarkers = ads.markers ?? []
            } else {
                self.adMarkers = []
            }
        }
    }

    private func startPlaybackStream(for ep: EpisodeItem, useClean: Bool) {
        let rawM3U8 = ep.link_m3u8?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawM3U8.isEmpty else {
            isFailed = true
            isBuffering = false
            errorMessage = "Tập này chưa có luồng phát HLS."
            return
        }

        let resolvedURL: URL?
        if useClean, let clean = ManiFlixAPI.shared.cleanM3U8URL(from: rawM3U8) {
            resolvedURL = clean
            currentSourceLabel = "Chuẩn"
        } else {
            resolvedURL = URL(string: rawM3U8)
            currentSourceLabel = "Dự phòng"
        }

        guard let url = resolvedURL else {
            isFailed = true
            isBuffering = false
            errorMessage = "Địa chỉ luồng phát không hợp lệ."
            return
        }

        activeStreamURL = url.absoluteString
        let asset = AVURLAsset(url: url, options: [
            "AVURLAssetHTTPHeaderFieldsKey": [
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15"
            ]
        ])
        let item = AVPlayerItem(asset: asset)
        AudioSpatialEngine.shared.applySettings(to: item, player: player)

        player.replaceCurrentItem(with: item)
        attachItemObservers(item: item)
        player.play()
        player.rate = playbackRate
        isPlaying = true
        updateNowPlayingInfo()

        scheduleFailoverWatchdog(for: ep)
    }

    private func scheduleFailoverWatchdog(for ep: EpisodeItem) {
        stallTimer?.cancel()
        stallTimer = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_500_000_000)
            guard !Task.isCancelled, let self = self else { return }
            if self.isBuffering && self.currentTime < 0.5 && !self.didFailoverThisEpisode {
                self.tryFailoverStream(for: ep, reason: "Đang đổi sang nguồn dự phòng...")
            }
        }
    }

    private func tryFailoverStream(for ep: EpisodeItem, reason: String) {
        guard !didFailoverThisEpisode else {
            isFailed = true
            isBuffering = false
            errorMessage = reason
            return
        }
        didFailoverThisEpisode = true
        usingCleanSource.toggle()
        showToast(usingCleanSource ? "Đổi sang nguồn lọc quảng cáo" : "Đổi sang nguồn gốc")
        startPlaybackStream(for: ep, useClean: usingCleanSource)
    }

    private func attachItemObservers(item: AVPlayerItem) {
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor in
                guard let self = self else { return }
                switch observedItem.status {
                case .readyToPlay:
                    self.isBuffering = false
                    self.stallTimer?.cancel()
                    let dur = observedItem.duration.seconds
                    if dur.isFinite && dur > 0 {
                        self.duration = dur
                    }
                    if self.pendingResumeSeconds > 3 {
                        let limit = dur.isFinite ? max(0, dur - 10) : self.pendingResumeSeconds
                        let target = min(self.pendingResumeSeconds, limit)
                        self.pendingResumeSeconds = 0
                        self.seek(to: target)
                        self.showToast("Phát tiếp từ \(Self.formatTime(target))")
                    }
                    self.updateNowPlayingInfo()
                case .failed:
                    let desc = observedItem.error?.localizedDescription ?? "Không tải được luồng phát"
                    if let ep = self.currentEpisode {
                        self.tryFailoverStream(for: ep, reason: desc)
                    } else {
                        self.isFailed = true
                        self.isBuffering = false
                        self.errorMessage = desc
                    }
                default:
                    break
                }
            }
        }

        bufferObserver = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] observedItem, _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.isBuffering = !observedItem.isPlaybackLikelyToKeepUp
                if let range = observedItem.loadedTimeRanges.first?.timeRangeValue {
                    let loadedEnd = CMTimeGetSeconds(range.start) + CMTimeGetSeconds(range.duration)
                    self.bufferedAhead = max(0, loadedEnd - self.currentTime)
                }
            }
        }

        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                guard let self = self else { return }
                let sec = time.seconds
                if sec.isFinite {
                    self.currentTime = sec
                    if let dur = self.player.currentItem?.duration.seconds, dur.isFinite && dur > 0 {
                        self.duration = dur
                    }
                    if self.isBuffering && sec > 0.2 && (self.player.currentItem?.isPlaybackLikelyToKeepUp ?? false) {
                        self.isBuffering = false
                    }
                    self.evaluateAdAndIntroMarkers(at: sec)
                    self.maybeSyncHistory(at: sec)
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                self.isPlaying = false
                if AppPreferences.shared.autoNextEpisode && self.hasNextEpisode {
                    self.nextEpisode()
                }
            }
        }
    }

    func effectiveEnd(for marker: AdMarker) -> Double {
        if marker.openEnd == true && duration > marker.start {
            return duration
        }
        return marker.end
    }

    var filteredTimelineMarkers: [AdMarker] {
        adMarkers.filter { m in
            let endSec = effectiveEnd(for: m)
            guard endSec > m.start else { return false }
            if m.type == "outro" && m.start < 30 { return false }
            let cap = duration > 0 ? min(420.0, duration * 0.45) : 420.0
            return (endSec - m.start) <= cap
        }
    }

    private func evaluateAdAndIntroMarkers(at sec: Double) {
        let prefs = AppPreferences.shared
        let validMarkers = filteredTimelineMarkers

        for m in validMarkers where (m.type == "ad" || m.mode == "cut") {
            let endSec = effectiveEnd(for: m)
            if sec < m.start - 1 || sec >= endSec {
                userSeekedInsideAdIds.remove(m.id)
            } else if abs(sec - lastPlayPosSec) > 3.5 && sec > m.start + 1.5 && sec < endSec {
                userSeekedInsideAdIds.insert(m.id)
            }
        }

        // 1. Auto-cut Ads (only at boundary or normal playback progression, matching watch.html)
        if prefs.autoCutAds {
            for marker in validMarkers {
                let endSec = effectiveEnd(for: marker)
                let mode = marker.mode ?? (marker.type == "ad" ? "cut" : (marker.type == "credit" ? "mark" : "skip"))
                if mode == "cut" && !userSeekedInsideAdIds.contains(marker.id) && !skippedCutIds.contains(marker.id) {
                    let atEntry = sec >= marker.start && sec < min(endSec, marker.start + 1.2)
                    let crossedStart = lastPlayPosSec < marker.start && sec >= marker.start && sec < endSec
                    if atEntry || crossedStart {
                        skippedCutIds.insert(marker.id)
                        lastPlayPosSec = endSec + 0.1
                        seek(to: endSec + 0.1)
                        showToast("Đã bỏ qua quảng cáo")
                        return
                    }
                }
            }
        }
        lastPlayPosSec = sec

        // 2. Intro / Recap (strictly type != "outro", matching watch.html)
        var foundIntro: AdMarker? = nil
        if prefs.introSkipBehavior != .off {
            for marker in validMarkers {
                let mode = marker.mode ?? (marker.type == "ad" ? "cut" : (marker.type == "credit" ? "mark" : "skip"))
                guard mode == "skip" && marker.type != "outro" else { continue }
                let endSec = effectiveEnd(for: marker)
                if sec >= marker.start && sec < endSec - 0.5 {
                    if prefs.introSkipBehavior == .auto && !skippedCutIds.contains(marker.id) {
                        skippedCutIds.insert(marker.id)
                        recordUndoAnchor(previousTime: sec)
                        seek(to: endSec + 0.1)
                        return
                    } else if !dismissedSkipIds.contains(marker.id) && !skippedCutIds.contains(marker.id) {
                        foundIntro = marker
                        break
                    }
                } else if sec < marker.start {
                    shownPromptIds.remove(marker.id)
                }
            }
        }

        if let intro = foundIntro {
            if !shownPromptIds.contains(intro.id) {
                shownPromptIds.insert(intro.id)
                activeSkipPrompt = intro
                scheduleIntroPromptAutoHide(for: intro.id)
            }
        } else {
            if activeSkipPrompt != nil {
                activeSkipPrompt = nil
            }
        }

        // 3. Outro / Credits window
        var foundOutro: AdMarker? = nil
        if prefs.introSkipBehavior != .off {
            for marker in validMarkers where marker.type == "outro" {
                let mode = marker.mode ?? "skip"
                guard mode != "mark" else { continue }
                let endSec = effectiveEnd(for: marker)
                if sec >= marker.start && sec < endSec - 0.5 && !dismissedSkipIds.contains(marker.id) {
                    foundOutro = marker
                    break
                }
            }
        }
        activeOutroPrompt = foundOutro
    }

    private func scheduleIntroPromptAutoHide(for markerId: String) {
        promptAutoHideTask?.cancel()
        promptAutoHideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            if self.activeSkipPrompt?.id == markerId {
                self.activeSkipPrompt = nil
            }
        }
    }

    private func recordUndoAnchor(previousTime: Double) {
        undoSkipTime = previousTime
        undoClearTask?.cancel()
        undoClearTask = Task {
            try? await Task.sleep(nanoseconds: 5_500_000_000)
            guard !Task.isCancelled else { return }
            self.undoSkipTime = nil
        }
    }

    func undoLastSkip() {
        guard let prev = undoSkipTime else { return }
        undoSkipTime = nil
        seek(to: prev)
        showToast("Đã hoàn tác vị trí trước khi bỏ qua")
    }

    private func maybeSyncHistory(at sec: Double) {
        guard sec > 5, duration > 10 else { return }
        if abs(sec - lastSavedProgressTimestamp) >= 12 {
            lastSavedProgressTimestamp = sec
            updateNowPlayingInfo()
            let epName = currentEpisode?.name ?? "Tập \(episodeIndex + 1)"
            Task {
                await AppState.shared.recordProgress(
                    movie: movie,
                    episodeIndex: episodeIndex,
                    episodeName: epName,
                    currentTime: sec,
                    duration: duration
                )
            }
        }
    }

    private func configureRemoteCommands() {
        guard !remoteCommandsConfigured else { return }
        remoteCommandsConfigured = true
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.isEnabled = true
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }

        center.pauseCommand.isEnabled = true
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isPlaying else { return }
                self.togglePlayPause()
            }
            return .success
        }

        center.togglePlayPauseCommand.isEnabled = true
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }

        center.skipForwardCommand.isEnabled = true
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: AppPreferences.shared.doubleTapSeekSeconds)]
        center.skipForwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.seekRelative(Double(AppPreferences.shared.doubleTapSeekSeconds))
            }
            return .success
        }

        center.skipBackwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: AppPreferences.shared.doubleTapSeekSeconds)]
        center.skipBackwardCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                self?.seekRelative(-Double(AppPreferences.shared.doubleTapSeekSeconds))
            }
            return .success
        }

        center.changePlaybackPositionCommand.isEnabled = true
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let posEvent = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in
                self?.seek(to: posEvent.positionTime)
            }
            return .success
        }
    }

    private func preloadPosterArtwork() {
        guard let url = movie.displayPosterURL else { return }
        if let cached = ImageCacheStore.shared.image(for: url) {
            self.artworkImage = cached
            updateNowPlayingInfo()
            return
        }
        Task {
            if let (data, _) = try? await URLSession.shared.data(from: url),
               let img = UIImage(data: data) {
                self.artworkImage = img
                self.updateNowPlayingInfo()
            }
        }
    }

    private func updateNowPlayingInfo() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: movie.name,
            MPMediaItemPropertyAlbumTitle: currentEpisode?.name ?? "",
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0.0
        ]
        if let img = artworkImage {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: img.size) { _ in img }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func togglePlayPause() {
        if isPlaying {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            player.rate = playbackRate
            isPlaying = true
        }
        updateNowPlayingInfo()
        Haptics.impact(.light)
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        let cm = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
        currentTime = clamped
        updateNowPlayingInfo()
    }

    func seekRelative(_ delta: Double) {
        seek(to: currentTime + delta)
    }

    func setRate(_ rate: Float) {
        playbackRate = rate
        if isPlaying {
            player.rate = rate
        }
        updateNowPlayingInfo()
        showToast("Tốc độ \(String(format: "%.2g", rate))x")
    }

    func skipActiveMarker() {
        guard let marker = activeSkipPrompt else { return }
        let endSec = effectiveEnd(for: marker)
        skippedCutIds.insert(marker.id)
        activeSkipPrompt = nil
        recordUndoAnchor(previousTime: currentTime)
        seek(to: endSec + 0.1)
        Haptics.impact(.medium)
    }

    func dismissSkipPrompt() {
        if let marker = activeSkipPrompt {
            dismissedSkipIds.insert(marker.id)
        }
        activeSkipPrompt = nil
    }

    func handleOutroAction() {
        guard let marker = activeOutroPrompt else { return }
        dismissedSkipIds.insert(marker.id)
        activeOutroPrompt = nil
        if hasNextEpisode {
            nextEpisode()
        } else {
            let endSec = effectiveEnd(for: marker)
            recordUndoAnchor(previousTime: currentTime)
            seek(to: min(endSec + 0.1, max(0, duration - 1)))
        }
        Haptics.impact(.medium)
    }

    func dismissOutroPrompt() {
        if let marker = activeOutroPrompt {
            dismissedSkipIds.insert(marker.id)
        }
        activeOutroPrompt = nil
    }

    func selectEpisode(serverIdx: Int, epIdx: Int) {
        serverIndex = serverIdx
        episodeIndex = epIdx
        pendingResumeSeconds = AppState.shared.savedResumeTime(slug: movie.slug, episodeIndex: epIdx)
        loadCurrentEpisode()
    }

    func previousEpisode() {
        guard hasPreviousEpisode else { return }
        selectEpisode(serverIdx: serverIndex, epIdx: episodeIndex - 1)
    }

    func nextEpisode() {
        guard hasNextEpisode else { return }
        selectEpisode(serverIdx: serverIndex, epIdx: episodeIndex + 1)
    }

    func refreshSpatialAudio() {
        AudioSpatialEngine.shared.configureAudioSession()
        if let item = player.currentItem {
            AudioSpatialEngine.shared.applySettings(to: item, player: player)
        }
        showToast(AudioSpatialEngine.shared.activeSpatialSummary)
    }

    func showToast(_ text: String) {
        statusToast = text
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if self.statusToast == text {
                self.statusToast = nil
            }
        }
    }

    func shutdown() {
        let epName = currentEpisode?.name ?? "Tập \(episodeIndex + 1)"
        let cur = currentTime
        let dur = duration
        if cur > 5 && dur > 10 {
            Task {
                await AppState.shared.recordProgress(
                    movie: movie,
                    episodeIndex: episodeIndex,
                    episodeName: epName,
                    currentTime: cur,
                    duration: dur
                )
            }
        }
        if pipController?.isPictureInPictureActive == true {
            pipController?.stopPictureInPicture()
        }
        player.pause()
        cleanupObservers()
        pipPossibleObserver?.invalidate()
        pipPossibleObserver = nil
        player.replaceCurrentItem(with: nil)
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    private func cleanupObservers() {
        stallTimer?.cancel()
        if let obs = timeObserver {
            player.removeTimeObserver(obs)
            timeObserver = nil
        }
        statusObserver?.invalidate()
        statusObserver = nil
        bufferObserver?.invalidate()
        bufferObserver = nil
        if let endObs = endObserver {
            NotificationCenter.default.removeObserver(endObs)
            endObserver = nil
        }
    }

    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

extension PlayerEngine: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureControllerWillStartPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = true
        }
    }

    nonisolated func pictureInPictureControllerDidStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        Task { @MainActor in
            self.isPiPActive = false
            if !AppState.shared.isPlayerPresented && !self.isPlaying {
                AppState.shared.stopPlaybackCompletely()
            }
        }
    }

    nonisolated func pictureInPictureController(
        _ pictureInPictureController: AVPictureInPictureController,
        restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler: @escaping (Bool) -> Void
    ) {
        Task { @MainActor in
            AppState.shared.isPlayerPresented = true
            completionHandler(true)
        }
    }
}
