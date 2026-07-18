import Foundation

/// Keeps catalogue metadata locally. Preview and original image bytes remain
/// under URLSession's cache / the user's chosen download folder; this file is
/// deliberately limited to lightweight searchable wallpaper records.
final class WallpaperCatalogCache {
    private static let maximumEntries = 30
    private let fileURL: URL
    private var entries: [String: WallpaperCatalogCacheEntry]

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("LumenWall", isDirectory: true)
            self.fileURL = support.appendingPathComponent("catalogue-cache.json")
        }
        entries = Self.read(from: self.fileURL)
    }

    func entry(for key: String) -> WallpaperCatalogCacheEntry? { entries[key] }

    func save(_ entry: WallpaperCatalogCacheEntry, for key: String) {
        entries[key] = entry
        if entries.count > Self.maximumEntries {
            let oldest = entries.sorted { $0.value.updatedAt < $1.value.updatedAt }
                .prefix(entries.count - Self.maximumEntries)
                .map(\.key)
            oldest.forEach { entries.removeValue(forKey: $0) }
        }
        persist()
    }

    private static func read(from url: URL) -> [String: WallpaperCatalogCacheEntry] {
        guard let data = try? Data(contentsOf: url),
              let cache = try? JSONDecoder().decode([String: WallpaperCatalogCacheEntry].self, from: data) else { return [:] }
        return cache
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // A cache failure must never prevent browsing wallpapers.
        }
    }
}

struct WallpaperCatalogCacheEntry: Codable {
    let wallpapers: [Wallpaper]
    let sourcePage: Int
    let bingArchivePage: Int
    let updatedAt: Date
}
