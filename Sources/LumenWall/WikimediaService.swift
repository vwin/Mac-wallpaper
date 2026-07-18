import Foundation

protocol WallpaperProviding: Sendable {
    func search(query: String, limit: Int) async throws -> [Wallpaper]
}

protocol PagedWallpaperProviding: WallpaperProviding {
    func search(query: String, limit: Int, page: Int) async throws -> [Wallpaper]
}

/// A no-key, attribution-friendly catalogue source. Each returned item carries its source and license.
struct WikimediaWallpaperService: PagedWallpaperProviding {
    func search(query: String, limit: Int = 30) async throws -> [Wallpaper] {
        try await search(query: query, limit: limit, page: 1)
    }

    func search(query: String, limit: Int, page: Int) async throws -> [Wallpaper] {
        var components = URLComponents(string: "https://commons.wikimedia.org/w/api.php")!
        components.queryItems = [
            .init(name: "action", value: "query"), .init(name: "format", value: "json"),
            .init(name: "generator", value: "search"), .init(name: "gsrsearch", value: "filetype:bitmap \(query)"),
            .init(name: "gsrnamespace", value: "6"), .init(name: "gsrlimit", value: "\(limit)"),
            .init(name: "gsroffset", value: "\(max(0, page - 1) * limit)"),
            .init(name: "prop", value: "imageinfo"), .init(name: "iiprop", value: "url|size|extmetadata"),
            .init(name: "iiurlwidth", value: "1200")
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(CommonsResponse.self, from: data)
        return (decoded.query?.pages ?? [:]).values.compactMap { page in
            guard let image = page.imageinfo.first, let original = URL(string: image.url),
                  let preview = URL(string: image.thumburl ?? image.url) else { return nil }
            let metadata = image.extmetadata ?? [:]
            let author = metadata["Artist"]?.value.strippingHTML ?? "Wikimedia Commons"
            let license = metadata["LicenseShortName"]?.value ?? "查看来源"
            return Wallpaper(id: page.pageid, title: page.title.replacingOccurrences(of: "File:", with: ""), creator: author,
                             license: license, sourcePage: URL(string: "https://commons.wikimedia.org/?curid=\(page.pageid)")!,
                             previewURL: preview, fullURL: original, width: image.width, height: image.height, kind: .staticImage, source: .wikimedia)
        }
        .filter { $0.width >= 1920 && $0.height >= 1080 }
        .sorted { $0.width * $0.height > $1.width * $1.height }
    }
}

/// Public, SFW wallpaper catalogue. Guest access supports search without an API key.
struct WallhavenWallpaperService: PagedWallpaperProviding {
    func search(query: String, limit: Int = 24) async throws -> [Wallpaper] {
        try await search(query: query, limit: limit, page: 1)
    }

