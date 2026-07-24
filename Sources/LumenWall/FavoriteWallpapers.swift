import Foundation

/// A compact, local collection of wallpaper records. Storing the complete record
/// means a favourite remains available even after its source page leaves the
/// network catalogue or cache.
@MainActor
final class FavoriteWallpapers: ObservableObject {
    @Published private(set) var wallpapers: [Wallpaper] = []

    private let storageKey = "favoriteWallpapers.v1"

    init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let saved = try? JSONDecoder().decode([Wallpaper].self, from: data) else { return }
        var known = Set<String>()
        wallpapers = saved.filter { known.insert($0.persistentKey).inserted }
    }

    func contains(_ wallpaper: Wallpaper) -> Bool {
        wallpapers.contains { $0.persistentKey == wallpaper.persistentKey }
    }

    /// Adds a wallpaper without turning an existing favourite back off. This is
    /// used by the menu-bar shortcut, where "favourite" must be idempotent.
    @discardableResult
    func add(_ wallpaper: Wallpaper) -> Bool {
        guard !contains(wallpaper) else { return false }
        wallpapers.insert(wallpaper, at: 0)
        persist()
        return true
    }

    func toggle(_ wallpaper: Wallpaper) {
        if let index = wallpapers.firstIndex(where: { $0.persistentKey == wallpaper.persistentKey }) {
            wallpapers.remove(at: index)
        } else {
            wallpapers.insert(wallpaper, at: 0)
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(wallpapers) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
