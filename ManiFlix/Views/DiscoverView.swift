import SwiftUI

struct MoviePosterCard: View {
    let movie: MovieItem
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .bottomLeading) {
                CachedAsyncImage(url: movie.displayPosterURL)
                    .frame(height: prefs.gridColumnsPhone == 2 ? 238 : 168)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5)
                    )
                    .shadow(color: Color.black.opacity(0.28), radius: 8, x: 0, y: 4)

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
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Menu {
                    MovieContextMenuItems(movie: movie)
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(white: 0.65))
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
            }

            if let year = movie.year?.value, year > 0 {
                Text("\(String(year)) • \(movie.lang ?? "Vietsub")")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.55))
                    .lineLimit(1)
            }
        }
        .movieCardContextMenu(movie)
    }
}

struct DiscoverView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var appState = AppState.shared

    @State private var heroMovies: [MovieItem] = []
    @State private var seriesMovies: [MovieItem] = []
    @State private var singleMovies: [MovieItem] = []
    @State private var animeMovies: [MovieItem] = []
    @State private var selectedGenreTag: String = "Tất cả"
    @State private var heroSelection: Int = 0
    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var showAccountSheet = false

    private let categories = ["Tất cả", "Phim bộ", "Phim lẻ", "Hoạt hình"]

    private var visibleHero: [MovieItem] {
        heroMovies.filter { !appState.isBlocked(slug: $0.slug) }
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

    var body: some View {
        ZStack(alignment: .top) {
            ManiFlixTheme.background(oled: prefs.oledBlackEnabled)
                .ignoresSafeArea()

            AmbientArtworkBackground(url: currentAmbientURL, oled: prefs.oledBlackEnabled, height: 390)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let err = errorMsg, heroMovies.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "wifi.slash")
                                .font(.title2)
                                .foregroundColor(Color(white: 0.55))
                            Text(err)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            Button("Thử lại") {
                                Task { await loadAll() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(prefs.accentPreset.color)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 80)
                    } else {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(categories, id: \.self) { cat in
                                    Button {
                                        selectedGenreTag = cat
                                        Haptics.impact(.light)
                                    } label: {
                                        Text(cat)
                                            .font(.system(size: 13, weight: selectedGenreTag == cat ? .semibold : .regular))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 7)
                                    }
                                    .adaptiveGlassCapsule(
                                        interactive: true,
                                        tint: selectedGenreTag == cat ? prefs.accentPreset.color : nil
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                        }

                        if !visibleHero.isEmpty {
                            let featured = Array(visibleHero.prefix(5))
                            TabView(selection: $heroSelection) {
                                ForEach(Array(featured.enumerated()), id: \.element.id) { idx, movie in
                                    NavigationLink(destination: MovieDetailView(slug: movie.slug, seedMovie: movie)) {
                                        heroCard(for: movie)
                                    }
                                    .buttonStyle(.plain)
                                    .movieCardContextMenu(movie)
                                    .tag(idx)
                                }
                            }
                            .frame(height: 292)
                            .tabViewStyle(.page(indexDisplayMode: .automatic))
                        } else if isLoading {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(Color.white.opacity(0.05))
                                .frame(height: 278)
                                .padding(.horizontal, 16)
                        }

                        if !appState.history.isEmpty {
                            continueWatchingRail
                        }

                        if selectedGenreTag == "Tất cả" || selectedGenreTag == "Phim bộ" {
                            horizontalRail(title: "Phim bộ mới", items: visibleSeries)
                        }
                        if selectedGenreTag == "Tất cả" || selectedGenreTag == "Phim lẻ" {
                            horizontalRail(title: "Phim lẻ tuyển chọn", items: visibleSingle)
                        }
                        if selectedGenreTag == "Tất cả" || selectedGenreTag == "Hoạt hình" {
                            horizontalRail(title: "Hoạt hình & Anime", items: visibleAnime)
                        }

                        latestGridSection
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 92)
            }
        }
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
                        .foregroundColor(appState.isLoggedIn ? prefs.accentPreset.color : Color(white: 0.92))
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
            await loadAll()
        }
        .task {
            if heroMovies.isEmpty {
                await loadAll()
            }
        }
    }

    private func heroCard(for movie: MovieItem) -> some View {
        ZStack(alignment: .bottomLeading) {
            CachedAsyncImage(url: movie.displayThumbURL ?? movie.displayPosterURL)
                .frame(maxWidth: .infinity)
                .frame(height: 278)
                .clipped()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.28), Color.black.opacity(0.9)],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    if let q = movie.quality, !q.isEmpty {
                        Text(q)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(prefs.accentPreset.color.opacity(0.85))
                            .cornerRadius(4)
                    }
                    if let lang = movie.lang, !lang.isEmpty {
                        Text(lang)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(white: 0.85))
                    }
                    if let year = movie.year?.value, year > 0 {
                        Text("• \(String(year))")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.68))
                    }
                }
                Text(movie.name)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                if let orig = movie.origin_name, !orig.isEmpty {
                    Text(orig)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.7))
                        .lineLimit(1)
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
        )
        .shadow(color: Color.black.opacity(0.4), radius: 14, x: 0, y: 8)
        .padding(.horizontal, 16)
    }

    private var continueWatchingRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Xem tiếp")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
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
                                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                                        )

                                    ProgressView(value: item.progressRatio)
                                        .tint(prefs.accentPreset.color)
                                        .padding(6)
                                }

                                HStack(alignment: .center, spacing: 4) {
                                    Text(item.name ?? item.slug)
                                        .font(.caption.weight(.medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Spacer(minLength: 2)
                                    Menu {
                                        MovieContextMenuItems(movie: cardItem)
                                    } label: {
                                        Image(systemName: "ellipsis")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(Color(white: 0.65))
                                            .frame(width: 22, height: 20)
                                            .contentShape(Rectangle())
                                    }
                                }

                                Text(item.episodeName ?? "Xem tiếp")
                                    .font(.caption2)
                                    .foregroundColor(Color(white: 0.55))
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
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 11) {
                        ForEach(items) { movie in
                            NavigationLink(destination: MovieDetailView(slug: movie.slug, seedMovie: movie)) {
                                MoviePosterCard(movie: movie)
                                    .frame(width: 118)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private var latestGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Mới cập nhật")
                .font(.system(size: 19, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)

            let cols = Array(
                repeating: GridItem(.flexible(), spacing: 11),
                count: UIDevice.current.userInterfaceIdiom == .pad ? 4 : prefs.gridColumnsPhone
            )
            LazyVGrid(columns: cols, spacing: 16) {
                ForEach(visibleHero) { movie in
                    NavigationLink(destination: MovieDetailView(slug: movie.slug, seedMovie: movie)) {
                        MoviePosterCard(movie: movie)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func loadAll() async {
        isLoading = true
        errorMsg = nil
        async let latestTask = ManiFlixAPI.shared.fetchMovies(page: 1)
        async let seriesTask = ManiFlixAPI.shared.fetchCategory(type: "phim-bo", page: 1)
        async let singleTask = ManiFlixAPI.shared.fetchCategory(type: "phim-le", page: 1)
        async let animeTask = ManiFlixAPI.shared.fetchCategory(type: "hoat-hinh", page: 1)

        do {
            let latest = try await latestTask
            self.heroMovies = latest.items ?? []
        } catch {
            self.errorMsg = error.localizedDescription
        }

        if let s = try? await seriesTask { self.seriesMovies = s.items ?? [] }
        if let m = try? await singleTask { self.singleMovies = m.items ?? [] }
        if let a = try? await animeTask { self.animeMovies = a.items ?? [] }
        isLoading = false
    }
}