    func search(query: String, limit: Int, page: Int) async throws -> [Wallpaper] {
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        components.queryItems = [
            .init(name: "q", value: WallhavenQueryNormalizer.normalize(query)), .init(name: "categories", value: "111"),
            .init(name: "purity", value: "100"), .init(name: "atleast", value: "3840x2160"),
            .init(name: "sorting", value: "relevance"), .init(name: "page", value: "\(max(1, page))")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 12
        request.setValue("LumenWall/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(WallhavenResponse.self, from: data)
        return decoded.data.prefix(limit).compactMap { item in
            let dimensions = item.resolution.split(separator: "x").compactMap { Int($0) }
            guard let full = URL(string: item.path), let preview = URL(string: item.thumbs.large), dimensions.count == 2 else { return nil }
            return Wallpaper(id: stableWallpaperID(item.id), title: item.shortURL, creator: item.uploader?.username ?? "Wallhaven",
                             license: "Wallhaven SFW", sourcePage: URL(string: item.url)!, previewURL: preview, fullURL: full,
                             width: dimensions[0], height: dimensions[1], kind: .staticImage, source: .wallhaven)
        }
    }
}

/// 360's desktop wallpaper catalogue is China-accessible and has a real offset
/// pagination API. The public endpoint is HTTP-only, while returned image CDN
/// URLs are upgraded to HTTPS before being displayed or downloaded.
struct Wallpaper360Service: PagedWallpaperProviding {
    func search(query: String, limit: Int = 24) async throws -> [Wallpaper] {
        try await search(query: query, limit: limit, page: 1)
    }

    func search(query: String, limit: Int, page: Int) async throws -> [Wallpaper] {
        guard let categoryID = Self.categoryID(for: query) else { return [] }
        var components = URLComponents(string: "http://cdn.apc.360.cn/index.php")!
        let pageSize = min(max(limit, 1), 60)
        components.queryItems = [
            .init(name: "c", value: "WallPaper"), .init(name: "a", value: "getAppsByCategory"),
            .init(name: "from", value: "360chrome"), .init(name: "cid", value: categoryID),
            .init(name: "start", value: "\(max(0, page - 1) * pageSize)"), .init(name: "count", value: "\(pageSize)")
        ]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 15
        request.setValue("LumenWall/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let decoded = try JSONDecoder().decode(Wallpaper360Response.self, from: data)
        guard decoded.errno == "0" else { throw URLError(.badServerResponse) }
        return decoded.data.compactMap { item in
            let dimensions = item.resolution.split(separator: "x").compactMap { Int($0) }
            guard dimensions.count == 2, let full = secureURL(item.url) else { return nil }
            let preview = secureURL(item.urlThumb) ?? full
            let title = item.utag?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Wallpaper(
                id: stableWallpaperID("360-\(item.id)"),
                title: (title?.isEmpty == false ? title! : "360 壁纸"),
                creator: "360 Wallpaper",
                license: "查看来源与版权信息",
                sourcePage: URL(string: "https://wallpaper.360.com/")!,
                previewURL: preview,
                fullURL: full,
                width: dimensions[0],
                height: dimensions[1],
                kind: .staticImage,
                source: .wallpaper360
            )
        }
    }

    static func supports(query: String) -> Bool { categoryID(for: query) != nil }

    private static func categoryID(for query: String) -> String? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.localizedCaseInsensitiveCompare("landscape") == .orderedSame { return "36" }
        let mapping: [(String, String)] = [
            ("美女", "6"), ("女性", "6"), ("女生", "6"), ("女孩", "6"), ("模特", "6"),
            ("爱情", "30"), ("情侣", "30"), ("风景", "9"), ("自然", "9"), ("山", "9"), ("海", "9"),
            ("清新", "15"), ("动漫", "26"), ("二次元", "26"), ("明星", "11"),
            ("宠物", "14"), ("动物", "14"), ("游戏", "5"), ("汽车", "12"),
            ("时尚", "10"), ("日历", "29"), ("电影", "7"), ("影视", "7"),
            ("节日", "13"), ("军事", "22"), ("体育", "16"), ("宝宝", "18"), ("baby", "18"),
            ("landscape", "9"), ("anime", "26"), ("game", "5"), ("car", "12"), ("pet", "14")
        ]
        return mapping.first(where: { trimmed.localizedCaseInsensitiveContains($0.0) })?.1
    }

    private func secureURL(_ string: String) -> URL? {
        URL(string: string.replacingOccurrences(of: "http://", with: "https://"))
    }
}

/// Wallhaven's public catalogue is primarily tagged in English. Keep common
/// Chinese wallpaper queries usable without sending them to a translation service.
private enum WallhavenQueryNormalizer {
    private static let terms: [(String, String)] = [
        ("赛博朋克", "cyberpunk"), ("二次元", "anime"), ("美女", "woman portrait"), ("女性", "woman portrait"),
        ("女生", "woman portrait"), ("女孩", "woman portrait"), ("美男", "man portrait"), ("男性", "man portrait"),
        ("男生", "man portrait"), ("男孩", "man portrait"), ("人像", "portrait"), ("人物", "people"),
        ("星空", "starry sky"), ("宇宙", "space"), ("太空", "space"), ("银河", "galaxy"),
        ("星球", "planet"), ("自然", "nature"), ("风景", "landscape"), ("山", "mountain"),
        ("海洋", "ocean"), ("大海", "ocean"), ("城市", "city"), ("建筑", "architecture"),
        ("森林", "forest"), ("动物", "animal"), ("汽车", "car"), ("科技", "technology"),
        ("抽象", "abstract"), ("日落", "sunset"), ("日出", "sunrise"), ("雪", "snow"),
        ("花", "flower"), ("游戏", "game"), ("动漫", "anime"), ("电影", "movie"),
        ("夜景", "night city"), ("壁纸", "wallpaper")
    ]

    static func normalize(_ query: String) -> String {
        let containsChinese = query.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)
        }
        guard containsChinese else { return query }

        // Do not leave unmatched Chinese characters in Wallhaven's English-tag
        // query. A mixed query produces unrelated relevance results.
        let matches = terms.compactMap { term -> (Int, String)? in
            guard let range = query.range(of: term.0) else { return nil }
            return (query.distance(from: query.startIndex, to: range.lowerBound), term.1)
        }
        let translated = matches.sorted { $0.0 < $1.0 }.map(\.1)
        // An unknown Chinese term must not silently turn into a landscape search.
        // Returning an impossible tag gives the user an honest empty state instead.
        return translated.isEmpty ? "lumenwall-untranslated-query" : Array(NSOrderedSet(array: translated)).compactMap { $0 as? String }.joined(separator: " ")
    }
}

/// Microsoft Bing China's daily selection is accessible in China and refreshes every day.
struct BingChinaWallpaperService: WallpaperProviding {
    func search(query: String, limit: Int = 8) async throws -> [Wallpaper] {
        try await searchHistory(startingAt: 0, limit: limit)
    }

