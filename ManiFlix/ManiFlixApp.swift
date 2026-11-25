import SwiftUI
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationController.allowedMask
    }
}

@main
struct ManiFlixApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var prefs = AppPreferences.shared
    @StateObject private var updates = UpdateManager.shared

    var body: some Scene {
        WindowGroup {
            RootTabScaffold()
                .preferredColorScheme(.dark)
                .tint(prefs.accentPreset.color)
                .task {
                    await appState.bootstrapSession()
                    await updates.checkForUpdates(manual: false)
                }
                .onOpenURL { url in
                    handleIncomingURL(url)
                }
                .fullScreenCover(isPresented: $appState.isPlayerPresented, onDismiss: {
                    OrientationController.forcePortrait()
                    appState.dismissPlayerKeepPiPIfNeeded()
                }) {
                    if let engine = appState.activeEngine {
                        ManiFlixPlayerView(engine: engine)
                    }
                }
                .sheet(isPresented: $appState.showAuthSheet) {
                    AuthSheetView()
                }
                .sheet(isPresented: $updates.showSoftPrompt) {
                    UpdatePromptView(isForced: false)
                }
                .fullScreenCover(isPresented: $updates.showForceBlocker) {
                    UpdatePromptView(isForced: true)
                }
        }
    }

    private func handleIncomingURL(_ url: URL) {
        if url.scheme == "maniflix" && url.host == "movie" {
            let slug = url.lastPathComponent
            if !slug.isEmpty && slug != "movie" {
                appState.deepLinkSlug = slug
            }
        }
    }
}

struct RootTabScaffold: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        ZStack(alignment: .bottom) {
            // Keeps AVPlayerLayer anchored in window when PiP is floating while browsing in-app
            if let engine = appState.activeEngine, !appState.isPlayerPresented {
                SharedPlayerLayerHost(engine: engine)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
            }

            Group {
                #if compiler(>=6.2)
                if #available(iOS 26.0, *), prefs.glassStyle.shouldUseLiquidGlass {
                    TabView {
                        Tab("Trang chủ", systemImage: "play.square.stack") {
                            navWrapper { DiscoverView() }
                        }
                        Tab("Tủ phim", systemImage: "bookmark") {
                            navWrapper { LibraryView() }
                        }
                        Tab("Cài đặt", systemImage: "gearshape") {
                            navWrapper { SettingsView() }
                        }
                        Tab("Tìm kiếm", systemImage: "magnifyingglass", role: .search) {
                            navWrapper { CatalogSearchView() }
                        }
                    }
                    .tabBarMinimizeBehavior(.onScrollDown)
                } else {
                    legacyTabScaffold
                }
                #else
                legacyTabScaffold
                #endif
            }

            if let engine = appState.activeEngine, !appState.isPlayerPresented {
                miniPiPBar(engine: engine)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 58)
            }

            if let banner = appState.globalBannerMessage {
                VStack {
                    Text(banner)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .adaptiveGlassCapsule(interactive: false)
                        .padding(.top, 10)
                    Spacer()
                }
                .allowsHitTesting(false)
            }
        }
        .sheet(isPresented: Binding(
            get: { appState.deepLinkSlug != nil },
            set: { if !$0 { appState.deepLinkSlug = nil } }
        )) {
            if let slug = appState.deepLinkSlug {
                navWrapper {
                    MovieDetailView(slug: slug, seedMovie: nil)
                }
            }
        }
    }

    private func miniPiPBar(engine: PlayerEngine) -> some View {
        HStack(spacing: 11) {
            Button {
                appState.isPlayerPresented = true
            } label: {
                HStack(spacing: 11) {
                    CachedAsyncImage(url: engine.movie.displayPosterURL)
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: Color.black.opacity(0.35), radius: 4, x: 0, y: 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(engine.movie.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(engine.isPiPActive ? "Đang phát thu nhỏ" : (engine.currentEpisode?.name ?? "Đang phát"))
                            .font(.caption2)
                            .foregroundColor(Color(white: 0.65))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                engine.togglePlayPause()
            } label: {
                Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                    .font(.body.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
            }

            Button {
                appState.stopPlaybackCompletely()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Color(white: 0.72))
                    .frame(width: 28, height: 34)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .adaptiveGlassCard(cornerRadius: 16, interactive: true)
    }

    private var legacyTabScaffold: some View {
        TabView {
            navWrapper { DiscoverView() }
                .tabItem { Label("Trang chủ", systemImage: "play.square.stack") }

            navWrapper { CatalogSearchView() }
                .tabItem { Label("Tìm kiếm", systemImage: "magnifyingglass") }

            navWrapper { LibraryView() }
                .tabItem { Label("Tủ phim", systemImage: "bookmark") }

            navWrapper { SettingsView() }
                .tabItem { Label("Cài đặt", systemImage: "gearshape") }
        }
    }

    @ViewBuilder
    private func navWrapper<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 16.0, *) {
            NavigationStack {
                content()
            }
        } else {
            NavigationView {
                content()
            }
            .navigationViewStyle(.stack)
        }
    }
}
