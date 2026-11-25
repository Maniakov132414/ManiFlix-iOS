import SwiftUI

struct MoviePosterCard: View {
    let movie: MovieItem
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topTrailing) {
                CachedAsyncImage(url: movie.displayPosterURL)
                    .frame(height: prefs.gridColumnsPhone == 2 ? 236 : 166)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.6)
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

            Text(movie.name)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            if let year = movie.year?.value, year > 0 {
                Text("\(String(year)) • \(movie.lang ?? "Vietsub")")
                    .font(.system(size: 11))
                    .foregroundColor(Color(white: 0.52))
                    .lineLimit(1)
            }
        }
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
    @State private var isLoading = true
    @State private var errorMsg: String?
    @State private var showAccountSheet = false

    private let categories = ["Tất cả", "Phim bộ", "Phim lẻ", "Hoạt hình"]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
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

                    if !heroMovies.isEmpty {
                        TabView {
                            ForEach(heroMovies.prefix(5)) { movie in
                                NavigationLink(destination: MovieDetailView(slug: movie.slug, seedMovie: movie)) {
                                    heroCard(for: movie)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .frame(height: 288)
                        .tabViewStyle(.page(indexDisplayMode: .automatic))
                    } else if isLoading {
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color.white.opacity(0.05))
                            .frame(height: 276)
                            .padding(.horizontal, 16)
                    }

                    if !appState.history.isEmpty {
                        continueWatchingRail
                    }

                    if selectedGenreTag == "Tất cả" || selectedGenreTag == "Phim bộ" {
                        horizontalRail(title: "Phim bộ mới", items: seriesMovies.isEmpty ? Array(heroMovies.prefix(12)) : seriesMovies)
                    }
                    if selectedGenreTag == "Tất cả" || selectedGenreTag == "Phim lẻ" {
                        horizontalRail(title: "Phim lẻ", items: singleMovies.isEmpty ? Array(heroMovies.dropFirst(4).prefix(12)) : singleMovies)
                    }
                    if selectedGenreTag == "Tất cả" || selectedGenreTag == "Hoạt hình" {
                        horizontalRail(title: "Hoạt hình", items: animeMovies)
                    }

                    latestGridSection
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 92)
        }
        .background(ManiFlixTheme.background(oled: prefs.oledBlackEnabled).ignoresSafeArea())
        .adaptiveSoftScrollEdge()
        .navigationTitle("ManiFlix")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showAccountSheet = true
                    Haptics.impact(.light)
                } label: {
                    Image(systemName: appState.isLoggedIn ? "person.crop.circle.fill" : "person.crop.circle")
                        .font(.system(size: 18))
                        .foregroundColor(appState.isLoggedIn ? prefs.accentPreset.color : Color(white: 0.9))
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
                .frame(height: 274)
                .clipped()

            LinearGradient(
                colors: [.clear, Color.black.opacity(0.3), Color.black.opacity(0.9)],
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
                            .background(Color.white.opacity(0.18))
                            .cornerRadius(4)
                    }
                    if let lang = movie.lang, !lang.isEmpty {
                        Text(lang)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Color(white: 0.82))
                    }
                    if let year = movie.year?.value, year > 0 {
                        Text("• \(String(year))")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.65))
                    }
                }
                Text(movie.name)
                    .font(.title3.weight(.bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                if let orig = movie.origin_name, !orig.isEmpty {
                    Text(orig)
                        .font(.caption)
                        .foregroundColor(Color(white: 0.65))
                        .lineLimit(1)
                }
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.7)
        )
        .padding(.horizontal, 16)
    }

    private var continueWatchingRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Đang xem")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(appState.history.prefix(10)) { item in
                        NavigationLink(destination: MovieDetailView(slug: item.slug, seedMovie: nil)) {
                            VStack(alignment: .leading, spacing: 5) {
                                ZStack(alignment: .bottom) {
                                    CachedAsyncImage(url: item.displayPosterURL)
                                        .frame(width: 156, height: 92)
                                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                                    ProgressView(value: item.progressRatio)
                                        .tint(prefs.accentPreset.color)
                                        .padding(6)
                                }
                                Text(item.name ?? item.slug)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)
                                Text(item.episodeName ?? "Xem tiếp")
                                    .font(.caption2)
                                    .foregroundColor(Color(white: 0.52))
                                    .lineLimit(1)
                            }
                            .frame(width: 156)
                        }
                        .buttonStyle(.plain)
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
                    .font(.system(size: 17, weight: .semibold))
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
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)

            let cols = Array(
                repeating: GridItem(.flexible(), spacing: 11),
                count: UIDevice.current.userInterfaceIdiom == .pad ? 4 : prefs.gridColumnsPhone
            )
            LazyVGrid(columns: cols, spacing: 14) {
                ForEach(heroMovies) { movie in
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
