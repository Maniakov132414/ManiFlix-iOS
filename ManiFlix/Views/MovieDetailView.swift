import SwiftUI

struct MovieDetailView: View {
    let slug: String
    let seedMovie: MovieItem?

    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var appState = AppState.shared

    @State private var detail: MovieDetail?
    @State private var servers: [EpisodeServer] = []
    @State private var franchiseSeasons: [FranchiseSeason] = []
    @State private var selectedServerIdx = 0
    @State private var isLoading = true
    @State private var errorMsg: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerBanner

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                } else if let err = errorMsg {
                    Text(err)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 16)
                } else if let movie = detail {
                    actionButtonsRow(movie: movie)
                    metadataBadges(movie: movie)

                    if !franchiseSeasons.isEmpty {
                        franchiseSection
                    }

                    episodeSelectorSection(movie: movie)

                    if !movie.plainSynopsis.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nội dung")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                            Text(movie.plainSynopsis)
                                .font(.subheadline)
                                .foregroundColor(Color(white: 0.72))
                                .lineSpacing(3.5)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(.bottom, 32)
        }
        .background(ManiFlixTheme.background(oled: prefs.oledBlackEnabled).ignoresSafeArea())
        .adaptiveSoftScrollEdge()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: slug) {
            await loadDetail()
        }
    }

    private var headerBanner: some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: detail?.displayThumbURL ?? detail?.displayPosterURL ?? seedMovie?.displayThumbURL ?? seedMovie?.displayPosterURL)
                .frame(height: 264)
                .frame(maxWidth: .infinity)
                .clipped()

            LinearGradient(
                colors: [.clear, ManiFlixTheme.background(oled: prefs.oledBlackEnabled).opacity(0.6), ManiFlixTheme.background(oled: prefs.oledBlackEnabled)],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(alignment: .bottom, spacing: 14) {
                CachedAsyncImage(url: detail?.displayPosterURL ?? seedMovie?.displayPosterURL)
                    .frame(width: 92, height: 134)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.7)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(detail?.name ?? seedMovie?.name ?? "")
                        .font(.title3.weight(.bold))
                        .foregroundColor(.white)
                        .lineLimit(2)

                    if let orig = detail?.origin_name ?? seedMovie?.origin_name, !orig.isEmpty {
                        Text(orig)
                            .font(.caption)
                            .foregroundColor(Color(white: 0.65))
                            .lineLimit(1)
                    }

                    if let year = detail?.year?.value ?? seedMovie?.year?.value, year > 0 {
                        Text("\(year) • \(detail?.time ?? "HD")")
                            .font(.caption2)
                            .foregroundColor(Color(white: 0.55))
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
    }

    private func actionButtonsRow(movie: MovieDetail) -> some View {
        HStack(spacing: 10) {
            Button {
                appState.startPlayback(movie: movie, servers: servers, serverIndex: selectedServerIdx, episodeIndex: 0)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(.subheadline)
                    Text("Phát")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
            }
            .adaptiveGlassCapsule(interactive: true, tint: prefs.accentPreset.color)
            .disabled(servers[safe: selectedServerIdx]?.server_data.isEmpty ?? true)

            Button {
                Task { await appState.toggleFavorite(movie: movie) }
            } label: {
                Image(systemName: appState.isFavorite(slug: movie.slug) ? "bookmark.fill" : "bookmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(appState.isFavorite(slug: movie.slug) ? prefs.accentPreset.color : .white)
                    .frame(width: 44, height: 44)
            }
            .adaptiveGlassCapsule(interactive: true)

            Button {
                shareMovie(movie)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
            }
            .adaptiveGlassCapsule(interactive: true)
        }
        .padding(.horizontal, 16)
    }

    private func metadataBadges(movie: MovieDetail) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if let q = movie.quality, !q.isEmpty { badgePill(q) }
                if let l = movie.lang, !l.isEmpty { badgePill(l) }
                if let ep = movie.episode_current, !ep.isEmpty { badgePill(ep) }
                ForEach((movie.category ?? []).prefix(4)) { cat in
                    if let name = cat.name { badgePill(name) }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func badgePill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundColor(Color(white: 0.85))
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .adaptiveGlassCapsule(interactive: false)
    }

    private var franchiseSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Các phần liên quan")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(franchiseSeasons) { season in
                        NavigationLink(destination: MovieDetailView(slug: season.slug, seedMovie: nil)) {
                            Text(season.name ?? season.fullTitle ?? season.slug)
                                .font(.caption.weight(.medium))
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .adaptiveGlassCard(
                                    cornerRadius: 10,
                                    interactive: true,
                                    tint: season.slug == slug ? prefs.accentPreset.color : nil
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private func episodeSelectorSection(movie: MovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !servers.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(servers.enumerated()), id: \.offset) { idx, srv in
                            Button {
                                selectedServerIdx = idx
                                Haptics.impact(.light)
                            } label: {
                                Text(srv.server_name)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6.5)
                            }
                            .adaptiveGlassCapsule(
                                interactive: true,
                                tint: selectedServerIdx == idx ? prefs.accentPreset.color : nil
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if let activeSrv = servers[safe: selectedServerIdx] {
                    Text("Danh sách tập (\(activeSrv.server_data.count))")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
                        ForEach(Array(activeSrv.server_data.enumerated()), id: \.offset) { epIdx, ep in
                            Button {
                                appState.startPlayback(
                                    movie: movie,
                                    servers: servers,
                                    serverIndex: selectedServerIdx,
                                    episodeIndex: epIdx
                                )
                            } label: {
                                Text(ep.name)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9.5)
                            }
                            .adaptiveGlassCard(cornerRadius: 9, interactive: true)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func loadDetail() async {
        isLoading = true
        errorMsg = nil
        do {
            let res = try await ManiFlixAPI.shared.fetchMovieDetail(slug: slug)
            self.detail = res.movie
            self.servers = res.episodes ?? []
            if let fr = try? await ManiFlixAPI.shared.fetchFranchise(slug: slug) {
                self.franchiseSeasons = fr.seasons ?? []
            }
        } catch {
            self.errorMsg = error.localizedDescription
        }
        isLoading = false
    }

    private func shareMovie(_ movie: MovieDetail) {
        let shareURL = URL(string: "\(prefs.normalizedBaseURL)/watch/\(movie.slug)") ?? URL(string: prefs.normalizedBaseURL)!
        let vc = UIActivityViewController(activityItems: [movie.name, shareURL], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(vc, animated: true)
        }
    }
}
