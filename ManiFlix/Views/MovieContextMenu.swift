import SwiftUI
import UIKit

struct MovieContextMenuItems: View {
    let movie: MovieItem
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var prefs = AppPreferences.shared

    var body: some View {
        Button {
            Task { await appState.quickWatch(slug: movie.slug) }
        } label: {
            Label("Xem ngay", systemImage: "play.fill")
        }

        Button {
            Task { await appState.toggleFavoriteItem(movie) }
        } label: {
            let fav = appState.isFavorite(slug: movie.slug)
            Label(fav ? "Xoá khỏi Tủ phim" : "Thêm vào Tủ phim", systemImage: fav ? "bookmark.slash" : "bookmark")
        }

        Divider()

        Button {
            appState.likeMovie(movie)
        } label: {
            Label("Thích / Đề xuất thêm phim này", systemImage: "hand.thumbsup")
        }

        Button {
            appState.dislikeMovie(movie)
        } label: {
            Label("Đề xuất ít lại", systemImage: "hand.thumbsdown")
        }

        if appState.isBlocked(slug: movie.slug) {
            Button {
                appState.unblockMovie(slug: movie.slug)
            } label: {
                Label("Hiện lại phim này", systemImage: "eye")
            }
        } else {
            Button(role: .destructive) {
                appState.blockMovie(movie)
            } label: {
                Label("Không đề xuất phim này nữa", systemImage: "eye.slash")
            }
        }

        if appState.hasHistory(slug: movie.slug) {
            Divider()
            Button(role: .destructive) {
                Task { await appState.deleteHistory(slug: movie.slug) }
            } label: {
                Label("Xoá khỏi lịch sử xem", systemImage: "trash")
            }
        }

        Divider()

        Button {
            shareMovieURL()
        } label: {
            Label("Chia sẻ liên kết", systemImage: "square.and.arrow.up")
        }
    }

    private func shareMovieURL() {
        let shareURL = URL(string: "\(prefs.normalizedBaseURL)/watch/\(movie.slug)") ?? URL(string: prefs.normalizedBaseURL)!
        AppState.presentShareSheet(items: [movie.name, shareURL])
    }
}

struct MovieContextMenuModifier: ViewModifier {
    let movie: MovieItem

    func body(content: Content) -> some View {
        content
            .contextMenu {
                MovieContextMenuItems(movie: movie)
            }
    }
}

extension View {
    func movieCardContextMenu(_ movie: MovieItem) -> some View {
        modifier(MovieContextMenuModifier(movie: movie))
    }
}
