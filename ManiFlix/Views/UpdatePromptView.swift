import SwiftUI
import UIKit

struct UpdatePromptView: View {
    let isForced: Bool
    @ObservedObject private var updates = UpdateManager.shared
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.openURL) private var openURL
    @State private var copiedRepo = false

    private var repoURLString: String {
        updates.config?.altStoreSourceUrl ?? "https://phim.maniakov.bond/repo.json"
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(updates.config?.title ?? "ManiFlix \(updates.config?.latestVersion ?? "1.0.0")")
                            .font(.title3.weight(.bold))
                            .foregroundColor(.white)

                        Text(isForced ? "Bản cập nhật này là bắt buộc để tiếp tục sử dụng." : "Phiên bản hiện tại: \(updates.currentVersion)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)

                    if let notes = updates.config?.releaseNotes, !notes.isEmpty {
                        Text(notes)
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.82))
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .adaptiveGlassCard(cornerRadius: 12)
                    }

                    Button {
                        if let url = updates.recommendedVariantURL() {
                            openURL(url)
                        }
                    } label: {
                        Text("Tải bản cập nhật (.ipa)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                    }
                    .adaptiveGlassCapsule(interactive: true, tint: prefs.accentPreset.color)

                    if let variants = updates.config?.variants, !variants.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Các bản dựng khác")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)

                            ForEach(variants) { variant in
                                Button {
                                    if let url = URL(string: variant.downloadUrl) {
                                        openURL(url)
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(variant.name)
                                                .font(.caption.weight(.medium))
                                                .foregroundColor(.white)
                                            Text("iOS \(variant.minOS ?? "15.0")+ • \(variant.hasPlugins == false ? "No Plugins" : "Kèm Widget")")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "arrow.down")
                                            .font(.caption)
                                            .foregroundColor(Color(white: 0.7))
                                    }
                                    .padding(11)
                                }
                                .adaptiveGlassCard(cornerRadius: 10, interactive: true)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Link Repo (ESign / Feather / SideStore)")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.secondary)
                            Spacer()
                            Button(copiedRepo ? "Đã chép" : "Chép link") {
                                UIPasteboard.general.string = repoURLString
                                copiedRepo = true
                                Haptics.notify(.success)
                            }
                            .font(.caption.weight(.semibold))
                            .foregroundColor(prefs.accentPreset.color)
                        }
                        Text(repoURLString)
                            .font(.caption2.monospaced())
                            .foregroundColor(Color(white: 0.75))
                            .lineLimit(1)
                    }
                    .padding(12)
                    .adaptiveGlassCard(cornerRadius: 10)

                    HStack(spacing: 8) {
                        Button {
                            if let url = URL(string: "sidestore://source?url=\(repoURLString)") { openURL(url) }
                        } label: {
                            Text("SideStore")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                        }
                        .adaptiveGlassCapsule()

                        Button {
                            if let url = URL(string: "esign://addsource?url=\(repoURLString)") { openURL(url) }
                        } label: {
                            Text("ESign")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                        }
                        .adaptiveGlassCapsule()

                        Button {
                            if let url = URL(string: "feather://source/\(repoURLString)") { openURL(url) }
                        } label: {
                            Text("Feather")
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 36)
                        }
                        .adaptiveGlassCapsule()
                    }

                    if !isForced {
                        Button {
                            updates.snoozeSoftUpdateFor24Hours()
                        } label: {
                            Text("Nhắc lại sau 24 giờ")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                    }
                }
                .padding(20)
            }
            .background(ManiFlixTheme.background(oled: prefs.oledBlackEnabled).ignoresSafeArea())
            .navigationTitle(isForced ? "Cập nhật bắt buộc" : "Bản cập nhật mới")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled(isForced)
        .preferredColorScheme(.dark)
    }
}
