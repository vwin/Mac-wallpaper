import Foundation

@MainActor
final class WallpaperCatalog: ObservableObject {
    @Published var wallpapers: [Wallpaper] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchText = ""
    @Published var selectedKind: WallpaperKind = .all
    @Published var selectedSource: WallpaperSource = .all
    @Published var only4K = true
    @Published var display = DisplayProfile.macBook14
    @Published private(set) var isLoadingMore = false
    @Published private(set) var canLoadMore = false
    @Published private(set) var loadMoreMarker = 0

    private let service: any WallpaperProviding
    private let wallhavenService: any WallpaperProviding
    private let bingChinaService: any WallpaperProviding
    private let wallpaper360Service: any WallpaperProviding
    private let bingArchiveService = BingChinaArchiveService()
    private let cache: WallpaperCatalogCache
    private var bingArchivePage = 1
    private var sourcePage = 1

    init(service: any WallpaperProviding = WikimediaWallpaperService(), wallhavenService: any WallpaperProviding = WallhavenWallpaperService(), bingChinaService: any WallpaperProviding = BingChinaWallpaperService(), wallpaper360Service: any WallpaperProviding = Wallpaper360Service(), cache: WallpaperCatalogCache = WallpaperCatalogCache()) {
        self.service = service
        self.wallhavenService = wallhavenService
        self.bingChinaService = bingChinaService
        self.wallpaper360Service = wallpaper360Service
        self.cache = cache
    }

    var filteredWallpapers: [Wallpaper] {
        wallpapers.filter { wallpaper in
            (selectedKind == .all || wallpaper.kind == selectedKind) && (!only4K || wallpaper.is4K)
        }
    }