    func searchHistory(startingAt offset: Int, limit: Int = 8) async throws -> [Wallpaper] {
        var lastError: Error = URLError(.cannotConnectToHost)
        for host in ["https://cn.bing.com", "https://www.bing.com"] {
            do {
                var components = URLComponents(string: "\(host)/HPImageArchive.aspx")!
                components.queryItems = [
                    .init(name: "format", value: "js"), .init(name: "idx", value: "\(max(0, offset))"),
                    .init(name: "n", value: "\(min(limit, 8))"), .init(name: "mkt", value: "zh-CN")
                ]
                var request = URLRequest(url: components.url!)
                request.timeoutInterval = 15
                request.setValue("LumenWall/1.0", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let decoded = try JSONDecoder().decode(BingResponse.self, from: data)
                let wallpapers = decoded.images.compactMap { image -> Wallpaper? in
                    guard let preview = URL(string: "\(host)\(image.url)"),
                          let full = URL(string: "\(host)\(image.urlbase)_UHD.jpg") else { return nil }
                    return Wallpaper(id: stableWallpaperID(image.urlbase), title: image.copyright, creator: "Microsoft Bing",
                                     license: "Bing Wallpaper", sourcePage: URL(string: image.copyrightlink ?? host)!,
                                     previewURL: preview, fullURL: full, width: 3840, height: 2160,
                                     kind: .staticImage, source: .bingChina)
                }
                if !wallpapers.isEmpty { return wallpapers }
            } catch { lastError = error }
        }
        throw lastError
    }
}

/// A China-accessible archive that indexes Bing's original image links. It is
/// used only after the official API reaches its short rolling-history limit.
struct BingChinaArchiveService: Sendable {
    func page(_ number: Int) async throws -> BingArchivePage {
        let url = URL(string: "https://bing.ioliu.cn/?p=\(max(1, number))")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        request.setValue("LumenWall/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let html = String(data: data, encoding: .utf8) else { throw URLError(.badServerResponse) }

        let pattern = #"\{slug:\"[^\"]+\",date:\"([^\"]+)\",headline:\"(?:[^\"\\]|\\.)*\",title:\"((?:[^\"\\]|\\.)*)\",copyright:\"((?:[^\"\\]|\\.)*)\",urlbase:\"([^\"]+)\",locale:\"zh-CN\""#
        let expression = try NSRegularExpression(pattern: pattern)
        let range = NSRange(html.startIndex..., in: html)
        let wallpapers = expression.matches(in: html, range: range).compactMap { match -> Wallpaper? in
            guard let dateRange = Range(match.range(at: 1), in: html),
                  let titleRange = Range(match.range(at: 2), in: html),
                  let copyrightRange = Range(match.range(at: 3), in: html),
                  let baseRange = Range(match.range(at: 4), in: html) else { return nil }
            let date = String(html[dateRange])
            let title = String(html[titleRange]).unescapingArchiveText
            let copyright = String(html[copyrightRange]).unescapingArchiveText
            let urlbase = String(html[baseRange])
            guard let preview = URL(string: "https://cn.bing.com/th?id=\(urlbase)_1920x1080.jpg&pid=hp&w=1200"),
                  let full = URL(string: "https://cn.bing.com/th?id=\(urlbase)_UHD.jpg") else { return nil }
            return Wallpaper(
                id: stableWallpaperID(urlbase),
                title: title.isEmpty ? "必应中国 · \(date)" : title,
                creator: copyright.isEmpty ? "Microsoft Bing" : copyright,
                license: "Bing Wallpaper",
                sourcePage: url,
                previewURL: preview,
                fullURL: full,
                width: 3840,
                height: 2160,
                kind: .staticImage,
                source: .bingChina
            )
        }
        return BingArchivePage(wallpapers: wallpapers, hasMore: html.contains("hasMore:true"))
    }
}

struct BingArchivePage: Sendable {
    let wallpapers: [Wallpaper]
    let hasMore: Bool
}

private struct CommonsResponse: Decodable { let query: CommonsQuery? }
private struct CommonsQuery: Decodable { let pages: [String: CommonsPage] }
private struct CommonsPage: Decodable { let pageid: Int; let title: String; let imageinfo: [CommonsImageInfo] }
private struct CommonsImageInfo: Decodable { let url: String; let thumburl: String?; let width: Int; let height: Int; let extmetadata: [String: CommonsMetadata]? }
private struct CommonsMetadata: Decodable {
    let value: String

