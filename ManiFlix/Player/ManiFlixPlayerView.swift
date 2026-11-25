import SwiftUI
import AVFoundation
import AVKit
import MediaPlayer

enum OrientationController {
    static var allowedMask: UIInterfaceOrientationMask = .portrait

    static func setLandscape(_ landscape: Bool) {
        allowedMask = landscape ? .landscape : .allButUpsideDown
        let targetMask: UIInterfaceOrientationMask = landscape ? .landscapeRight : .portrait

        if #available(iOS 16.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: targetMask)) { _ in }
                    windowScene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
                }
            }
        } else {
            let orient: UIInterfaceOrientation = landscape ? .landscapeRight : .portrait
            UIDevice.current.setValue(orient.rawValue, forKey: "orientation")
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }

    static func allowFreeRotation() {
        allowedMask = .allButUpsideDown
        if #available(iOS 16.0, *) {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    windowScene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
                }
            }
        }
    }

    static func resetPortrait() {
        setLandscape(false)
        allowedMask = .portrait
    }
}

struct SharedPlayerLayerHost: UIViewRepresentable {
    let engine: PlayerEngine

    func makeUIView(context: Context) -> PlayerLayerHostUIView {
        let view = PlayerLayerHostUIView()
        view.backgroundColor = .black
        view.attach(layer: engine.playerLayer)
        return view
    }

    func updateUIView(_ uiView: PlayerLayerHostUIView, context: Context) {
        uiView.attach(layer: engine.playerLayer)
        engine.playerLayer.videoGravity = engine.videoGravity
    }
}

final class PlayerLayerHostUIView: UIView {
    private weak var hostedLayer: AVPlayerLayer?

    func attach(layer: AVPlayerLayer) {
        if hostedLayer !== layer || layer.superlayer !== self.layer {
            layer.removeFromSuperlayer()
            self.layer.addSublayer(layer)
            hostedLayer = layer
        }
        layer.frame = bounds
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hostedLayer?.frame = bounds
        CATransaction.commit()
    }
}

struct AirPlayPickerButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.activeTintColor = UIColor(AppPreferences.shared.accentPreset.color)
        picker.tintColor = .white
        picker.prioritizesVideoDevices = true
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

final class SystemVolumeController {
    static let shared = SystemVolumeController()
    private let volumeView = MPVolumeView(frame: CGRect(x: -9999, y: -9999, width: 1, height: 1))

    var currentVolume: Float {
        AVAudioSession.sharedInstance().outputVolume
    }

    func setVolume(_ value: Float) {
        let clamped = max(0, min(1, value))
        if let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider {
            DispatchQueue.main.async {
                slider.value = clamped
            }
        }
    }
}

struct ManiFlixPlayerView: View {
    @ObservedObject var engine: PlayerEngine
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var spatial = AudioSpatialEngine.shared
    @ObservedObject private var appState = AppState.shared
    @Environment(\.dismiss) private var dismiss

    @State private var showControls = true
    @State private var isLocked = false
    @State private var isLandscape = false
    @State private var showEpisodeDrawer = false
    @State private var showAudioDrawer = false
    @State private var autoHideTask: Task<Void, Never>?

    @State private var isLongPressBoosting = false
    @State private var seekPulseText: String?
    @State private var gestureHUDIcon: String?
    @State private var gestureHUDValue: Double = 0
    @State private var dragStartValue: Double?
    @State private var isDraggingScrubber = false
    @State private var scrubPreviewTime: Double = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            // Video layer respects Safe Area (Dynamic Island) unless Tràn viền is selected
            videoSurface
                .scaleEffect(x: engine.flipHorizontal ? -1 : 1, y: engine.flipVertical ? -1 : 1)
                .ignoresSafeArea(edges: engine.aspectMode == .edgeFill ? .all : [])

            GeometryReader { geo in
                gestureLayer(in: geo.size)
            }

            centerStatusOverlay

            if let icon = gestureHUDIcon {
                HStack(spacing: 10) {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    ProgressView(value: gestureHUDValue)
                        .tint(.white)
                        .frame(width: 110)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .adaptiveGlassCapsule(interactive: false)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 16)
            }

            if isLongPressBoosting {
                HStack(spacing: 5) {
                    Image(systemName: "forward.fill")
                        .font(.caption2)
                    Text("\(String(format: "%.2g", prefs.longPressSpeed))x")
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .adaptiveGlassCapsule(interactive: false)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, 16)
            }

