import AppKit
import SwiftUI

@MainActor
final class LumenWallAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private weak var rotationManager: WallpaperRotationManager?
    private weak var appSettings: AppSettings?
    private var openMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "LumenWall")
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "LumenWall"
        statusItem = item
        rebuildStatusMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func configure(rotationManager: WallpaperRotationManager, appSettings: AppSettings, openMainWindow: @escaping () -> Void) {
        self.rotationManager = rotationManager
        self.appSettings = appSettings
        self.openMainWindow = openMainWindow
        rebuildStatusMenu()
    }

    private func rebuildStatusMenu() {
        let menu = NSMenu()
        menu.addItem(actionItem(text("打开 LumenWall", "Open LumenWall"), action: #selector(showMainWindow)))
        menu.addItem(.separator())
        let random = actionItem(text("随机换一张", "Set a random wallpaper"), action: #selector(rotateNow))
        random.image = NSImage(systemSymbolName: "shuffle", accessibilityDescription: nil)
        random.isEnabled = rotationManager?.isRotating != true
        menu.addItem(random)

        let sources = NSMenuItem(title: text("图片来源（已选 \(rotationManager?.selectedSourceCount ?? 0)）", "Image sources (\(rotationManager?.selectedSourceCount ?? 0) selected)"), action: nil, keyEquivalent: "")
        let sourceMenu = NSMenu()
        let selectAll = actionItem(text("全部选择", "Select all"), action: #selector(selectAllSources))
        sourceMenu.addItem(selectAll)
        sourceMenu.addItem(.separator())
        for source in WallpaperSource.allCases where source != .all {
            let item = actionItem(source.displayName(for: appSettings?.language ?? .chinese), action: #selector(toggleSource(_:)))
            item.representedObject = source.rawValue
            item.state = rotationManager?.selectedSources.contains(source) == true ? .on : .off
            sourceMenu.addItem(item)
        }
        sources.submenu = sourceMenu
        menu.addItem(sources)

        menu.addItem(.separator())
        let automatic = actionItem(text("定时随机更换", "Rotate automatically"), action: #selector(toggleRotation))
        automatic.state = rotationManager?.isEnabled == true ? .on : .off
        menu.addItem(automatic)

        let intervals = NSMenuItem(title: text("更换间隔", "Interval"), action: nil, keyEquivalent: "")
        let intervalMenu = NSMenu()
        addInterval(.thirtyMinutes, title: text("30 分钟", "30 minutes"), to: intervalMenu)
        addInterval(.oneHour, title: text("1 小时", "1 hour"), to: intervalMenu)
        addInterval(.twoHours, title: text("2 小时", "2 hours"), to: intervalMenu)
        let custom = actionItem(text("在设置中自定义…", "Customize in Settings…"), action: #selector(showMainWindow))
        intervalMenu.addItem(.separator())
        intervalMenu.addItem(custom)
        intervals.submenu = intervalMenu
        menu.addItem(intervals)

        menu.addItem(.separator())
        menu.addItem(actionItem(text("退出 LumenWall", "Quit LumenWall"), action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    private func addInterval(_ interval: WallpaperRotationInterval, title: String, to menu: NSMenu) {
        let item = actionItem(title, action: #selector(selectInterval(_:)))
        item.representedObject = interval.rawValue
        item.state = interval == rotationManager?.interval ? .on : .off
        menu.addItem(item)
    }

    private func actionItem(_ title: String, action: Selector, keyEquivalent: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        return item
    }

    private func text(_ chinese: String, _ english: String) -> String {
        appSettings?.text(chinese, english) ?? chinese
    }

    @objc private func showMainWindow() {
        openMainWindow?()
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func rotateNow() {
        Task { [weak self] in
            await self?.rotationManager?.rotateNow()
            self?.rebuildStatusMenu()
        }
    }

    @objc private func toggleRotation() {
        rotationManager?.isEnabled.toggle()
        rebuildStatusMenu()
    }

    @objc private func toggleSource(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let source = WallpaperSource(rawValue: value) else { return }
        rotationManager?.toggleSource(source)
        rebuildStatusMenu()
    }

    @objc private func selectAllSources() {
        rotationManager?.selectAllSources()
        rebuildStatusMenu()
    }

    @objc private func selectInterval(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let interval = WallpaperRotationInterval(rawValue: value) else { return }
        rotationManager?.interval = interval
        rebuildStatusMenu()
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

@main
struct LumenWallApp: App {
    @NSApplicationDelegateAdaptor(LumenWallAppDelegate.self) private var appDelegate
    @StateObject private var catalog = WallpaperCatalog()
    @StateObject private var wallpaperManager = WallpaperManager()
    @StateObject private var appSettings = AppSettings()
    @StateObject private var rotationManager = WallpaperRotationManager()
    @StateObject private var favoriteWallpapers = FavoriteWallpapers()

    var body: some Scene {
        WindowGroup(id: "main") {
            MainWindowContent(appDelegate: appDelegate)
                .environmentObject(catalog)
                .environmentObject(wallpaperManager)
                .environmentObject(appSettings)
                .environmentObject(rotationManager)
                .environmentObject(favoriteWallpapers)
                .preferredColorScheme(appSettings.appearance.colorScheme)
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
    }
}

private struct MainWindowContent: View {
    let appDelegate: LumenWallAppDelegate
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var rotationManager: WallpaperRotationManager
    @EnvironmentObject private var appSettings: AppSettings

    var body: some View {
        ContentView()
            .onAppear {
                appDelegate.configure(
                    rotationManager: rotationManager,
                    appSettings: appSettings,
                    openMainWindow: { openWindow(id: "main") }
                )
            }
    }
}
