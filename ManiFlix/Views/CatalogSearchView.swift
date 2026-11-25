import SwiftUI

struct CatalogSearchView: View {
    @ObservedObject private var prefs = AppPreferences.shared
    @ObservedObject private var appState = AppState.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var query: String = ""
    @State private var results: [MovieItem] = []
    @State private var isSearching = false
    @State private var hasSearched = false
    @State private var debounceTask: Task<Void, Never>?

    private let suggestions = ["Hành động", "Khoa học viễn tưởng", "Hình sự", "Tâm lý", "Hoạt hình", "Kinh dị"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { topic in
                            Button {
                                query = topic
                                performSearch(immediate: true)
                            } label: {
                                Text(topic)
                                    .font(.caption.weight(.medium))
                                    .foregroundColor(ManiFlixTheme.primaryText(colorScheme))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                            }
                            .adaptiveGlassCapsule(interactive: true)
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if isSearching {
                    HStack {
                        Spacer()
                        ProgressView()
                            .tint(prefs.currentAccentColor)
                        Spacer()
                    }
                    .padding(.vertical, 50)
                } else if results.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                        Text(hasSearched ? "Không có kết quả cho \"\(query)\"" : "Tìm theo tên phim, tên gốc hoặc diễn viên")
                            .font(.subheadline)
                            .foregroundColor(ManiFlixTheme.secondaryText(colorScheme))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 70)
                } else {
                    let cols = Array(
                        repeating: GridItem(.flexible(), spacing: 11),
                        count: UIDevice.current.userInterfaceIdiom == .pad ? 4 : prefs.gridColumnsPhone
                    )
                    LazyVGrid(columns: cols, spacing: 14) {
                        ForEach(results.filter { !appState.isBlocked(slug: $0.slug) }) { movie in
                            NavigationLink(destination: MovieDetailView(slug: movie.slug, seedMovie: movie)) {
                                MoviePosterCard(movie: movie)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 92)
                }
            }
            .padding(.vertical, 10)
        }
        .background(ManiFlixTheme.background(scheme: colorScheme).ignoresSafeArea())
        .adaptiveSoftScrollEdge()
        .navigationTitle("Tìm kiếm")
        .searchable(text: $query, prompt: "Tên phim, diễn viên...")
        .onChange(of: query) { _ in
            performSearch(immediate: false)
        }
        .onSubmit(of: .search) {
            performSearch(immediate: true)
        }
    }

    private func performSearch(immediate: Bool) {
        debounceTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            hasSearched = false
            return
        }

        debounceTask = Task {
            if !immediate {
                try? await Task.sleep(nanoseconds: 320_000_000)
            }
            guard !Task.isCancelled else { return }
            isSearching = true
            do {
                let res = try await ManiFlixAPI.shared.searchMovies(query: trimmed, page: 1)
                self.results = res.items ?? []
                self.hasSearched = true
            } catch {
                self.results = []
                self.hasSearched = true
            }
            isSearching = false
        }
    }
}
