import SwiftUI

struct LibraryView: View {
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var prefs = AppPreferences.shared
    @State private var selectedSegment = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("Danh mục", selection: $selectedSegment) {
                Text("Lịch sử (\(appState.history.count))").tag(0)
                Text("Đã lưu (\(appState.favorites.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if !appState.isLoggedIn {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 44))
                        .foregroundColor(Color(white: 0.55))
                    Text("Đồng bộ tủ phim")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("Đăng nhập để giữ lịch sử xem và danh sách phim đã lưu trên mọi thiết bị.")
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
            } else if selectedSegment == 0 {
                historyList
            } else {
                favoritesGrid
            }
        }
        .background(ManiFlixTheme.background(oled: prefs.oledBlackEnabled).ignoresSafeArea())
        .navigationTitle("Tủ phim")
        .refreshable {
            await appState.refreshLibrary()
        }
    }

    private var historyList: some View {
        Group {
            if appState.history.isEmpty {
                emptyState(icon: "clock", text: "Chưa có phim đang xem.")
            } else {
                List {
                    ForEach(appState.history) { entry in
                        NavigationLink(destination: MovieDetailView(slug: entry.slug, seedMovie: nil)) {
                            HStack(spacing: 12) {
                                CachedAsyncImage(url: entry.displayPosterURL)
                                    .frame(width: 92, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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
            }
        }
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
                }
                .adaptiveSoftScrollEdge()
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
