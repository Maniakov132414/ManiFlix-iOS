import SwiftUI

struct ThemeSettingsView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var appState = AppState.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isSyncingTheme = false

    var body: some View {
        Form {
            Section {
                taurusLivePreviewCard
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .listRowBackground(Color.clear)
            } header: {
                Text("Xem trước trực tiếp")
            }

            Section("Chế độ & Bộ giao diện") {
                Picker("Chế độ giao diện", selection: $prefs.themeMode) {
                    ForEach(ThemeMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Bộ giao diện gợi ý")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ThemePreset.presets) { preset in
                                let isSelected = prefs.activeThemePresetId == preset.id
                                Button {
                                    prefs.applyPreset(preset)
                                    Haptics.impact(.light)
                                } label: {
                                    HStack(spacing: 7) {
                                        ZStack {
                                            Circle()
                                                .fill(Color(hex: preset.bgHex))
                                                .frame(width: 18, height: 18)
                                                .overlay(
                                                    Circle()
                                                        .strokeBorder(ManiFlixTheme.cardStroke(colorScheme), lineWidth: 1)
                                                )
                                            Circle()
                                                .fill(Color(hex: preset.accentHex))
                                                .frame(width: 8, height: 8)
                                        }
                                        Text(preset.name)
                                            .font(.caption.weight(isSelected ? .semibold : .medium))
                                            .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(isSelected ? Color(hex: preset.accentHex).opacity(0.18) : ManiFlixTheme.cardFill(colorScheme))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .strokeBorder(isSelected ? Color(hex: preset.accentHex) : ManiFlixTheme.cardStroke(colorScheme), lineWidth: isSelected ? 1.2 : 0.6)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack(spacing: 12) {
                    Text("Màu chủ đạo")
                    Spacer()
                    ForEach(AccentPreset.allCases) { preset in
                        let isSelected = prefs.customAccentHex.caseInsensitiveCompare(preset.hexString) == .orderedSame
                        Button {
                            prefs.accentPreset = preset
                            Haptics.impact(.light)
                        } label: {
                            Circle()
                                .fill(preset.color)
                                .frame(width: 22, height: 22)
                                .overlay(
                                    Circle()
                                        .strokeBorder(ManiFlixTheme.primaryText(colorScheme), lineWidth: isSelected ? 2.2 : 0)
                                )
                                .scaleEffect(isSelected ? 1.1 : 1.0)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)

                if prefs.themeMode == .custom {
                    ColorPicker(
                        "Màu nhấn tuỳ chỉnh",
                        selection: Binding(
                            get: { Color(hex: prefs.customAccentHex) },
                            set: { prefs.customAccentHex = $0.toHexString() }
                        ),
                        supportsOpacity: false
                    )
                    ColorPicker(
                        "Màu nền tuỳ chỉnh",
                        selection: Binding(
                            get: { Color(hex: prefs.customBgHex) },
                            set: { prefs.customBgHex = $0.toHexString() }
                        ),
                        supportsOpacity: false
                    )
                    ColorPicker(
                        "Màu thẻ / bề mặt",
                        selection: Binding(
                            get: { Color(hex: prefs.customSurfaceHex) },
                            set: { prefs.customSurfaceHex = $0.toHexString() }
                        ),
                        supportsOpacity: false
                    )
                }
            }

            Section("Bố cục & Hiệu ứng") {
                Picker("Phong cách hiển thị", selection: $prefs.glassStyle) {
                    ForEach(GlassUIStyle.allCases) { st in
                        Text(st.title).tag(st)
                    }
                }

                Toggle("Ánh nền theo ảnh phim", isOn: $prefs.ambientArtworkEnabled)

                Picker("Số cột hiển thị", selection: $prefs.gridColumnsPhone) {
                    Text("2 cột").tag(2)
                    Text("3 cột").tag(3)
                }

                Toggle("Rung phản hồi", isOn: $prefs.hapticsEnabled)
            }

            if appState.isLoggedIn {
                Section("Tài khoản") {
                    Button {
                        Task {
                            isSyncingTheme = true
                            _ = await appState.syncThemeToServer()
                            isSyncingTheme = false
                        }
                    } label: {
                        HStack {
                            Label("Đồng bộ lên tài khoản", systemImage: "icloud.and.arrow.up")
                            Spacer()
                            if isSyncingTheme {
                                ProgressView().scaleEffect(0.8)
                            }
                        }
                    }
                }
            }
        }
        .adaptiveHiddenScrollBackground()
        .background(ManiFlixTheme.background(scheme: colorScheme).ignoresSafeArea())
        .navigationTitle("Giao diện & Chủ đề")
        .navigationBarTitleDisplayMode(.inline)
        .adaptiveSoftScrollEdge()
    }

    private var taurusLivePreviewCard: some View {
        let bg = ManiFlixTheme.background(scheme: colorScheme)
        let surface = ManiFlixTheme.surface(scheme: colorScheme)
        let primary = ManiFlixTheme.primaryText(colorScheme)
        let secondary = ManiFlixTheme.secondaryText(colorScheme)
        let stroke = ManiFlixTheme.cardStroke(colorScheme)
        let accent = prefs.currentAccentColor
        let isLegacyGlass = (prefs.glassStyle == .legacy)

        return ZStack(alignment: .bottom) {
            bg

            if prefs.ambientArtworkEnabled {
                RadialGradient(
                    colors: [accent.opacity(ManiFlixTheme.isLight(colorScheme) ? 0.22 : 0.36), .clear],
                    center: .top,
                    startRadius: 10,
                    endRadius: 210
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Trang chủ")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(primary)
                    Spacer()
                    Text(prefs.themeMode.title)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(accent)
                        .clipShape(Capsule())
                }

                // Mini Hero Banner
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(
                        colors: [accent.opacity(0.45), Color.black.opacity(0.86)],
                        startPoint: .topTrailing,
                        endPoint: .bottomLeading
                    )
                    .frame(height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(stroke, lineWidth: 0.6)
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("PHIM MỚI • FHD")
                            .font(.system(size: 8.5, weight: .bold))
                            .tracking(0.6)
                            .foregroundColor(.white.opacity(0.85))
                        Text("Dune: Hành Tinh Cát")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            HStack(spacing: 4) {
                                Image(systemName: "play.fill")
                                    .font(.system(size: 8, weight: .bold))
                                Text("Xem ngay")
                                    .font(.system(size: 9.5, weight: .bold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4.5)
                            .background(accent)
                            .clipShape(Capsule())

                            HStack(spacing: 3) {
                                Image(systemName: "plus")
                                    .font(.system(size: 8, weight: .semibold))
                                Text("Tủ phim")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Capsule())
                        }
                    }
                    .padding(10)
                }

                // 2 miniature 2:3 poster cards
                HStack(spacing: 10) {
                    ForEach(0..<2, id: \.self) { idx in
                        VStack(alignment: .leading, spacing: 4) {
                            ZStack(alignment: .bottomLeading) {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(surface)
                                    .overlay(
                                        LinearGradient(
                                            colors: [accent.opacity(idx == 0 ? 0.25 : 0.14), surface],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(stroke, lineWidth: 0.6)
                                    )
                                    .aspectRatio(2.0 / 3.0, contentMode: .fit)
                                    .frame(height: 82)

                                Text(idx == 0 ? "4K" : "Vietsub")
                                    .font(.system(size: 7.5, weight: .semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.black.opacity(0.7))
                                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                                    .padding(5)
                            }
                            RoundedRectangle(cornerRadius: 3)
                                .fill(primary.opacity(0.82))
                                .frame(width: idx == 0 ? 58 : 48, height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(secondary.opacity(0.55))
                                .frame(width: 36, height: 5)
                        }
                    }
                    Spacer()
                }
                .padding(.bottom, 34)
            }
            .padding(12)

            // Mini Tab Bar (Liquid Glass Capsule vs Legacy Solid)
            if isLegacyGlass {
                HStack {
                    miniTabItem(icon: "play.square.stack.fill", label: "Trang chủ", active: true, accent: accent, secondary: secondary)
                    Spacer()
                    miniTabItem(icon: "magnifyingglass", label: "Tìm", active: false, accent: accent, secondary: secondary)
                    Spacer()
                    miniTabItem(icon: "bookmark", label: "Tủ phim", active: false, accent: accent, secondary: secondary)
                    Spacer()
                    miniTabItem(icon: "gearshape", label: "Cài đặt", active: false, accent: accent, secondary: secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(surface.opacity(0.95))
                .overlay(Rectangle().frame(height: 0.5).foregroundColor(stroke), alignment: .top)
            } else {
                HStack(spacing: 8) {
                    HStack(spacing: 14) {
                        miniTabItem(icon: "play.square.stack.fill", label: "Trang chủ", active: true, accent: accent, secondary: secondary)
                        miniTabItem(icon: "bookmark", label: "Tủ phim", active: false, accent: accent, secondary: secondary)
                        miniTabItem(icon: "gearshape", label: "Cài đặt", active: false, accent: accent, secondary: secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 5)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(Capsule().strokeBorder(stroke, lineWidth: 0.6))

                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(primary)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(Circle().strokeBorder(stroke, lineWidth: 0.6))
                }
                .padding(.bottom, 8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(stroke, lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(ManiFlixTheme.isLight(colorScheme) ? 0.10 : 0.32), radius: 10, x: 0, y: 5)
    }

    private func miniTabItem(icon: String, label: String, active: Bool, accent: Color, secondary: Color) -> some View {
        VStack(spacing: 1.5) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
            Text(label)
                .font(.system(size: 7.5, weight: active ? .semibold : .regular))
        }
        .foregroundColor(active ? accent : secondary)
    }
}
