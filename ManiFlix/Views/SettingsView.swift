import SwiftUI

struct SettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var spatial = AudioSpatialEngine.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var updates = UpdateManager.shared

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

            Section("Giao diện") {
                HStack(spacing: 12) {
                    Text("Màu chủ đạo")
                    Spacer()
                    ForEach(AccentPreset.allCases) { preset in
                        Button {
                            prefs.accentPreset = preset
                            Haptics.impact(.light)
                        } label: {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .strokeBorder(Color.white, lineWidth: prefs.accentPreset == preset ? 2.2 : 0)
                                )
                                .scaleEffect(prefs.accentPreset == preset ? 1.1 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)

                Picker("Phong cách hiển thị", selection: $prefs.glassStyle) {
                    ForEach(GlassUIStyle.allCases) { st in
                        Text(st.title).tag(st)
                    }
                }

                Toggle("Ánh nền theo ảnh phim", isOn: $prefs.ambientArtworkEnabled)
                Toggle("Nền đen thuần (OLED)", isOn: $prefs.oledBlackEnabled)

                Picker("Số cột hiển thị", selection: $prefs.gridColumnsPhone) {
                    Text("2 cột").tag(2)
                    Text("3 cột").tag(3)
                }

                Toggle("Rung phản hồi", isOn: $prefs.hapticsEnabled)
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
                Text("Âm thanh")
            }

            Section("Trình phát") {
                Toggle("Tự mở Picture in Picture", isOn: $prefs.autoPiP)
                Toggle("Tự xoay ngang khi xem", isOn: $prefs.autoRotateLandscape)
                Toggle("Tự cắt đoạn quảng cáo", isOn: $prefs.autoCutAds)
                Toggle("Tự chuyển tập tiếp theo", isOn: $prefs.autoNextEpisode)

                Picker("Mở đầu & kết thúc", selection: $prefs.introSkipBehavior) {
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
                    Text(updates.displayVersion)
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

                Button("Đặt lại mặc định", role: .destructive) {
                    prefs.resetToDefaults()
                    Haptics.notify(.warning)
                }
            }
        }
        .adaptiveHiddenScrollBackground()
        .background(ManiFlixTheme.background(oled: prefs.oledBlackEnabled).ignoresSafeArea())
        .navigationTitle("Cài đặt")
        .adaptiveSoftScrollEdge()
    }
}
