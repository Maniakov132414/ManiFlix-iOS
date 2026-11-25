import SwiftUI

private enum DiscoverCategoryFilter: String, CaseIterable, Identifiable {
    case all = "Tất cả"
    case series = "Phim bộ"
    case single = "Phim lẻ"
    case anime = "Hoạt hình"
    case tvShows = "TV Shows"
    case action = "Hành động"
    case costume = "Cổ trang"
    case romance = "Tình cảm"
    case horror = "Kinh dị"
    case sciFi = "Viễn tưởng"

    var id: String { rawValue }

    enum Endpoint {
        case latest
        case category(String)
        case genre(String)
    }

    var endpoint: Endpoint {
        switch self {
        case .all: return .latest
        case .series: return .category("phim-bo")
        case .single: return .category("phim-le")
        case .anime: return .category("hoat-hinh")
        case .tvShows: return .category("tv-shows")
        case .action: return .genre("hanh-dong")
        case .costume: return .genre("co-trang")
        case .romance: return .genre("tinh-cam")
        case .horror: return .genre("kinh-di")
        case .sciFi: return .genre("vien-tuong")
        }
    }
}

struct MoviePosterCard: View {
    let movie: MovieItem
    @ObservedObject private var prefs = AppPreferences.shared
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: movie.displayPosterURL)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(2.0 / 3.0, contentMode: .fill)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(ManiFlixTheme.cardStroke(colorScheme), lineWidth: 0.5)
                    )

                if let badge = movie.quality ?? movie.episode_current, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.black.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        .padding(6)
                }
            }

            HStack(alignment: .center, spacing: 4) {
                Text(movie.name)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                    .lineLimit(1)

                Spacer(minLength: 2)

                Menu {
                    MovieContextMenuItems(movie: movie)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
            }

            if let year = movie.year?.value, year > 0 {
                Text("\(String(year)) • \(movie.lang ?? "Vietsub")")
                    .font(.system(size: 11))
                    .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                    .lineLimit(1)
            }
        }
        .movieCardContextMenu(movie)
    }
}

