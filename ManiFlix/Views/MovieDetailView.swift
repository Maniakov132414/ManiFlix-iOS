import SwiftUI

struct MovieDetailView: View {
    let slug: String
    let seedMovie: MovieItem?

    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var appState = AppState.shared
    @Environment(\.colorScheme) private var colorScheme

    @State private var containerWidth: CGFloat = UIScreen.main.bounds.width
    @State private var detail: MovieDetail?
    @State private var servers: [EpisodeServer] = []
    @State private var franchiseMeta: FranchiseResponse?
    @State private var franchiseSeasons: [FranchiseSeason] = []
    @State private var relatedMovies: [MovieItem] = []
    @State private var selectedServerIdx = 0
    @State private var isFranchiseExpanded = true
    @State private var isLoading = true
    @State private var errorMsg: String?

    private var isTwoPane: Bool {
        containerWidth >= 640
    }

    private var panePadding: CGFloat {
        isTwoPane ? 0 : 16
    }

    private var heroArtworkURL: URL? {
        detail?.displayPosterURL ?? seedMovie?.displayPosterURL ?? detail?.displayThumbURL ?? seedMovie?.displayThumbURL
    }

    private var resumeEntry: HistoryEntry? {
        appState.history.first(where: { $0.slug == (detail?.slug ?? slug) })
    }