    private enum CodingKeys: String, CodingKey { case value }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let string = try? container.decode(String.self, forKey: .value) {
            value = string
        } else if let number = try? container.decode(Double.self, forKey: .value) {
            value = String(number)
        } else if let flag = try? container.decode(Bool.self, forKey: .value) {
            value = String(flag)
        } else {
            value = ""
        }
    }
}

private struct WallhavenResponse: Decodable { let data: [WallhavenItem] }
private struct WallhavenItem: Decodable {
    let id: String; let url: String; let shortURL: String; let path: String; let resolution: String
    let thumbs: WallhavenThumbs; let uploader: WallhavenUploader?
    enum CodingKeys: String, CodingKey { case id, url, path, resolution, thumbs, uploader; case shortURL = "short_url" }
}
private struct WallhavenThumbs: Decodable { let large: String }
private struct WallhavenUploader: Decodable { let username: String }
private struct BingResponse: Decodable { let images: [BingImage] }
private struct BingImage: Decodable { let url: String; let urlbase: String; let copyright: String; let copyrightlink: String? }
private struct Wallpaper360Response: Decodable { let errno: String; let data: [Wallpaper360Item] }
private struct Wallpaper360Item: Decodable {
    let id: String
    let resolution: String
    let url: String
    let urlThumb: String
    let utag: String?

    enum CodingKeys: String, CodingKey {
        case id, resolution, url, utag
        case urlThumb = "url_thumb"
    }
}

private func stableWallpaperID(_ value: String) -> Int {
    var hash: UInt64 = 1_469_598_103_934_665_603
    for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
    return Int(hash & UInt64(Int.max))
}

private extension String {
    var unescapingArchiveText: String {
        replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: #"\\"#, with: "\\")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var strippingHTML: String {
        replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