    func load() async {
        errorMessage = nil
        canLoadMore = false
        bingArchivePage = 1
        sourcePage = 1
        let hasSearchTerm = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let query = searchText.isEmpty ? "landscape" : searchText
        let source = selectedSource
        let cacheKey = cacheKey(for: source, query: query)
        let cached = cache.entry(for: cacheKey)
        if let cached {
            wallpapers = cached.wallpapers
            sourcePage = max(1, cached.sourcePage)
            bingArchivePage = max(1, cached.bingArchivePage)
            canLoadMore = !wallpapers.isEmpty
        }
        isLoading = cached == nil
        do {
            let latest: [Wallpaper]
            switch source {
            case .wikimedia:
                latest = try await service.search(query: query, limit: 40)
            case .wallhaven:
                latest = try await wallhavenService.search(query: query, limit: 24)
            case .bingChina:
                do {
                    latest = try await bingChinaService.search(query: query, limit: 8)
                } catch {
                    let archive = try await bingArchiveService.page(1)
                    latest = archive.wallpapers
                    bingArchivePage = 2
                }
            case .wallpaper360:
                latest = try await wallpaper360Service.search(query: query, limit: 24)
            case .all:
                async let wikimedia: [Wallpaper]? = try? service.search(query: query, limit: 24)
                async let wallhaven: [Wallpaper]? = try? wallhavenService.search(query: query, limit: 24)
                async let wallpaper360: [Wallpaper]? = try? wallpaper360Service.search(query: query, limit: 24)
                let wikiResult = await wikimedia ?? []
                let wallhavenResult = await wallhaven ?? []
                let wallpaper360Result = await wallpaper360 ?? []
                let bingResult = hasSearchTerm ? [] : ((try? await bingChinaService.search(query: query, limit: 8)) ?? [])
                latest = bingResult + wallpaper360Result + wallhavenResult + wikiResult
                if latest.isEmpty { throw URLError(.cannotLoadFromNetwork) }
            }
            // A keyword search must never retain a previous broad / fallback
            // result set. Keep cache for instant display, then replace it with
            // this query's newest authoritative page once it arrives.
            wallpapers = hasSearchTerm ? latest : merged(latest, with: wallpapers)
            canLoadMore = !wallpapers.isEmpty
            saveCache(for: cacheKey)
        } catch {
            // Cached results remain usable offline; only surface a blocking error
            // when there is nothing local to show.
            if wallpapers.isEmpty { errorMessage = "无法更新图库。请检查网络后重试。" }
        }
        isLoading = false
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let query = searchText.isEmpty ? "landscape" : searchText
            let hasSearchTerm = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let source = selectedSource
            let next: [Wallpaper]
            let hasMore: Bool
            switch source {
            case .bingChina:
                let archive = try await bingArchiveService.page(bingArchivePage)
                bingArchivePage += 1
                next = archive.wallpapers
                hasMore = archive.hasMore
            case .wikimedia:
                guard let provider = service as? any PagedWallpaperProviding else { throw URLError(.unsupportedURL) }
                sourcePage += 1
                next = try await provider.search(query: query, limit: 40, page: sourcePage)
                hasMore = !next.isEmpty
            case .wallhaven:
                guard let provider = wallhavenService as? any PagedWallpaperProviding else { throw URLError(.unsupportedURL) }
                sourcePage += 1
                next = try await provider.search(query: query, limit: 24, page: sourcePage)
                hasMore = !next.isEmpty
            case .wallpaper360:
                guard let provider = wallpaper360Service as? any PagedWallpaperProviding else { throw URLError(.unsupportedURL) }
                sourcePage += 1
                next = try await provider.search(query: query, limit: 24, page: sourcePage)
                hasMore = !next.isEmpty
            case .all:
                sourcePage += 1
                bingArchivePage += 1
                let wikiNext: [Wallpaper]
                if let provider = service as? any PagedWallpaperProviding {
                    wikiNext = (try? await provider.search(query: query, limit: 24, page: sourcePage)) ?? []
                } else {
                    wikiNext = []
                }
                let wallhavenNext: [Wallpaper]
                if let provider = wallhavenService as? any PagedWallpaperProviding {
                    wallhavenNext = (try? await provider.search(query: query, limit: 24, page: sourcePage)) ?? []
                } else {
                    wallhavenNext = []
                }
                let wallpaper360Next: [Wallpaper]
                if Wallpaper360Service.supports(query: query), let provider = wallpaper360Service as? any PagedWallpaperProviding {
                    wallpaper360Next = (try? await provider.search(query: query, limit: 24, page: sourcePage)) ?? []
                } else {
                    wallpaper360Next = []
                }
                let archivePage = hasSearchTerm ? nil : (try? await bingArchiveService.page(bingArchivePage - 1))
                next = wallpaper360Next + wikiNext + wallhavenNext + (archivePage?.wallpapers ?? [])
                hasMore = !wallpaper360Next.isEmpty || !wikiNext.isEmpty || !wallhavenNext.isEmpty || (archivePage?.hasMore ?? false)
            }
            let existing = Set(wallpapers.map(\.persistentKey))
            let unique = next.filter { !existing.contains($0.persistentKey) }
            wallpapers.append(contentsOf: unique)
            canLoadMore = hasMore && !unique.isEmpty
            loadMoreMarker += 1
            saveCache(for: cacheKey(for: source, query: query))
        } catch {
            canLoadMore = false
        }
    }

    func loadMoreIfNeeded(for wallpaper: Wallpaper) async {
        guard wallpaper.persistentKey == filteredWallpapers.last?.persistentKey else { return }
        await loadMore()
    }

    /// Random rotation uses the already cached catalogue first. If this source
    /// has never been opened, fetch one initial page without changing the UI's
    /// selected source or current search results.
    func randomWallpaper(from source: WallpaperSource) async -> Wallpaper? {
        let query = "landscape"
        let key = cacheKey(for: source, query: query)
        var candidates = cache.entry(for: key)?.wallpapers ?? []
        if candidates.isEmpty {
            do {
                let fetched: [Wallpaper]
                switch source {
                case .wikimedia:
                    fetched = try await service.search(query: query, limit: 40)
                case .wallhaven:
                    fetched = try await wallhavenService.search(query: query, limit: 24)
                case .wallpaper360:
                    fetched = try await wallpaper360Service.search(query: query, limit: 24)
                case .bingChina:
                    if let bing = try? await bingChinaService.search(query: query, limit: 8) {
                        fetched = bing
                    } else {
                        fetched = try await bingArchiveService.page(1).wallpapers
                    }
                case .all:
                    async let wiki: [Wallpaper]? = try? service.search(query: query, limit: 24)
                    async let wallhaven: [Wallpaper]? = try? wallhavenService.search(query: query, limit: 24)
                    async let wallpaper360: [Wallpaper]? = try? wallpaper360Service.search(query: query, limit: 24)
                    let bing = (try? await bingChinaService.search(query: query, limit: 8)) ?? []
                    fetched = bing + (await wallpaper360 ?? []) + (await wallhaven ?? []) + (await wiki ?? [])
                }
                candidates = fetched
                cache.save(
                    WallpaperCatalogCacheEntry(wallpapers: candidates, sourcePage: 1, bingArchivePage: source == .bingChina ? 2 : 1, updatedAt: .now),
                    for: key
                )
            } catch {
                return nil
            }
        }
        let highResolution = candidates.filter(\.is4K)
        return (highResolution.isEmpty ? candidates : highResolution).randomElement()
    }

    func randomWallpaper(from sources: Set<WallpaperSource>) async -> Wallpaper? {
        for source in sources.shuffled() where source != .all {
            if let wallpaper = await randomWallpaper(from: source) { return wallpaper }
        }
        return nil
    }

    private func cacheKey(for source: WallpaperSource, query: String) -> String {
        "\(source.rawValue)|\(query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    private func merged(_ newest: [Wallpaper], with cached: [Wallpaper]) -> [Wallpaper] {
        var known = Set<String>()
        return (newest + cached).filter { known.insert($0.persistentKey).inserted }
    }

    private func saveCache(for key: String) {
        cache.save(
            WallpaperCatalogCacheEntry(
                wallpapers: wallpapers,
                sourcePage: sourcePage,
                bingArchivePage: bingArchivePage,
                updatedAt: .now
            ),
            for: key
        )
    }
}