            if let marker = engine.activeSkipPrompt, !isLocked {
                let skipTitle: String = {
                    if marker.type == "recap" { return "Bỏ qua tóm tắt" }
                    if marker.type == "intro" { return "Bỏ qua phần giới thiệu" }
                    return "Bỏ qua phân đoạn"
                }()
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Button {
                                engine.skipActiveMarker()
                            } label: {
                                Text(skipTitle)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                            }
                            Button {
                                engine.dismissSkipPrompt()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundColor(Color(white: 0.7))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .adaptiveGlassCapsule(interactive: true)
                        .padding(.trailing, 20)
                        .padding(.bottom, showControls ? 96 : 24)
                    }
                }
                .zIndex(35)
            } else if engine.activeOutroPrompt != nil, !isLocked {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 10) {
                            Button {
                                engine.handleOutroAction()
                            } label: {
                                Text(engine.hasNextEpisode ? "Tập tiếp theo" : "Bỏ qua kết thúc")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundColor(.white)
                            }
                            Button {
                                engine.dismissOutroPrompt()
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundColor(Color(white: 0.7))
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .adaptiveGlassCapsule(interactive: true)
                        .padding(.trailing, 20)
                        .padding(.bottom, showControls ? 96 : 24)
                    }
                }
                .zIndex(35)
            }

            if engine.undoSkipTime != nil, !isLocked {
                VStack {
                    Spacer()
                    HStack {
                        Button {
                            engine.undoLastSkip()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.caption)
                                Text("Hoàn tác")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                        }
                        .adaptiveGlassCapsule(interactive: true)
                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.bottom, showControls ? 96 : 24)
                }
                .zIndex(35)
            }

            if let toast = engine.statusToast {
                Text(toast)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .adaptiveGlassCapsule(interactive: false)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 52)
            }

            if showControls {
                if isLocked {
                    lockedControlsOverlay
                        .zIndex(30)
                } else {
                    fullControlsOverlay
                        .zIndex(30)
                }
            }
        }
        .statusBarHidden(true)
        .onAppear {
            engine.closingExplicitly = false
            engine.syncAutoPiPPreference()
            OrientationController.allowFreeRotation()
            if prefs.autoRotateLandscape {
                isLandscape = true
                OrientationController.setLandscape(true)
            }
            scheduleAutoHide()
        }
        .onDisappear {
            OrientationController.resetPortrait()
        }
        .sheet(isPresented: $showEpisodeDrawer) {
            episodeDrawerSheet
        }
        .sheet(isPresented: $showAudioDrawer) {
            audioSpatialDrawerSheet
        }
    }

    @ViewBuilder
    private var videoSurface: some View {
        if let ratio = engine.aspectMode.explicitRatio {
            SharedPlayerLayerHost(engine: engine)
                .aspectRatio(ratio, contentMode: .fit)
                .clipped()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            SharedPlayerLayerHost(engine: engine)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func closePlayerTapped() {
        engine.markClosingExplicitly()
        appState.isPlayerPresented = false
        dismiss()
    }

    private func gestureLayer(in size: CGSize) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard !isLocked else { return }
                    let sec = Double(prefs.doubleTapSeekSeconds)
                    engine.seekRelative(-sec)
                    triggerSeekPulse("-\(Int(sec))s")
                }
                .onTapGesture(count: 1) {
                    toggleControls()
                }
                .gesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            guard !isLocked else { return }
                            if abs(value.translation.height) > abs(value.translation.width) {
                                if !isLandscape && value.startLocation.y < 120 && value.translation.height > 95 {
                                    closePlayerTapped()
                                    return
                                }
                                let start = dragStartValue ?? currentBrightness()
                                if dragStartValue == nil { dragStartValue = start }
                                let delta = Double(-value.translation.height / max(size.height * 0.55, 160))
                                let next = min(max(start + delta, 0.05), 1.0)
                                setBrightness(next)
                                gestureHUDIcon = "sun.max.fill"
                                gestureHUDValue = next
                            }
                        }
                        .onEnded { _ in
                            dragStartValue = nil
                            gestureHUDIcon = nil
                        }
                )

            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    guard !isLocked else { return }
                    let sec = Double(prefs.doubleTapSeekSeconds)
                    engine.seekRelative(sec)
                    triggerSeekPulse("+\(Int(sec))s")
                }
                .onTapGesture(count: 1) {
                    toggleControls()
                }
                .gesture(
                    DragGesture(minimumDistance: 18)
                        .onChanged { value in
                            guard !isLocked else { return }
                            if abs(value.translation.height) > abs(value.translation.width) {
                                if !isLandscape && value.startLocation.y < 120 && value.translation.height > 95 {
                                    closePlayerTapped()
                                    return
                                }
                                let start = dragStartValue ?? Double(SystemVolumeController.shared.currentVolume)
                                if dragStartValue == nil { dragStartValue = start }
                                let delta = Double(-value.translation.height / max(size.height * 0.55, 160))
                                let next = min(max(start + delta, 0), 1.0)
                                SystemVolumeController.shared.setVolume(Float(next))
                                gestureHUDIcon = "speaker.wave.2.fill"
                                gestureHUDValue = next
                            }
                        }
                        .onEnded { _ in
                            dragStartValue = nil
                            gestureHUDIcon = nil
                        }
                )
        }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    guard !isLocked else { return }
                    isLongPressBoosting = true
                    engine.player.rate = Float(prefs.longPressSpeed)
                    Haptics.impact(.medium)
                }
                .sequenced(before: DragGesture(minimumDistance: 0))
                .onEnded { _ in
                    if isLongPressBoosting {
                        isLongPressBoosting = false
                        if engine.isPlaying {
                            engine.player.rate = engine.playbackRate
                        }
                    }
                }
        )
    }

    private var centerStatusOverlay: some View {
        VStack(spacing: 12) {
            if let pulse = seekPulseText {
                Text(pulse)
                    .font(.title3.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .adaptiveGlassCapsule(interactive: false)
            } else if engine.isFailed {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.title2)
                        .foregroundColor(Color(white: 0.8))
                    Text("Không thể phát tập này")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                    Text(engine.errorMessage)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.6))
                        .multilineTextAlignment(.center)
                    Button {
                        engine.loadCurrentEpisode()
                    } label: {
                        Text("Thử lại")
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                    }
                    .adaptiveGlassCapsule(interactive: true)
                }
                .padding(20)
                .adaptiveGlassCard(cornerRadius: 16)
                .padding(.horizontal, 36)
            } else if engine.isBuffering {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.2)
            }
        }
    }

    private var lockedControlsOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    isLocked = false
                    scheduleAutoHide()
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "lock.open")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .adaptiveGlassCapsule()
                .padding(.trailing, 16)
                .padding(.top, 12)
            }
            Spacer()
        }
    }

    private var fullControlsOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button {
                    closePlayerTapped()
                } label: {
                    Image(systemName: "xmark")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .adaptiveGlassCapsule()

                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.movie.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)
                    Text("\(engine.currentEpisode?.name ?? "Tập 1") • \(engine.currentSourceLabel)")
                        .font(.caption2)
                        .foregroundColor(Color(white: 0.7))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    showAudioDrawer = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: spatial.isHeadphoneOutput ? "airpodspro" : "slider.horizontal.3")
                            .font(.caption)
                        Text(spatial.isHeadphoneOutput ? "Spatial" : "\(String(format: "%.2g", engine.playbackRate))x")
                            .font(.caption.weight(.medium))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 34)
                }
                .adaptiveGlassCapsule()

                AirPlayPickerButton()
                    .frame(width: 34, height: 34)
                    .adaptiveGlassCapsule()

                if AVPictureInPictureController.isPictureInPictureSupported() {
                    Button {
                        if !engine.isPiPActive {
                            engine.togglePiP()
                            Task {
                                try? await Task.sleep(nanoseconds: 250_000_000)
                                appState.isPlayerPresented = false
                            }
                        } else {
                            engine.togglePiP()
                        }
                    } label: {
                        Image(systemName: engine.isPiPActive ? "pip.exit" : "pip.enter")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(width: 34, height: 34)
                    }
                    .adaptiveGlassCapsule()
                }

                Button {
                    isLocked = true
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: "lock")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 34, height: 34)
                }
                .adaptiveGlassCapsule()
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            Spacer()

            HStack(spacing: 38) {
                Button {
                    engine.seekRelative(-Double(prefs.doubleTapSeekSeconds))
                    scheduleAutoHide()
                } label: {
                    Image(systemName: "gobackward.\(prefs.doubleTapSeekSeconds)")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                }
                .adaptiveGlassCapsule()

                Button {
                    engine.togglePlayPause()
                    scheduleAutoHide()
                } label: {
                    Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(width: 64, height: 64)
                }
                .adaptiveGlassCapsule()

                Button {
                    engine.seekRelative(Double(prefs.doubleTapSeekSeconds))
                    scheduleAutoHide()
                } label: {
                    Image(systemName: "goforward.\(prefs.doubleTapSeekSeconds)")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                }
                .adaptiveGlassCapsule()
            }

            Spacer()

            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    Text(PlayerEngine.formatTime(isDraggingScrubber ? scrubPreviewTime : engine.currentTime))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.white)

                    ZStack(alignment: .center) {
                        if engine.duration > 1 && !engine.filteredTimelineMarkers.isEmpty {
                            GeometryReader { barGeo in
                                let dur = max(engine.duration, 1)
                                ForEach(engine.filteredTimelineMarkers) { mk in
                                    let st = min(max(mk.start / dur, 0), 1)
                                    let en = min(max(engine.effectiveEnd(for: mk) / dur, st), 1)
                                    let w = max(3, barGeo.size.width * CGFloat(en - st))
                                    let x = barGeo.size.width * CGFloat(st)
                                    Rectangle()
                                        .fill(markerSegmentColor(type: mk.type))
                                        .frame(width: w, height: 3.5)
                                        .cornerRadius(1.5)
                                        .offset(x: x, y: (barGeo.size.height - 3.5) / 2)
                                }
                            }
                            .frame(height: 28)
                            .allowsHitTesting(false)
                        }

                        Slider(
                            value: Binding(
                                get: { isDraggingScrubber ? scrubPreviewTime : engine.currentTime },
                                set: { newVal in
                                    isDraggingScrubber = true
                                    scrubPreviewTime = newVal
                                }
                            ),
                            in: 0...max(engine.duration, 1),
                            onEditingChanged: { editing in
                                if !editing {
                                    isDraggingScrubber = false
                                    engine.seek(to: scrubPreviewTime)
                                    scheduleAutoHide()
                                }
                            }
                        )
                        .tint(prefs.accentPreset.color)
                    }

                    Text(PlayerEngine.formatTime(engine.duration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(Color(white: 0.72))
                }

                HStack(spacing: 8) {
                    if engine.hasPreviousEpisode {
                        Button {
                            engine.previousEpisode()
                        } label: {
                            Image(systemName: "backward.end.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .frame(width: 34, height: 32)
                        }
                        .adaptiveGlassCapsule()
                    }

                    Button {
                        showEpisodeDrawer = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.grid.2x2")
                            Text("Tập & nguồn")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                    }
                    .adaptiveGlassCapsule()

                    if engine.hasNextEpisode {
                        Button {
                            engine.nextEpisode()
                        } label: {
                            Image(systemName: "forward.end.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .frame(width: 34, height: 32)
                        }
                        .adaptiveGlassCapsule()
                    }

                    Spacer()

                    Button {
                        engine.cycleAspectMode()
                        scheduleAutoHide()
                        Haptics.impact(.light)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "aspectratio")
                            Text(engine.aspectMode.title)
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                    }
                    .adaptiveGlassCapsule()

                    Button {
                        isLandscape.toggle()
                        OrientationController.setLandscape(isLandscape)
                        scheduleAutoHide()
                        Haptics.impact(.light)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isLandscape ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate")
                            Text(isLandscape ? "Dọc" : "Ngang")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                    }
                    .adaptiveGlassCapsule()
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0.62), .clear, .clear, Color.black.opacity(0.74)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        )
    }

    private var episodeDrawerSheet: some View {
        NavigationView {
            List {
                Section("Máy chủ") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(engine.servers.enumerated()), id: \.offset) { idx, srv in
                                Button {
                                    engine.selectEpisode(serverIdx: idx, epIdx: min(engine.episodeIndex, max(0, srv.server_data.count - 1)))
                                } label: {
                                    Text(srv.server_name)
                                        .font(.caption.weight(.medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .foregroundColor(.white)
                                }
                                .adaptiveGlassCapsule(tint: idx == engine.serverIndex ? prefs.accentPreset.color : nil)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if let currentSrv = engine.servers[safe: engine.serverIndex] {
                    Section("Danh sách tập (\(currentSrv.server_data.count))") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
                            ForEach(Array(currentSrv.server_data.enumerated()), id: \.offset) { epIdx, ep in
                                Button {
                                    engine.selectEpisode(serverIdx: engine.serverIndex, epIdx: epIdx)
                                    showEpisodeDrawer = false
                                } label: {
                                    Text(ep.name)
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 9)
                                        .foregroundColor(.white)
                                }
                                .adaptiveGlassCard(
                                    cornerRadius: 9,
                                    interactive: true,
                                    tint: epIdx == engine.episodeIndex ? prefs.accentPreset.color : nil
                                )
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Tập & nguồn phát")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { showEpisodeDrawer = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var audioSpatialDrawerSheet: some View {
        NavigationView {
            Form {
                Section("Âm thanh không gian (Spatial Audio)") {
                    HStack {
                        Text("Thiết bị đầu ra")
                        Spacer()
                        Text(spatial.outputRouteName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    HStack {
                        Text("Cảm biến chuyển động đầu")
                        Spacer()
                        Text(spatial.isHeadTrackingHardwareReady ? "Đang hoạt động" : "Không hoạt động")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("Chế độ không gian", selection: $prefs.spatialAudioMode) {
                        ForEach(SpatialAudioMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .onChange(of: prefs.spatialAudioMode) { _ in engine.refreshSpatialAudio() }

                    Picker("Cấu hình âm", selection: $prefs.soundProfile) {
                        ForEach(SoundProfileMode.allCases) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .onChange(of: prefs.soundProfile) { _ in engine.refreshSpatialAudio() }

                    Picker("Xử lý cao độ khi tua", selection: $prefs.pitchAlgorithm) {
                        ForEach(AudioPitchAlgorithmMode.allCases) { a in
                            Text(a.title).tag(a)
                        }
                    }
                    .onChange(of: prefs.pitchAlgorithm) { _ in engine.refreshSpatialAudio() }

                    VStack(alignment: .leading) {
                        HStack {
                            Text("Mức âm lượng nội bộ")
                            Spacer()
                            Text("\(Int(prefs.comfortGain * 100))%")
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $prefs.comfortGain, in: 0.35...1.0, step: 0.05) { _ in
                            engine.refreshSpatialAudio()
                        }
                    }
                }

                Section("Tỉ lệ & khung hình") {
                    Picker("Tỉ lệ khung hình", selection: Binding(
                        get: { engine.aspectMode },
                        set: { engine.updateAspectMode($0) }
                    )) {
                        ForEach(PlayerAspectMode.allCases, id: \.self) { m in
                            Text(m.title).tag(m)
                        }
                    }
                    Toggle("Lật ngang khung hình", isOn: $engine.flipHorizontal)
                    Toggle("Lật dọc khung hình", isOn: $engine.flipVertical)
                }

                Section("Tốc độ phát") {
                    HStack(spacing: 8) {
                        ForEach([Float(0.75), 1.0, 1.25, 1.5, 2.0], id: \.self) { rate in
                            Button {
                                engine.setRate(rate)
                            } label: {
                                Text("\(String(format: "%.2g", rate))x")
                                    .font(.caption.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(engine.playbackRate == rate ? prefs.accentPreset.color : Color.gray.opacity(0.28))
                        }
                    }
                }

                Section("Liên kết & mở ngoài") {
                    Button {
                        if let ep = engine.currentEpisode, let raw = ep.link_m3u8 {
                            UIPasteboard.general.string = engine.activeStreamURL.isEmpty ? raw : engine.activeStreamURL
                            engine.showToast("Đã sao chép liên kết HLS")
                            showAudioDrawer = false
                        }
                    } label: {
                        Label("Sao chép liên kết .m3u8", systemImage: "doc.on.doc")
                    }

                    ForEach([ExternalPlayerOption.vlc, .outplayer, .infuse]) { ext in
                        Button {
                            let target = engine.activeStreamURL.isEmpty ? (engine.currentEpisode?.link_m3u8 ?? "") : engine.activeStreamURL
                            if !ExternalPlayerLauncher.open(url: target, option: ext) {
                                engine.showToast("Thiết bị chưa cài \(ext.title)")
                            }
                        } label: {
                            Label("Mở bằng \(ext.title)", systemImage: "arrow.up.forward.app")
                        }
                    }
                }
            }
            .navigationTitle("Âm thanh & phát")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Xong") { showAudioDrawer = false }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showControls.toggle()
        }
        if showControls {
            scheduleAutoHide()
        }
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            if engine.isPlaying && !isDraggingScrubber {
                withAnimation(.easeOut(duration: 0.22)) {
                    showControls = false
                }
            }
        }
    }

    private func triggerSeekPulse(_ text: String) {
        seekPulseText = text
        Haptics.impact(.light)
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            if seekPulseText == text {
                seekPulseText = nil
            }
        }
    }

    private func currentBrightness() -> Double {
        let screen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first ?? UIScreen.main
        return Double(screen.brightness)
    }

    private func setBrightness(_ val: Double) {
        let screen = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.screen }.first ?? UIScreen.main
        screen.brightness = CGFloat(val)
    }

    private func markerSegmentColor(type: String?) -> Color {
        switch type {
        case "ad": return Color(red: 0.13, green: 0.77, blue: 0.37)
        case "recap": return Color(red: 0.93, green: 0.28, blue: 0.60)
        case "credit": return Color(red: 0.96, green: 0.62, blue: 0.04)
        default: return Color(red: 0.03, green: 0.57, blue: 0.70)
        }
    }
}
