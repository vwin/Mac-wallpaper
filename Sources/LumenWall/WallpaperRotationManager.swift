import AppKit
import Foundation

enum WallpaperRotationInterval: String, CaseIterable, Identifiable {
    case thirtyMinutes
    case oneHour
    case twoHours
    case custom

    var id: String { rawValue }

    var minutes: Int? {
        switch self {
        case .thirtyMinutes: 30
        case .oneHour: 60
        case .twoHours: 120
        case .custom: nil
        }
    }
}

@MainActor
final class WallpaperRotationManager: ObservableObject {
    @Published private(set) var isRotating = false
    @Published private(set) var nextRotationDate: Date?
    @Published var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: enabledKey)
            reschedule()
        }
    }
    @Published var selectedSources: Set<WallpaperSource> {
        didSet {
            if selectedSources.isEmpty {
                selectedSources = Self.availableSources
                return
            }
            UserDefaults.standard.set(selectedSources.map(\.rawValue), forKey: sourcesKey)
        }
    }
    @Published var interval: WallpaperRotationInterval {
        didSet {
            UserDefaults.standard.set(interval.rawValue, forKey: intervalKey)
            reschedule()
        }
    }
    @Published var customMinutes: Int {
        didSet {
            let normalized = Self.clamped(customMinutes)
            if normalized != customMinutes {
                customMinutes = normalized
                return
            }
            UserDefaults.standard.set(customMinutes, forKey: customMinutesKey)
            if interval == .custom { reschedule() }
        }
    }

    private let enabledKey = "wallpaperRotationEnabled"
    private let sourcesKey = "wallpaperRotationSources"
    private let legacySourceKey = "wallpaperRotationSource"
    private let intervalKey = "wallpaperRotationInterval"
    private let customMinutesKey = "wallpaperRotationCustomMinutes"
    private let lastRotationKey = "wallpaperRotationLastDate"
    // A Task.sleep based schedule is not tied to a particular RunLoop mode. This
    // is important when the main window is closed, a menu is being tracked, or the
    // app returns from sleep, where a default-mode Timer can be delayed indefinitely.
    private var scheduledRotationTask: Task<Void, Never>?
    private var wakeObserver: NSObjectProtocol?
    private var applicationActiveObserver: NSObjectProtocol?
    private weak var catalog: WallpaperCatalog?
    private weak var wallpaperManager: WallpaperManager?

    static let availableSources = Set(WallpaperSource.allCases.filter { $0 != .all })

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: enabledKey)
        let savedSources = (UserDefaults.standard.array(forKey: sourcesKey) as? [String] ?? [])
            .compactMap(WallpaperSource.init(rawValue:))
            .filter { $0 != .all }
        if savedSources.isEmpty,
           let legacy = WallpaperSource(rawValue: UserDefaults.standard.string(forKey: legacySourceKey) ?? ""),
           legacy != .all {
            selectedSources = [legacy]
        } else {
            selectedSources = Set(savedSources).isEmpty ? Self.availableSources : Set(savedSources)
        }
        interval = WallpaperRotationInterval(rawValue: UserDefaults.standard.string(forKey: intervalKey) ?? "") ?? .thirtyMinutes
        customMinutes = Self.clamped(UserDefaults.standard.object(forKey: customMinutesKey) as? Int ?? 30)

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: NSWorkspace.shared,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.catchUpAfterResume() }
        }
        applicationActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.catchUpAfterResume() }
        }
    }

    var intervalMinutes: Int { interval.minutes ?? customMinutes }
    var selectedSourceCount: Int { selectedSources.count }

    func toggleSource(_ source: WallpaperSource) {
        guard source != .all else { return }
        if selectedSources.contains(source), selectedSources.count > 1 {
            selectedSources.remove(source)
        } else {
            selectedSources.insert(source)
        }
    }

    func selectAllSources() { selectedSources = Self.availableSources }

    func activate(catalog: WallpaperCatalog, wallpaperManager: WallpaperManager) {
        self.catalog = catalog
        self.wallpaperManager = wallpaperManager
        reschedule()
    }

    func rotateNow() async {
        guard !isRotating, let catalog, let wallpaperManager else { return }
        isRotating = true
        defer { isRotating = false }
        guard let wallpaper = await catalog.randomWallpaper(from: selectedSources) else {
            wallpaperManager.setRotationStatus("未找到可用于随机更换的壁纸。")
            reschedule()
            return
        }
        let didApply = await wallpaperManager.apply(wallpaper)
        if didApply {
            UserDefaults.standard.set(Date(), forKey: lastRotationKey)
        }
        reschedule()
    }

    private func reschedule() {
        scheduledRotationTask?.cancel()
        scheduledRotationTask = nil
        nextRotationDate = nil
        guard isEnabled, catalog != nil, wallpaperManager != nil else { return }

        let intervalSeconds = TimeInterval(intervalMinutes * 60)
        let previous = UserDefaults.standard.object(forKey: lastRotationKey) as? Date
        let elapsed = previous.map { Date().timeIntervalSince($0) } ?? 0
        let delay = previous == nil ? intervalSeconds : max(0, intervalSeconds - elapsed)
        nextRotationDate = Date().addingTimeInterval(delay)
        scheduledRotationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(delay))
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.rotateNow()
        }
    }

    /// A sleeping Mac cannot run timers. On wake or reactivation, compare the
    /// persisted completion time with wall-clock time and immediately perform a
    /// missed rotation instead of waiting for another full interval.
    private func catchUpAfterResume() {
        guard isEnabled, catalog != nil, wallpaperManager != nil else { return }
        guard let previous = UserDefaults.standard.object(forKey: lastRotationKey) as? Date else {
            reschedule()
            return
        }
        guard Date().timeIntervalSince(previous) >= TimeInterval(intervalMinutes * 60) else {
            reschedule()
            return
        }
        scheduledRotationTask?.cancel()
        scheduledRotationTask = Task { [weak self] in
            await self?.rotateNow()
        }
    }

    private static func clamped(_ value: Int) -> Int { min(max(value, 30), 24 * 60) }
}
