import SwiftUI

struct LibraryView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var selectedSegment = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Danh mục", selection: $selectedSegment) {
                Text("Đang xem").tag(0)
                Text("Đã lưu").tag(1)
                Text("Đã ẩn (\(appState.blockedMovies.count))").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if selectedSegment == 0 {
                historyList
            } else if selectedSegment == 1 {
                if appState.isLoggedIn {
                    favoritesGrid
                } else {
                    loginPrompt(
                        title: "Đồng bộ danh sách đã lưu",
                        subtitle: "Đăng nhập để lưu và đồng bộ các phim bạn yêu thích trên mọi thiết bị."
                    )
                }
            } else {
                blockedMoviesList
            }
        }
        .background(ManiFlixTheme.background(oled: prefs.oledBlackEnabled).ignoresSafeArea())
        .navigationTitle("Tủ phim")
        .refreshable {
            await appState.refreshLibrary()
        }
    }

    private func loginPrompt(title: String, subtitle: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "person.crop.circle")
                .font(.system(size: 44))
                .foregroundColor(Color(white: 0.55))
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                appState.showAuthSheet = true
            } label: {
                Text("Đăng nhập")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .adaptiveGlassCapsule(tint: prefs.accentPreset.color)
            Spacer()
        }
    }

    private var historyList: some View {
        Group {
            if appState.history.isEmpty {
                VStack(spacing: 12) {
                    if !appState.isLoggedIn {
                        syncBanner
                    }
                    emptyState(icon: "clock", text: "Chưa có phim đang xem.")
                }
            } else {
                List {
                    if !appState.isLoggedIn {
                        syncBanner
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                    ForEach(appState.history) { entry in
                        NavigationLink(destination: MovieDetailView(slug: entry.slug, seedMovie: nil)) {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: entry.displayPosterURL)
                                    .frame(width: 96, height: 58)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                                    )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.name ?? entry.slug)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundColor(.white)
                                        .lineLimit(1)
                                    Text("\(entry.episodeName ?? "Tập 1") • \(PlayerEngine.formatTime(entry.currentTime ?? 0))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    ProgressView(value: entry.progressRatio)
                                        .tint(prefs.accentPreset.color)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .listRowBackground(Color.clear)
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await appState.deleteHistory(slug: entry.slug) }
                            } label: {
                                Label("Xoá", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .adaptiveHiddenScrollBackground()
            }
        }
    }

    private var syncBanner: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Chưa đăng nhập")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Text("Đăng nhập để đồng bộ lịch sử xem trên nhiều thiết bị.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button("Đăng nhập") {
                appState.showAuthSheet = true
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(prefs.accentPreset.color)
            .clipShape(Capsule())
        }
        .padding(12)
        .adaptiveGlassCard(cornerRadius: 12)
    }

    private var favoritesGrid: some View {
        Group {
            if appState.favorites.isEmpty {
                emptyState(icon: "bookmark", text: "Chưa có phim đã lưu.")
            } else {
                ScrollView {
                    let cols = Array(
                        repeating: GridItem(.flexible(), spacing: 11),
                        count: UIDevice.current.userInterfaceIdiom == .pad ? 4 : prefs.gridColumnsPhone
                    )
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(appState.favorites) { fav in
                            let item = MovieItem(
                                _id: nil,
                                name: fav.name ?? fav.slug,
                                slug: fav.slug,
                                origin_name: nil,
                                poster_url: fav.poster,
                                thumb_url: nil,
                                year: fav.year,
                                type: nil,
                                quality: fav.quality,
                                lang: fav.lang,
                                episode_current: nil,
                                time: nil,
                                category: nil,
                                country: nil
                            )
                            NavigationLink(destination: MovieDetailView(slug: fav.slug, seedMovie: item)) {
                                MoviePosterCard(movie: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .padding(.bottom, 76)
                }
                .adaptiveSoftScrollEdge()
            }
        }
    }

    private var blockedMoviesList: some View {
        Group {
            if appState.blockedMovies.isEmpty {
                emptyState(icon: "eye.slash", text: "Chưa có phim nào bị ẩn.")
            } else {
                List {
                    ForEach(appState.blockedMovies) { item in
                        HStack(spacing: 12) {
                            NavigationLink(destination: MovieDetailView(slug: item.slug, seedMovie: nil)) {
                                HStack(spacing: 12) {
                                    CachedAsyncImage(url: ImageURLResolver.resolve(item.poster))
                                        .frame(width: 52, height: 74)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
                                        )

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(item.name)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundColor(.white)
                                            .lineLimit(2)
                                        Text("Đang ẩn khỏi trang chủ & tìm kiếm")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            Spacer(minLength: 8)

                            Button {
                                appState.unblockMovie(slug: item.slug)
                            } label: {
                                Text("Hiện lại")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(prefs.accentPreset.color)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 3)
                        .listRowBackground(Color.clear)
                        .swipeActions {
                            Button {
                                appState.unblockMovie(slug: item.slug)
                            } label: {
                                Label("Hiện lại", systemImage: "eye")
                            }
                            .tint(prefs.accentPreset.color)
                        }
                    }
                }
                .listStyle(.plain)
                .adaptiveHiddenScrollBackground()
            }
        }
    }

    private func emptyState(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(Color(white: 0.45))
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