struct DiscoverView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var appState = AppState.shared
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var containerWidth: CGFloat = UIScreen.main.bounds.width
    @State private var heroMovies: [MovieItem] = []
    @State private var seriesMovies: [MovieItem] = []
    @State private var singleMovies: [MovieItem] = []
    @State private var animeMovies: [MovieItem] = []
    @State private var filteredMovies: [MovieItem] = []
    @State private var selectedCategory: DiscoverCategoryFilter = .all
    @State private var currentPage: Int = 1
    @State private var hasMorePages: Bool = true
    @State private var isLoadingFilter: Bool = false
    @State private var isLoadingMore: Bool = false
    @State private var heroSelection: Int = 0
    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var showAccountSheet = false

    private var visibleHero: [MovieItem] {
        heroMovies.filter { !appState.isBlocked(slug: $0.slug) }
    }
    private var visibleFiltered: [MovieItem] {
        filteredMovies.filter { !appState.isBlocked(slug: $0.slug) }
    }
    private var visibleSeries: [MovieItem] {
        (seriesMovies.isEmpty ? Array(heroMovies.prefix(12)) : seriesMovies).filter { !appState.isBlocked(slug: $0.slug) }
    }
    private var visibleSingle: [MovieItem] {
        (singleMovies.isEmpty ? Array(heroMovies.dropFirst(4).prefix(12)) : singleMovies).filter { !appState.isBlocked(slug: $0.slug) }
    }
    private var visibleAnime: [MovieItem] {
        animeMovies.filter { !appState.isBlocked(slug: $0.slug) }
    }

    private var currentAmbientURL: URL? {
        let featured = Array(visibleHero.prefix(5))
        return featured[safe: heroSelection]?.displayPosterURL ?? featured.first?.displayPosterURL
    }

    private var heroCardHeight: CGFloat {
        horizontalSizeClass == .regular ? 346 : 294
    }

    private var heroTabHeight: CGFloat {
        horizontalSizeClass == .regular ? 348 : 296
    }

    private var railCardWidth: CGFloat {
        horizontalSizeClass == .regular ? 136 : 118
    }

    var body: some View {
        ZStack(alignment: .top) {
            ManiFlixTheme.background(scheme: colorScheme)
                .ignoresSafeArea()

            AmbientArtworkBackground(url: currentAmbientURL, height: 390)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let err = errorMsg, heroMovies.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.slash")
                                .font(.title2)
                                .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                            Text(err)
                                .font(.subheadline)
                                .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                                .multilineTextAlignment(.center)
                            Button("Thử lại") {
                                Task { await loadAll() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(prefs.currentAccentColor)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                    } else {
                        categoryChipsBar

                        if selectedCategory == .all {
                            if !visibleHero.isEmpty {
                                let featured = Array(visibleHero.prefix(5))
                                VStack(spacing: 10) {
                                    TabView(selection: $heroSelection) {
                                        ForEach(Array(featured.enumerated()), id: \.element.id) { idx, movie in
                                            heroCard(for: movie)
                                                .tag(idx)
                                        }
                                    }
                                    .frame(height: heroTabHeight)
                                    .tabViewStyle(.page(indexDisplayMode: .never))

                                    if featured.count > 1 {
                                        HStack(spacing: 6) {
                                            ForEach(0..<featured.count, id: \.self) { idx in
                                                Button {
                                                    withAnimation(.easeInOut(duration: 0.22)) {
                                                        heroSelection = idx
                                                    }
                                                } label: {
                                                    Capsule()
                                                        .fill(idx == heroSelection ? prefs.currentAccentColor : ManiFlixTheme.secondaryText(colorScheme).opacity(0.36))
                                                        .frame(width: idx == heroSelection ? 18 : 6, height: 6)
                                                        .animation(.easeInOut(duration: 0.2), value: heroSelection)
                                                }
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                    }
                                }
                            } else if isLoading {
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(ManiFlixTheme.cardFill(colorScheme))
                                    .frame(height: heroCardHeight)
                                    .padding(.horizontal, 16)
                            }

                            if !appState.history.isEmpty {
                                continueWatchingRail
                            }

                            horizontalRail(title: "Phim bộ mới", items: visibleSeries)
                            horizontalRail(title: "Phim lẻ tuyển chọn", items: visibleSingle)
                            horizontalRail(title: "Hoạt hình & Anime", items: visibleAnime)

                            gridSection(title: "Mới cập nhật", items: visibleHero)
                        } else {
                            if isLoadingFilter && visibleFiltered.isEmpty {
                                ProgressView()
                                    .tint(prefs.currentAccentColor)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 60)
                            } else {
                                gridSection(title: selectedCategory.rawValue, items: visibleFiltered)
                            }
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 92)
            }
        }
        .readContainerWidth($containerWidth)
        .adaptiveSoftScrollEdge()
        .navigationTitle("Trang chủ")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAccountSheet = true
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: appState.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.system(size: 19))
                        .foregroundColor(appState.isLoggedIn ? prefs.currentAccentColor : ManiFlixTheme.primaryText(colorScheme))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showAccountSheet) {
            AuthSheetView()
        }
        .refreshable {
            if selectedCategory == .all {
                await loadAll()
            } else {
                await loadCategoryFeed(for: selectedCategory, reset: true)
            }
        }
        .task {
            if heroMovies.isEmpty {
                await loadAll()
            }
        }
    }

    private var categoryChipsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DiscoverCategoryFilter.allCases) { cat in
                    let isSelected = selectedCategory == cat
                    Button {
                        guard selectedCategory != cat else { return }
                        selectedCategory = cat
                        Haptics.impact(.light)
                        Task {
                            if cat == .all {
                                currentPage = max(1, (heroMovies.count + 23) / 24)
                                hasMorePages = true
                            } else {
                                await loadCategoryFeed(for: cat, reset: true)
                            }
                        }
                    } label: {
                        Text(cat.rawValue)
                            .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                            .foregroundColor(isSelected ? .white : ManiFlixTheme.primaryText(colorScheme))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                    }
                    .adaptiveGlassCapsule(
                        interactive: true,
                        tint: isSelected ? prefs.currentAccentColor : nil
                    )
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func heroCard(for movie: MovieItem) -> some View {
        let isSaved = appState.isFavorite(slug: movie.slug)
        let yearText = (movie.year?.value ?? 0) > 0 ? String(movie.year!.value) : "2026"

        return ZStack(alignment: .bottomLeading) {
            NavigationLink(destination: MovieDetailView(slug: movie.slug, seedMovie: movie)) {
                ZStack(alignment: .bottomLeading) {
                    CachedAsyncImage(url: movie.displayThumbURL ?? movie.displayPosterURL, maxPixelSize: 960)
                        .frame(maxWidth: .infinity)
                        .frame(height: heroCardHeight)
                        .clipped()

                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0.12),
                            .init(color: Color.black.opacity(0.45), location: 0.52),
                            .init(color: Color.black.opacity(0.94), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("PHIM MỚI • \(yearText)")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundColor(.white.opacity(0.85))

                HStack(spacing: 6) {
                    if let q = movie.quality, !q.isEmpty {
                        Text(q)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(prefs.currentAccentColor.opacity(0.9))
                            .cornerRadius(4)
                    }
                    if let lang = movie.lang, !lang.isEmpty {
                        Text(lang)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(white: 0.88))
                    }
                    if let ep = movie.episode_current, !ep.isEmpty {
                        Text("• \(ep)")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.72))
                    }
                }

                Text(movie.name)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(2)

                if let orig = movie.origin_name, !orig.isEmpty {
                    Text(orig)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.72))
                        .lineLimit(1)
                }

                HStack(spacing: 10) {
                    Button {
                        Haptics.impact(.medium)
                        Task { await appState.quickWatch(slug: movie.slug) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill")
                                .font(.caption.weight(.bold))
                            Text("Xem ngay")
                                .font(.caption.weight(.bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(prefs.currentAccentColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.impact(.light)
                        Task { await appState.toggleFavoriteItem(movie) }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: isSaved ? "checkmark" : "plus")
                                .font(.caption.weight(.semibold))
                            Text(isSaved ? "Đã lưu" : "Tủ phim")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .strokeBorder(Color.white.opacity(0.24), lineWidth: 0.6)
                        )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(16)
            .allowsHitTesting(true)
        }
        .frame(height: heroCardHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(ManiFlixTheme.cardStroke(colorScheme), lineWidth: 0.6)
        )
        .padding(.horizontal, 16)
        .movieCardContextMenu(movie)
    }

    private var continueWatchingRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Xem tiếp")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(appState.history.prefix(10)) { item in
                        let cardItem = MovieItem(
                            _id: nil,
                            name: item.name ?? item.slug,
                            slug: item.slug,
                            origin_name: nil,
                            poster_url: item.poster,
                            thumb_url: item.poster,
                            year: nil,
                            type: nil,
                            quality: nil,
                            lang: nil,
                            episode_current: item.episodeName,
                            time: nil,
                            category: nil,
                            country: nil
                        )
                        NavigationLink(destination: MovieDetailView(slug: item.slug, seedMovie: cardItem)) {
                            VStack(alignment: .leading, spacing: 5) {
                                ZStack(alignment: .bottom) {
                                    CachedAsyncImage(url: item.displayPosterURL)
                                        .frame(width: 158, height: 94)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .strokeBorder(ManiFlixTheme.cardStroke(colorScheme), lineWidth: 0.5)
                                        )

                                    ProgressView(value: item.progressRatio)
                                        .tint(prefs.currentAccentColor)
                                        .padding(6)
                                }

                                HStack(alignment: .center, spacing: 4) {
                                    Text(item.name ?? item.slug)
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                                        .lineLimit(1)
                                    Spacer(minLength: 2)
                                    Menu {
                                        MovieContextMenuItems(movie: cardItem)
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                                            .frame(width: 22, height: 20)
                                            .contentShape(Rectangle())
                                    }
                                }

                                Text(item.episodeName ?? "Xem tiếp")
                                    .font(.caption2)
                                    .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                                    .lineLimit(1)
                            }
                            .frame(width: 158)
                        }
                        .buttonStyle(.plain)
                        .movieCardContextMenu(cardItem)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    @ViewBuilder
    private func horizontalRail(title: String, items: [MovieItem]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 11) {
                        ForEach(items) { movie in
                            NavigationLink(destination: MovieDetailView(slug: movie.slug, seedMovie: movie)) {
                                MoviePosterCard(movie: movie)
                                    .frame(width: railCardWidth)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func gridSection(title: String, items: [MovieItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                .padding(.horizontal, 16)

            if items.isEmpty && !isLoading && !isLoadingFilter {
                Text("Chưa có phim nào trong danh mục này.")
                    .font(.subheadline)
                    .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 20)
            } else {
                let cols = Array(
                    repeating: GridItem(.flexible(), spacing: 11),
                    count: ManiFlixTheme.adaptiveGridColumnCount(width: containerWidth)
                )
                LazyVGrid(columns: cols, spacing: 16) {
                    ForEach(items) { movie in
                        NavigationLink(destination: MovieDetailView(slug: movie.slug, seedMovie: movie)) {
                            MoviePosterCard(movie: movie)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                if hasMorePages && !items.isEmpty {
                    Button {
                        Task { await loadMoreCurrentFeed() }
                    } label: {
                        HStack(spacing: 8) {
                            if isLoadingMore {
                                ProgressView()
                                    .scaleEffect(0.85)
                                    .tint(prefs.currentAccentColor)
                            } else {
                                Image(systemName: "arrow.down.circle")
                                    .font(.subheadline.weight(.semibold))
                            }
                            Text(isLoadingMore ? "Đang tải thêm..." : "Xem thêm")
                                .font(.subheadline.weight(.semibold))
                        }
                        .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                    .adaptiveGlassCard(cornerRadius: 12, interactive: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .disabled(isLoadingMore)
                }
            }
        }
    }

    private func loadAll() async {
        isLoading = true
        errorMsg = nil
        currentPage = 1
        hasMorePages = true
        async let latestTask = ManiFlixAPI.shared.fetchMovies(page: 1)
        async let seriesTask = ManiFlixAPI.shared.fetchCategory(type: "phim-bo", page: 1)
        async let singleTask = ManiFlixAPI.shared.fetchCategory(type: "phim-le", page: 1)
        async let animeTask = ManiFlixAPI.shared.fetchCategory(type: "hoat-hinh", page: 1)

        do {
            let latest = try await latestTask
            self.heroMovies = latest.items ?? []
            if let pag = latest.pagination, let cur = pag.currentPage, let tot = pag.totalPages {
                self.hasMorePages = cur < tot
            } else {
                self.hasMorePages = !(latest.items ?? []).isEmpty
            }
        } catch {
            self.errorMsg = error.localizedDescription
        }

        if let s = try? await seriesTask { self.seriesMovies = s.items ?? [] }
        if let m = try? await singleTask { self.singleMovies = m.items ?? [] }
        if let a = try? await animeTask { self.animeMovies = a.items ?? [] }
        isLoading = false
    }

    private func loadCategoryFeed(for category: DiscoverCategoryFilter, reset: Bool) async {
        let targetPage = reset ? 1 : (currentPage + 1)
        if reset {
            isLoadingFilter = true
            filteredMovies = []
            hasMorePages = true
            currentPage = 1
        } else {
            isLoadingMore = true
        }

        defer {
            isLoadingFilter = false
            isLoadingMore = false
        }

        do {
            let newItems: [MovieItem]
            switch category.endpoint {
            case .latest:
                let res = try await ManiFlixAPI.shared.fetchMovies(page: targetPage)
                newItems = res.items ?? []
            case .category(let type):
                let res = try await ManiFlixAPI.shared.fetchCategory(type: type, page: targetPage)
                newItems = res.items ?? []
            case .genre(let slug):
                let res = try await ManiFlixAPI.shared.fetchGenre(slug: slug, page: targetPage)
                newItems = res.items ?? []
            }

            if selectedCategory != category { return }

            if reset {
                filteredMovies = newItems
                currentPage = 1
            } else {
                let existing = Set(filteredMovies.map(\.slug))
                let unique = newItems.filter { !existing.contains($0.slug) }
                filteredMovies.append(contentsOf: unique)
                currentPage = targetPage
            }
            hasMorePages = newItems.count >= 12
        } catch {
            if reset { filteredMovies = [] }
            hasMorePages = false
        }
    }

    private func loadMoreCurrentFeed() async {
        guard !isLoadingMore else { return }
        if selectedCategory == .all {
            isLoadingMore = true
            defer { isLoadingMore = false }
            let nextPage = currentPage + 1
            do {
                let res = try await ManiFlixAPI.shared.fetchMovies(page: nextPage)
                let newItems = res.items ?? []
                let existing = Set(heroMovies.map(\.slug))
                let unique = newItems.filter { !existing.contains($0.slug) }
                heroMovies.append(contentsOf: unique)
                currentPage = nextPage
                if let pag = res.pagination, let cur = pag.currentPage, let tot = pag.totalPages {
                    hasMorePages = cur < tot
                } else {
                    hasMorePages = !newItems.isEmpty
                }
            } catch {
                hasMorePages = false
            }
        } else {
            await loadCategoryFeed(for: selectedCategory, reset: false)
        }
    }
}
