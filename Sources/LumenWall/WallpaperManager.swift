import AppKit
import Foundation

@MainActor
final class WallpaperManager: ObservableObject {
    @Published private(set) var downloadDirectory: URL
    @Published private(set) var statusMessage: String?
    @Published private(set) var isApplying = false
    @Published private(set) var currentWallpaper: Wallpaper?
    @Published var applyToAllDisplays: Bool {
        didSet { UserDefaults.standard.set(applyToAllDisplays, forKey: applyToAllDisplaysKey) }
    }
    @Published var applyToAllSpaces: Bool {
        didSet { UserDefaults.standard.set(applyToAllSpaces, forKey: applyToAllSpacesKey) }
    }

    private let directoryKey = "wallpaperDownloadDirectory"
    private let downloadedFilesKey = "downloadedWallpaperFiles"
    private let downloadedBookmarksKey = "downloadedWallpaperBookmarks"
    private let applyToAllDisplaysKey = "applyWallpaperToAllDisplays"
    private let applyToAllSpacesKey = "applyWallpaperToAllSpaces"
    private let syncedWallpaperBookmarkKey = "syncedWallpaperBookmark"
    private let currentWallpaperKey = "currentAppliedWallpaper.v1"
    private var activeSpaceObserver: NSObjectProtocol?

