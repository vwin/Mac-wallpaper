import XCTest
@testable import LumenWall

final class LumenWallTests: XCTestCase {
    func test4KClassifier() {
        let image = Wallpaper(id: 1, title: "x", creator: "x", license: "CC0", sourcePage: URL(string: "https://example.com")!, previewURL: URL(string: "https://example.com/a")!, fullURL: URL(string: "https://example.com/a")!, width: 3840, height: 2160, kind: .staticImage, source: .wallhaven)
        XCTAssertTrue(image.is4K)
    }
    func testMacBookDisplayLabel() { XCTAssertEqual(DisplayProfile.macBook14.label, "3024 × 1964") }

    func test360SearchOnlyUsesRecognizedCategories() {
        XCTAssertTrue(Wallpaper360Service.supports(query: "美女"))
        XCTAssertTrue(Wallpaper360Service.supports(query: "动漫壁纸"))
        XCTAssertFalse(Wallpaper360Service.supports(query: "太空"))
    }

    func testCatalogueCachePersistsPaginationAndWallpapers() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("catalogue.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = Wallpaper(id: 7, title: "cached", creator: "creator", license: "CC0", sourcePage: URL(string: "https://example.com")!, previewURL: URL(string: "https://example.com/preview")!, fullURL: URL(string: "https://example.com/full")!, width: 3840, height: 2160, kind: .staticImage, source: .wikimedia)
        let cache = WallpaperCatalogCache(fileURL: file)
        cache.save(.init(wallpapers: [image], sourcePage: 4, bingArchivePage: 6, updatedAt: .now), for: "test")

        let restored = WallpaperCatalogCache(fileURL: file).entry(for: "test")
        XCTAssertEqual(restored?.wallpapers, [image])
        XCTAssertEqual(restored?.sourcePage, 4)
        XCTAssertEqual(restored?.bingArchivePage, 6)
    }
}
