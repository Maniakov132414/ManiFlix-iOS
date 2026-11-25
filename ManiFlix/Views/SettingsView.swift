import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var spatial = AudioSpatialEngine.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var updates = UpdateManager.shared
    @State private var showHiddenMovies = false

    var body: some View {
        Form {
            Section("Tài khoản") {
                if appState.isLoggedIn, let user = appState.currentUser {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.displayName ?? user.username)
                                .font(.subheadline.weight(.semibold))
                            Text("@\(user.username)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Đăng xuất", role: .destructive) {
                            appState.logout()
                        }
                        .font(.caption)
                    }
                } else {
                    Button {
                        appState.showAuthSheet = true
                    } label: {
                        Text("Đăng nhập hoặc tạo tài khoản")
                    }
                }
            }

            Section {
                HStack {
                    Text("Đầu ra âm thanh")
                    Spacer()
                    Text(spatial.outputRouteName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Theo dõi chuyển động đầu")
                    Spacer()
                    Text(spatial.isHeadTrackingHardwareReady ? "Hỗ trợ" : "Không hoạt động")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Picker("Âm thanh không gian", selection: $prefs.spatialAudioMode) {
                    ForEach(SpatialAudioMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Picker("Cấu hình âm", selection: $prefs.soundProfile) {
                    ForEach(SoundProfileMode.allCases) { prof in
                        Text(prof.title).tag(prof)
                    }
                }

                Picker("Xử lý cao độ khi tua", selection: $prefs.pitchAlgorithm) {
                    ForEach(AudioPitchAlgorithmMode.allCases) { alg in
                        Text(alg.title).tag(alg)
                    }
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Âm lượng nội bộ")
                        Spacer()
                        Text("\(Int(prefs.comfortGain * 100))%")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $prefs.comfortGain, in: 0.35...1.0, step: 0.05)
                }
            } header: {
                Text("Spatial Audio & Âm thanh")
            }

            Section("Giao diện") {
                Picker("Hiệu ứng nền", selection: $prefs.glassStyle) {
                    ForEach(GlassUIStyle.allCases) { st in
                        Text(st.title).tag(st)
                    }
                }

                Toggle("Nền đen OLED", isOn: $prefs.oledBlackEnabled)

                Picker("Màu chủ đạo", selection: $prefs.accentPreset) {
                    ForEach(AccentPreset.allCases) { preset in
                        HStack {
                            Circle().fill(preset.color).frame(width: 10, height: 10)
                            Text(preset.label)
                        }.tag(preset)
                    }
                }

                Picker("Bố cục lưới phim", selection: $prefs.gridColumnsPhone) {
                    Text("2 cột").tag(2)
                    Text("3 cột").tag(3)
                }

                Toggle("Rung phản hồi", isOn: $prefs.hapticsEnabled)
            }

            Section("Trình phát & Picture in Picture") {
                Toggle("Tự mở Picture in Picture khi thoát ra màn hình chính", isOn: $prefs.autoPiP)
                Toggle("Tự xoay ngang khi bắt đầu xem", isOn: $prefs.autoRotateLandscape)
                Toggle("Tự cắt đoạn quảng cáo", isOn: $prefs.autoCutAds)
                Toggle("Tự chuyển tập tiếp theo", isOn: $prefs.autoNextEpisode)

                Picker("Đoạn mở đầu / kết thúc", selection: $prefs.introSkipBehavior) {
                    ForEach(IntroSkipBehavior.allCases) { m in
                        Text(m.title).tag(m)
                    }
                }

                Picker("Chạm đúp để tua", selection: $prefs.doubleTapSeekSeconds) {
                    Text("5 giây").tag(5)
                    Text("10 giây").tag(10)
                    Text("15 giây").tag(15)
                    Text("30 giây").tag(30)
                }

                Picker("Nhấn giữ để tăng tốc", selection: $prefs.longPressSpeed) {
                    Text("1.5x").tag(1.5)
                    Text("2.0x").tag(2.0)
                    Text("2.5x").tag(2.5)
                    Text("3.0x").tag(3.0)
                }

                Picker("Nguồn phát ưu tiên", selection: $prefs.preferredSource) {
                    ForEach(PreferredStreamSource.allCases) { src in
                        Text(src.title).tag(src)
                    }
                }

                Picker("Bộ đệm tải trước", selection: $prefs.forwardBufferSeconds) {
                    Text("15 giây").tag(15.0)
                    Text("45 giây").tag(45.0)
                    Text("90 giây").tag(90.0)
                    Text("120 giây").tag(120.0)
                }

                Picker("Trình phát mặc định", selection: $prefs.externalPlayer) {
                    ForEach(ExternalPlayerOption.allCases) { opt in
                        Text(opt.title).tag(opt)
                    }
                }
            }

            Section("Ứng dụng") {
                HStack {
                    Text("Phiên bản")
                    Spacer()
                    Text(updates.currentVersion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Text("Bản dựng")
                    Spacer()
                    Text(updates.buildFlavorLabel)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    Task { await updates.checkForUpdates(manual: true) }
                } label: {
                    HStack {
                        Text("Kiểm tra cập nhật")
                        Spacer()
                        if updates.isChecking {
                            ProgressView().scaleEffect(0.8)
                        }
                    }
                }

                if !updates.lastCheckNote.isEmpty {
                    Text(updates.lastCheckNote)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Kết nối") {
                TextField("Địa chỉ máy chủ", text: $prefs.baseURLString)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)

                Button("Phim đã ẩn (\(appState.blockedMovies.count))") {
                    showHiddenMovies = true
                }

                Button("Đặt lại mặc định", role: .destructive) {
                    prefs.resetToDefaults()
                    Haptics.notify(.warning)
                }
            }
        }
        .navigationTitle("Cài đặt")
        .adaptiveSoftScrollEdge()
        .sheet(isPresented: $showHiddenMovies) {
            NavigationView {
                List {
                    if appState.blockedMovies.isEmpty {
                        Text("Chưa có phim nào bị ẩn.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(appState.blockedMovies) { item in
                            HStack {
                                Text(item.name)
                                    .font(.subheadline)
                                Spacer()
                                Button("Hiện lại") {
                                    appState.unblockMovie(slug: item.slug)
                                }
                                .font(.caption.weight(.semibold))
                                .foregroundColor(prefs.accentPreset.color)
                            }
                        }
                    }
                }
                .navigationTitle("Phim đã ẩn")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Xong") { showHiddenMovies = false }
                    }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
