import Foundation

enum WallpaperKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case all = "全部"
    case staticImage = "静态"
    case dynamic = "动态"
    var id: String { rawValue }
}

enum WallpaperSource: String, CaseIterable, Identifiable, Sendable, Codable {
    case all = "全部来源"
    case bingChina = "必应中国（每日）"
    case wallpaper360 = "360壁纸（4K）"
    case wallhaven = "Wallhaven"
    case wikimedia = "Wikimedia"
    var id: String { rawValue }
}

struct Wallpaper: Identifiable, Hashable, Sendable, Codable {
    let id: Int
    let title: String
    let creator: String
    let license: String
    let sourcePage: URL
    let previewURL: URL
    let fullURL: URL
    let width: Int
    let height: Int
    let kind: WallpaperKind
    let source: WallpaperSource

    var resolution: String { "\(width) × \(height)" }
    var is4K: Bool { width >= 3840 || height >= 2160 }
    var aspectRatio: Double { guard height > 0 else { return 1 }; return Double(width) / Double(height) }

    /// The original image can be tens or hundreds of megabytes. Use a 4K rendition for desktop use.
    var desktopDownloadURL: URL {
        guard source == .wikimedia else { return fullURL }
        let optimized = previewURL.absoluteString.replacingOccurrences(
            of: #"/\d+px-"#, with: "/3840px-", options: .regularExpression
        )
        return URL(string: optimized) ?? fullURL
    }

    var persistentKey: String { "\(source.rawValue)|\(fullURL.absoluteString)" }
}

struct DisplayProfile: Equatable {
    let width: Int
    let height: Int
    let scale: Int

    static let macBook14 = DisplayProfile(width: 3024, height: 1964, scale: 2)
    var label: String { "\(width) × \(height)" }
}
