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
    @State private var isFranchiseExpanded = true
    @State private var isLoading = true
    @State private var errorMsg: String?

    private var heroArtworkURL: URL? {
        detail?.displayPosterURL ?? seedMovie?.displayPosterURL ?? detail?.displayThumbURL ?? seedMovie?.displayThumbURL
    }

    private var resumeEntry: HistoryEntry? {
        appState.history.first(where: { $0.slug == (detail?.slug ?? slug) })
    }

    var body: some View {
        ZStack(alignment: .top) {
            ManiFlixTheme.background(oled: prefs.oledBlackEnabled)
                .ignoresSafeArea()

            AmbientArtworkBackground(url: heroArtworkURL, oled: prefs.oledBlackEnabled, height: 420)

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

                        if franchiseSeasons.count > 1 {
                            franchiseSection
                        }

                        episodeSelectorSection(movie: movie)

                        if !movie.plainSynopsis.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Giới thiệu")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                                Text(movie.plainSynopsis)
                                    .font(.subheadline)
                                    .foregroundColor(Color(white: 0.76))
                                    .lineSpacing(3.5)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.bottom, 96)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .adaptiveSoftScrollEdge()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: slug) {
            await loadDetail()
        }
    }

    private var headerBanner: some View {
        VStack(spacing: 14) {
            CachedAsyncImage(url: heroArtworkURL)
                .frame(width: 158, height: 228)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.6)
                )
                .shadow(color: Color.black.opacity(0.55), radius: 20, x: 0, y: 12)
                .padding(.top, 10)

            VStack(spacing: 5) {
                Text(detail?.name ?? seedMovie?.name ?? "")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, 20)

                if let orig = detail?.origin_name ?? seedMovie?.origin_name, !orig.isEmpty {
                    Text(orig)
                        .font(.subheadline)
                        .foregroundColor(Color(white: 0.72))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 24)
                }

                let metaParts: [String] = [
                    (detail?.year?.value ?? seedMovie?.year?.value).flatMap { $0 > 0 ? String($0) : nil },
                    detail?.time ?? seedMovie?.time,
                    detail?.lang ?? seedMovie?.lang
                ].compactMap { val in
                    guard let v = val, !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
                    return v
                }

                if !metaParts.isEmpty {
                    Text(metaParts.joined(separator: " • "))
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color(white: 0.60))
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func actionButtonsRow(movie: MovieDetail) -> some View {
        let epCount = servers[safe: selectedServerIdx]?.server_data.count ?? 0
        let targetIdx: Int = {
            guard let resume = resumeEntry, let idx = resume.episodeIndex, idx >= 0, idx < epCount else { return 0 }
            return idx
        }()
        let playLabel: String = {
            if let resume = resumeEntry, let epTitle = resume.episodeName, !epTitle.isEmpty, targetIdx < epCount {
                return "Xem tiếp • \(epTitle)"
            }
            return "Phát"
        }()

        let itemForMenu = MovieItem(
            _id: movie._id,
            name: movie.name,
            slug: movie.slug,
            origin_name: movie.origin_name,
            poster_url: movie.poster_url,
            thumb_url: movie.thumb_url,
            year: movie.year,
            type: movie.type,
            quality: movie.quality,
            lang: movie.lang,
            episode_current: movie.episode_current,
            time: movie.time,
            category: movie.category,
            country: movie.country
        )

        return HStack(spacing: 10) {
            Button {
                appState.startPlayback(movie: movie, servers: servers, serverIndex: selectedServerIdx, episodeIndex: targetIdx)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(.subheadline)
                    Text(playLabel)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(prefs.accentPreset.color)
                )
            }
            .buttonStyle(.plain)
            .disabled(servers[safe: selectedServerIdx]?.server_data.isEmpty ?? true)

            Button {
                Task { await appState.toggleFavorite(movie: movie) }
            } label: {
                Image(systemName: appState.isFavorite(slug: movie.slug) ? "bookmark.fill" : "bookmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(appState.isFavorite(slug: movie.slug) ? prefs.accentPreset.color : .white)
                    .frame(width: 46, height: 46)
            }
            .adaptiveGlassCard(cornerRadius: 12, interactive: true)

            Menu {
                MovieContextMenuItems(movie: itemForMenu)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(width: 46, height: 46)
            }
            .adaptiveGlassCard(cornerRadius: 12, interactive: true)
        }
        .padding(.horizontal, 16)
    }

    private func metadataBadges(movie: MovieDetail) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if let q = movie.quality, !q.isEmpty { badgePill(q) }
                if let ep = movie.episode_current, !ep.isEmpty { badgePill(ep) }
                ForEach((movie.category ?? []).prefix(5)) { cat in
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
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .adaptiveGlassCapsule(interactive: false)
    }

    private var franchiseSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isFranchiseExpanded.toggle()
                }
                Haptics.impact(.light)
            } label: {
                HStack(spacing: 8) {
                    Text("Các phần phim (\(franchiseSeasons.count))")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)

                    Spacer()

                    Text(isFranchiseExpanded ? "Thu gọn" : "Mở rộng")
                        .font(.caption.weight(.medium))
                        .foregroundColor(Color(white: 0.65))

                    Image(systemName: isFranchiseExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(prefs.accentPreset.color)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isFranchiseExpanded {
                if #available(iOS 16.0, *) {
                    WrappingFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                        ForEach(franchiseSeasons) { season in
                            franchiseSeasonChip(season)
                        }
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(franchiseSeasons) { season in
                            franchiseSeasonChip(season)
                        }
                    }
                }
            }
        }
        .padding(14)
        .adaptiveGlassCard(cornerRadius: 14)
        .padding(.horizontal, 16)
    }

    private func franchiseSeasonChip(_ season: FranchiseSeason) -> some View {
        let isCurrent = season.slug == slug
        return NavigationLink(destination: MovieDetailView(slug: season.slug, seedMovie: nil)) {
            Text(season.displayFullTitle)
                .font(.caption.weight(isCurrent ? .semibold : .medium))
                .foregroundColor(.white)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isCurrent ? prefs.accentPreset.color.opacity(0.28) : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isCurrent ? prefs.accentPreset.color : Color.white.opacity(0.12), lineWidth: isCurrent ? 1.2 : 0.6)
                )
        }
        .buttonStyle(.plain)
    }

    private func episodeSelectorSection(movie: MovieDetail) -> some View {
        let watchedEpIdx = resumeEntry?.episodeIndex
        return VStack(alignment: .leading, spacing: 12) {
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
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 74), spacing: 8)], spacing: 8) {
                        ForEach(Array(activeSrv.server_data.enumerated()), id: \.offset) { epIdx, ep in
                            let isWatchedEp = watchedEpIdx == epIdx
                            Button {
                                appState.startPlayback(
                                    movie: movie,
                                    servers: servers,
                                    serverIndex: selectedServerIdx,
                                    episodeIndex: epIdx
                                )
                            } label: {
                                Text(ep.name)
                                    .font(.caption.weight(isWatchedEp ? .semibold : .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9.5)
                            }
                            .adaptiveGlassCard(
                                cornerRadius: 9,
                                interactive: true,
                                tint: isWatchedEp ? prefs.accentPreset.color : nil
                            )
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
}