    var body: some View {
        ZStack(alignment: .top) {
            ManiFlixTheme.background(scheme: colorScheme)
                .ignoresSafeArea()

            AmbientArtworkBackground(url: heroArtworkURL, height: 420)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if isLoading {
                        headerBanner
                        ProgressView()
                            .tint(prefs.currentAccentColor)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    } else if let err = errorMsg {
                        headerBanner
                        Text(err)
                            .font(.subheadline)
                            .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                            .padding(.horizontal, 16)
                    } else if let movie = detail {
                        if isTwoPane {
                            HStack(alignment: .top, spacing: 28) {
                                VStack(alignment: .leading, spacing: 18) {
                                    headerBanner
                                    actionButtonsRow(movie: movie)
                                    metadataBadges(movie: movie)
                                    if !movie.plainSynopsis.isEmpty {
                                        synopsisSection(movie: movie)
                                    }
                                    creditsSection(movie: movie)
                                }
                                .frame(maxWidth: 360, alignment: .leading)

                                VStack(alignment: .leading, spacing: 18) {
                                    if franchiseSeasons.count > 1 {
                                        franchiseSection
                                    }
                                    episodeSelectorSection(movie: movie)
                                    if !relatedMovies.isEmpty {
                                        relatedMoviesRail
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                        } else {
                            headerBanner
                            actionButtonsRow(movie: movie)
                            metadataBadges(movie: movie)

                            if franchiseSeasons.count > 1 {
                                franchiseSection
                            }

                            episodeSelectorSection(movie: movie)

                            if !movie.plainSynopsis.isEmpty {
                                synopsisSection(movie: movie)
                            }

                            creditsSection(movie: movie)

                            if !relatedMovies.isEmpty {
                                relatedMoviesRail
                            }
                        }
                    } else {
                        headerBanner
                    }
                }
                .padding(.bottom, 96)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .readContainerWidth($containerWidth)
        .adaptiveSoftScrollEdge()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: slug) {
            await loadDetail()
        }
    }

    private func synopsisSection(movie: MovieDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Giới thiệu")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
            Text(movie.plainSynopsis)
                .font(.subheadline)
                .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                .lineSpacing(3.5)
        }
        .padding(.horizontal, panePadding)
        .padding(.top, 4)
    }

    private var headerTitleText: String {
        detail?.localizedPrimaryTitle(prefs.uiLanguage) ?? seedMovie?.localizedPrimaryTitle(prefs.uiLanguage) ?? ""
    }

    private var headerOriginText: String? {
        detail?.localizedSecondaryTitle(prefs.uiLanguage) ?? seedMovie?.localizedSecondaryTitle(prefs.uiLanguage)
    }

    private var headerMetaText: String? {
        let rawYear = detail?.year?.value ?? seedMovie?.year?.value
        let yearStr: String? = (rawYear ?? 0) > 0 ? String(rawYear!) : nil
        let timeStr = detail?.time ?? seedMovie?.time
        let langStr = detail?.lang ?? seedMovie?.lang
        let parts = [yearStr, timeStr, langStr].compactMap { val -> String? in
            guard let v = val, !v.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            return v
        }
        return parts.isEmpty ? nil : parts.joined(separator: " • ")
    }

    private var headerBanner: some View {
        VStack(spacing: 14) {
            CachedAsyncImage(url: heroArtworkURL, maxPixelSize: 480)
                .frame(width: 158, height: 228)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(ManiFlixTheme.cardStroke(colorScheme), lineWidth: 0.6)
                )
                .padding(.top, 10)

            VStack(spacing: 5) {
                Text(headerTitleText)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .padding(.horizontal, isTwoPane ? 8 : 20)

                if let orig = headerOriginText {
                    Text(orig)
                        .font(.subheadline)
                        .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, isTwoPane ? 10 : 24)
                }

                if let meta = headerMetaText {
                    Text(meta)
                        .font(.caption.weight(.medium))
                        .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
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
                        .fill(prefs.currentAccentColor)
                )
            }
            .buttonStyle(.plain)
            .disabled(servers[safe: selectedServerIdx]?.server_data.isEmpty ?? true)

            Button {
                Task { await appState.toggleFavorite(movie: movie) }
            } label: {
                Image(systemName: appState.isFavorite(slug: movie.slug) ? "bookmark.fill" : "bookmark")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(appState.isFavorite(slug: movie.slug) ? prefs.currentAccentColor : ManiFlixTheme.primaryText(colorScheme))
                    .frame(width: 46, height: 46)
            }
            .adaptiveGlassCard(cornerRadius: 12, interactive: true)

            Menu {
                MovieContextMenuItems(movie: itemForMenu)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                    .frame(width: 46, height: 46)
            }
            .adaptiveGlassCard(cornerRadius: 12, interactive: true)
        }
        .padding(.horizontal, panePadding)
    }

    private func metadataBadges(movie: MovieDetail) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                if let q = movie.quality, !q.isEmpty { badgePill(q) }
                if let ep = movie.episode_current, !ep.isEmpty { badgePill(ep) }
                ForEach((movie.country ?? []).prefix(3)) { c in
                    if let name = c.name, !name.isEmpty { badgePill(name) }
                }
                ForEach((movie.category ?? []).prefix(5)) { cat in
                    if let name = cat.name, !name.isEmpty { badgePill(name) }
                }
            }
            .padding(.horizontal, panePadding)
        }
    }

    private func badgePill(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundColor(ManiFlixTheme.primaryText(colorScheme).opacity(0.88))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .adaptiveGlassCapsule(interactive: false)
    }

    private var franchiseSection: some View {
        let headerTitle = franchiseMeta?.localizedHeader(uiLang: prefs.uiLanguage, count: franchiseSeasons.count)
            ?? (prefs.uiLanguage == "en" ? "Franchise (\(franchiseSeasons.count) parts)" : "Các phần phim (\(franchiseSeasons.count))")
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.22)) {
                    isFranchiseExpanded.toggle()
                }
                Haptics.impact(.light)
            } label: {
                HStack(spacing: 8) {
                    Text(headerTitle)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ManiFlixTheme.primaryText(colorScheme))

                    Spacer()

                    Text(isFranchiseExpanded ? prefs.tr("Thu gọn", "Collapse") : prefs.tr("Mở rộng", "Expand"))
                        .font(.caption.weight(.medium))
                        .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))

                    Image(systemName: isFranchiseExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(prefs.currentAccentColor)
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
        .padding(.horizontal, panePadding)
    }

    private func franchiseSeasonChip(_ season: FranchiseSeason) -> some View {
        let isCurrent = season.slug == slug
        return NavigationLink(destination: MovieDetailView(slug: season.slug, seedMovie: nil)) {
            Text(season.localizedLabel(uiLang: prefs.uiLanguage, meta: franchiseMeta, allSeasons: franchiseSeasons))
                .font(.caption.weight(isCurrent ? .semibold : .medium))
                .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isCurrent ? prefs.currentAccentColor.opacity(0.24) : ManiFlixTheme.cardFill(colorScheme))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(isCurrent ? prefs.currentAccentColor : ManiFlixTheme.cardStroke(colorScheme), lineWidth: isCurrent ? 1.2 : 0.6)
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
                            let selected = selectedServerIdx == idx
                            Button {
                                selectedServerIdx = idx
                                Haptics.impact(.light)
                            } label: {
                                Text(srv.server_name)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(selected ? .white : ManiFlixTheme.primaryText(colorScheme))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6.5)
                            }
                            .adaptiveGlassCapsule(
                                interactive: true,
                                tint: selected ? prefs.currentAccentColor : nil
                            )
                        }
                    }
                    .padding(.horizontal, panePadding)
                }

                if let activeSrv = servers[safe: selectedServerIdx] {
                    Text("Danh sách tập (\(activeSrv.server_data.count))")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                        .padding(.horizontal, panePadding)

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
                                    .foregroundColor(isWatchedEp ? prefs.currentAccentColor : ManiFlixTheme.primaryText(colorScheme))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9.5)
                            }
                            .adaptiveGlassCard(
                                cornerRadius: 9,
                                interactive: true,
                                tint: isWatchedEp ? prefs.currentAccentColor : nil
                            )
                        }
                    }
                    .padding(.horizontal, panePadding)
                }
            }
        }
    }

    @ViewBuilder
    private func creditsSection(movie: MovieDetail) -> some View {
        let directors = (movie.director ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let actors = (movie.actor ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let countries = (movie.country ?? [])
            .compactMap { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if !directors.isEmpty || !actors.isEmpty || !countries.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Thông tin thêm")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(ManiFlixTheme.primaryText(colorScheme))

                if !countries.isEmpty {
                    creditRow(title: "Quốc gia", value: countries.joined(separator: ", "))
                }
                if !directors.isEmpty {
                    creditRow(title: "Đạo diễn", value: directors.joined(separator: ", "))
                }
                if !actors.isEmpty {
                    creditRow(title: "Diễn viên", value: actors.prefix(12).joined(separator: ", "))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .adaptiveGlassCard(cornerRadius: 14)
            .padding(.horizontal, panePadding)
        }
    }

    private func creditRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
            Text(value)
                .font(.caption)
                .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var relatedMoviesRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Có thể bạn cũng thích")
                .font(.system(size: 17, weight: .bold))
                .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                .padding(.horizontal, panePadding)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 11) {
                    ForEach(relatedMovies) { item in
                        NavigationLink(destination: MovieDetailView(slug: item.slug, seedMovie: item)) {
                            MoviePosterCard(movie: item)
                                .frame(width: 118)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, panePadding)
            }
        }
        .padding(.top, 4)
    }

    private func loadDetail() async {
        isLoading = true
        errorMsg = nil
        relatedMovies = []
        do {
            let res = try await ManiFlixAPI.shared.fetchMovieDetail(slug: slug)
            self.detail = res.movie
            self.servers = res.episodes ?? []
            if let fr = try? await ManiFlixAPI.shared.fetchFranchise(slug: slug) {
                self.franchiseMeta = fr
                self.franchiseSeasons = TitleLocalizer.sortFranchiseSeasons(fr.seasons ?? [], baseTitle: fr.baseTitle)
            }
            await loadRelatedMovies(for: res.movie)
        } catch {
            self.errorMsg = error.localizedDescription
        }
        isLoading = false
    }

    private func loadRelatedMovies(for movie: MovieDetail?) async {
        guard let movie = movie else { return }
        var candidates: [MovieItem] = []

        if let genreSlug = movie.category?.first(where: { !($0.slug ?? "").isEmpty })?.slug,
           let res = try? await ManiFlixAPI.shared.fetchGenre(slug: genreSlug, page: 1) {
            candidates = res.items ?? []
        }

        if candidates.isEmpty {
            let catType: String
            switch movie.type {
            case "hoathinh": catType = "hoat-hinh"
            case "series": catType = "phim-bo"
            case "tvshows": catType = "tv-shows"
            default: catType = "phim-le"
            }
            if let res = try? await ManiFlixAPI.shared.fetchCategory(type: catType, page: 1) {
                candidates = res.items ?? []
            }
        }

        if candidates.isEmpty, let firstWord = movie.name.split(separator: " ").first {
            if let res = try? await ManiFlixAPI.shared.searchMovies(query: String(firstWord), page: 1) {
                candidates = res.items ?? []
            }
        }

        self.relatedMovies = Array(
            candidates
                .filter { $0.slug != slug && !appState.isBlocked(slug: $0.slug) }
                .prefix(12)
        )
    }
}