    init() {
        let fallback = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("LumenWall", isDirectory: true)
        if let saved = UserDefaults.standard.string(forKey: directoryKey) {
            downloadDirectory = URL(fileURLWithPath: saved, isDirectory: true)
        } else {
            downloadDirectory = fallback
        }
        applyToAllDisplays = UserDefaults.standard.object(forKey: applyToAllDisplaysKey) as? Bool ?? true
        applyToAllSpaces = UserDefaults.standard.object(forKey: applyToAllSpacesKey) as? Bool ?? true
        currentWallpaper = UserDefaults.standard.data(forKey: currentWallpaperKey)
            .flatMap { try? JSONDecoder().decode(Wallpaper.self, from: $0) }
        repairLegacyDownloadFileNames()
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.applySavedWallpaperForActiveSpace() }
        }
    }

    var directoryLabel: String { downloadDirectory.path }
    var connectedDisplayCount: Int { NSScreen.screens.count }
    var connectedDisplaysSummary: String {
        let count = connectedDisplayCount
        return applyToAllDisplays ? "将同步到 \(count) 个已连接显示器" : "仅设置主显示器（检测到 \(count) 个显示器）"
    }

    func isDownloaded(_ wallpaper: Wallpaper) -> Bool { downloadedFile(for: wallpaper) != nil }

    func setRotationStatus(_ message: String) { statusMessage = message }

    func chooseDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择壁纸保存位置"
        panel.message = "设为壁纸时，原图会保存在此文件夹。"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = downloadDirectory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        downloadDirectory = url
        UserDefaults.standard.set(url.path, forKey: directoryKey)
        statusMessage = "已将壁纸保存到 \(url.lastPathComponent)"
    }

    @discardableResult
    func apply(_ wallpaper: Wallpaper) async -> Bool {
        guard !isApplying else { return false }
        isApplying = true
        statusMessage = "正在下载适配显示器的高质量壁纸…"
        defer { isApplying = false }
        do {
            try FileManager.default.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
            if let existing = downloadedFile(for: wallpaper) {
                statusMessage = "该壁纸已下载，正在直接设置…"
                let applied = try await setDesktopImage(existing)
                rememberCurrentWallpaper(wallpaper)
                statusMessage = "已使用本地文件设为 \(applied) 个显示器的壁纸"
                return true
            }
            var request = URLRequest(url: wallpaper.desktopDownloadURL)
            request.timeoutInterval = 300
            request.setValue("LumenWall/1.0 (macOS wallpaper downloader)", forHTTPHeaderField: "User-Agent")
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 300
            configuration.timeoutIntervalForResource = 900
            let (temporaryURL, response) = try await URLSession(configuration: configuration).download(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw URLError(.badServerResponse) }
            let destination = availableFileURL(for: wallpaper)
            try FileManager.default.moveItem(at: temporaryURL, to: destination)
            try saveDownloadedFile(destination, for: wallpaper)
            let applied = try await setDesktopImage(destination)
            rememberCurrentWallpaper(wallpaper)
            statusMessage = "已设为 \(applied) 个显示器的壁纸，并保存到 \(downloadDirectory.lastPathComponent)"
            return true
        } catch {
            let host = wallpaper.desktopDownloadURL.host ?? "壁纸服务器"
            statusMessage = "设置失败（\(host)）：\(error.localizedDescription)"
            return false
        }
    }

    private func setDesktopImage(_ fileURL: URL) async throws -> Int {
        let screens = applyToAllDisplays ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        guard !screens.isEmpty else { throw URLError(.cannotFindHost) }

        // Always use the public API for the active Space first.  The Wallpaper Store
        // is only a supplement for the other Spaces; it cannot replace this call.
        for screen in screens {
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            try NSWorkspace.shared.setDesktopImageURL(fileURL, for: screen, options: options)
            try await confirmDesktopImage(fileURL, for: screen)
        }
        if applyToAllSpaces {
            try rememberWallpaperForSpaces(fileURL)
        }
        return screens.count
    }

    private func rememberCurrentWallpaper(_ wallpaper: Wallpaper) {
        currentWallpaper = wallpaper
        guard let data = try? JSONEncoder().encode(wallpaper) else { return }
        UserDefaults.standard.set(data, forKey: currentWallpaperKey)
    }

    private func confirmDesktopImage(_ fileURL: URL, for screen: NSScreen) async throws {
        let expected = fileURL.resolvingSymlinksInPath().standardizedFileURL
        for _ in 0..<4 {
            if NSWorkspace.shared.desktopImageURL(for: screen)?.resolvingSymlinksInPath().standardizedFileURL == expected {
                return
            }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw WallpaperApplyError.verificationFailed
    }

    /// AppKit only controls the active Space. Retain the chosen local file and set
    /// it again whenever macOS reports a Space change. This keeps all Spaces in
    /// sync without mutating the private WallpaperAgent store.
    private func rememberWallpaperForSpaces(_ fileURL: URL) throws {
        let bookmark = try fileURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: syncedWallpaperBookmarkKey)
    }

    private func applySavedWallpaperForActiveSpace() {
        guard applyToAllSpaces,
              let bookmark = UserDefaults.standard.data(forKey: syncedWallpaperBookmarkKey) else { return }
        var stale = false
        guard let fileURL = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
              FileManager.default.fileExists(atPath: fileURL.path) else { return }
        if stale { try? rememberWallpaperForSpaces(fileURL) }
        let screens = applyToAllDisplays ? NSScreen.screens : [NSScreen.main].compactMap { $0 }
        for screen in screens {
            let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
            do {
                try NSWorkspace.shared.setDesktopImageURL(fileURL, for: screen, options: options)
            } catch {
                statusMessage = "切换虚拟桌面时同步失败：\(error.localizedDescription)"
            }
        }
    }

    private func downloadedFile(for wallpaper: Wallpaper) -> URL? {
        let bookmarks = UserDefaults.standard.dictionary(forKey: downloadedBookmarksKey) ?? [:]
        if let bookmark = bookmarks[wallpaper.persistentKey] as? Data {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                if stale { try? saveDownloadedFile(url, for: wallpaper) }
                return url
            }
        }
        let files = UserDefaults.standard.dictionary(forKey: downloadedFilesKey) as? [String: String] ?? [:]
        if let path = files[wallpaper.persistentKey] ?? files[String(wallpaper.id)], FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    private func saveDownloadedFile(_ fileURL: URL, for wallpaper: Wallpaper) throws {
        var files = UserDefaults.standard.dictionary(forKey: downloadedFilesKey) as? [String: String] ?? [:]
        files[wallpaper.persistentKey] = fileURL.path
        UserDefaults.standard.set(files, forKey: downloadedFilesKey)
        let bookmark = try fileURL.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
        var bookmarks = UserDefaults.standard.dictionary(forKey: downloadedBookmarksKey) ?? [:]
        bookmarks[wallpaper.persistentKey] = bookmark
        UserDefaults.standard.set(bookmarks, forKey: downloadedBookmarksKey)
    }

    private func availableFileURL(for wallpaper: Wallpaper) -> URL {
        let ext = safeFileExtension(wallpaper.fullURL.pathExtension)
        let name = wallpaperFileBase(wallpaper)
        var candidate = downloadDirectory.appendingPathComponent("\(name).\(ext)")
        var copy = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = downloadDirectory.appendingPathComponent("\(name)-\(copy).\(ext)")
            copy += 1
        }
        return candidate
    }

    private func wallpaperFileBase(_ wallpaper: Wallpaper) -> String {
        // APFS supports Unicode file names. Keep Chinese and accented titles,
        // while replacing only characters that are unsafe in a file path.
        let cleaned = wallpaper.title
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: #"[\\/:*?\"<>|\p{Cc}]"#, with: "-", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ".-")))
        let sourceName = wallpaper.source.rawValue
            .replacingOccurrences(of: #"[\\/:*?\"<>|]"#, with: "-", options: .regularExpression)
        let base = cleaned.isEmpty ? sourceName : cleaned
        let token = String(wallpaper.id.magnitude, radix: 16)
        return String("\(base)-\(token)".prefix(100))
    }

    private func safeFileExtension(_ value: String) -> String {
        let normalized = value.lowercased()
        return normalized.range(of: #"^[a-z0-9]{1,8}$"#, options: .regularExpression) != nil ? normalized : "jpg"
    }

    /// Old builds removed every non-ASCII title character, producing names like
    /// `.jpg` and `-2.jpg`. Move those files to a stable source-and-key name and
    /// update both persistent indexes without touching normally named downloads.
    private func repairLegacyDownloadFileNames() {
        var files = UserDefaults.standard.dictionary(forKey: downloadedFilesKey) as? [String: String] ?? [:]
        var bookmarks = UserDefaults.standard.dictionary(forKey: downloadedBookmarksKey) ?? [:]
        var changed = false

        for (key, path) in files {
            let current = URL(fileURLWithPath: path)
            guard FileManager.default.fileExists(atPath: current.path), isLegacyMissingName(current) else { continue }
            let ext = safeFileExtension(current.pathExtension)
            let destination = current.deletingLastPathComponent()
                .appendingPathComponent("LumenWall-\(legacyFileToken(key)).\(ext)")
            guard !FileManager.default.fileExists(atPath: destination.path) else { continue }
            do {
                try FileManager.default.moveItem(at: current, to: destination)
                files[key] = destination.path
                bookmarks[key] = try destination.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
                changed = true
            } catch {
                continue
            }
        }

        if changed {
            UserDefaults.standard.set(files, forKey: downloadedFilesKey)
            UserDefaults.standard.set(bookmarks, forKey: downloadedBookmarksKey)
        }
    }

    private func isLegacyMissingName(_ url: URL) -> Bool {
        let stem = url.deletingPathExtension().lastPathComponent
        return stem.range(of: #"^[\s._-]*\d*[\s._-]*$"#, options: .regularExpression) != nil
    }

    private func legacyFileToken(_ key: String) -> String {
        var hash: UInt64 = 1_469_598_103_934_665_603
        for byte in key.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return String(hash, radix: 16)
    }
}

private enum WallpaperApplyError: LocalizedError {
    case verificationFailed
    var errorDescription: String? {
        switch self {
        case .verificationFailed: "系统未确认壁纸设置，请在系统设置中检查显示器权限。"
        }
    }
}
