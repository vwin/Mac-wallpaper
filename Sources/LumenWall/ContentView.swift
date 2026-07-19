import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var catalog: WallpaperCatalog
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var rotationManager: WallpaperRotationManager
    @EnvironmentObject private var favoriteWallpapers: FavoriteWallpapers
    @State private var selection: Wallpaper?
    @State private var showingSettings = false
    @State private var searchQuery = ""
    @State private var showingFavorites = false

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            HStack(spacing: 0) {
                sidebar
                    .fixedSize(horizontal: true, vertical: false)
                Divider().overlay(Color.primary.opacity(0.08))
                main
                    .frame(minWidth: 760)
            }
        }
        .task {
            searchQuery = catalog.searchText
            rotationManager.activate(catalog: catalog, wallpaperManager: wallpaperManager)
            if catalog.wallpapers.isEmpty { await catalog.load() }
        }
        .sheet(item: $selection) { WallpaperDetail(wallpaper: $0) }
        .sheet(isPresented: $showingSettings) { DownloadSettings() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) { AppLogo(size: 28); Text("LumenWall").font(.title3.weight(.bold)) }
            Text(t("探索", "Explore")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(WallpaperKind.allCases.filter { $0 != .dynamic }) { kind in
                Button { showingFavorites = false; catalog.selectedKind = kind } label: { Label(kind.displayName(for: appSettings.language), systemImage: kind == .dynamic ? "livephoto" : kind == .staticImage ? "photo" : "square.grid.2x2")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).padding(.horizontal, 10)
                    .background(!showingFavorites && catalog.selectedKind == kind ? Color.cyan.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8)) }
                .buttonStyle(.plain)
            }
            Button { showingFavorites = true } label: {
                Label(t("收藏", "Favorites"), systemImage: "heart.fill")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).padding(.horizontal, 10)
                    .background(showingFavorites ? Color.cyan.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
            Spacer()
            Button { showingSettings = true } label: { Label(t("设置", "Settings"), systemImage: "gearshape") }
                .buttonStyle(.plain).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                Text(t("你的显示器", "Your display")).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("MacBook Pro 14\"").font(.subheadline.weight(.medium))
                Text("\(catalog.display.label) · Retina").font(.caption).foregroundStyle(.secondary)
                Text(t("自动匹配高分辨率资源", "High-resolution matching")).font(.caption2).foregroundStyle(.cyan)
            }.padding(12).background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
        .padding(22).frame(width: 220).foregroundStyle(.primary)
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { VStack(alignment: .leading, spacing: 5) { Text(showingFavorites ? t("我的收藏", "My favorites") : t("今日灵感", "Today's inspiration")).font(.system(size: 28, weight: .bold)); Text(showingFavorites ? t("你收藏的壁纸会保存在这台 Mac 上", "Wallpapers you love, saved on this Mac") : t("为你的桌面挑一张足够清晰的壁纸", "Find a crisp wallpaper for your desktop")).foregroundStyle(.secondary) }; Spacer(); if !showingFavorites { Button { performSearch() } label: { Label(t("更新", "Refresh"), systemImage: "arrow.clockwise") }.buttonStyle(.bordered) } }
            if !showingFavorites { HStack(spacing: 12) {
                HStack(spacing: 6) {
                    NativeSearchField(text: $searchQuery, placeholder: t("搜索自然、城市、太空…", "Search nature, cities, space…"), onSubmit: performSearch)
                        .frame(minWidth: 220, idealWidth: 380, maxWidth: .infinity)
                }
                .layoutPriority(0)
                Menu {
                    ForEach(WallpaperSource.allCases) { source in
                        Button(source.displayName(for: appSettings.language)) { catalog.selectedSource = source; performSearch() }
                    }
                } label: { Label(catalog.selectedSource.displayName(for: appSettings.language), systemImage: "network") }
                    .buttonStyle(.bordered).fixedSize().layoutPriority(2)
                Button(t("搜索", "Search")) { performSearch() }.buttonStyle(.borderedProminent).fixedSize()
                Toggle(t("仅 4K+", "4K+ only"), isOn: $catalog.only4K).toggleStyle(.button).fixedSize()
                Menu { Button("MacBook Pro 14\"") { catalog.display = .macBook14 }; Button(t("4K 显示器", "4K display")) { catalog.display = .init(width: 3840, height: 2160, scale: 1) } } label: { Label(catalog.display.label, systemImage: "display") }.buttonStyle(.bordered).fixedSize()
            } }
            if !showingFavorites && catalog.isLoading {
                VStack(spacing: 14) {
                    ProgressView().controlSize(.large).tint(.cyan)
                    Text(t("正在搜索", "Searching") + " \(catalog.selectedSource.displayName(for: appSettings.language))…").font(.headline)
                    Text(t("正在匹配高分辨率壁纸", "Matching high-resolution wallpapers")).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            else if !showingFavorites, let error = catalog.errorMessage {
                ContentUnavailableView(t("暂时无法获取壁纸", "Wallpapers unavailable"), systemImage: "wifi.exclamationmark", description: Text(error))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            else if displayedWallpapers.isEmpty {
                ContentUnavailableView(showingFavorites ? t("还没有收藏壁纸", "No favorites yet") : t("没有匹配的壁纸", "No matching wallpapers"), systemImage: showingFavorites ? "heart" : "photo.on.rectangle.angled", description: Text(showingFavorites ? t("在壁纸预览中点亮爱心，它会出现在这里。", "Open a wallpaper preview and tap the heart to save it here.") : t("换一个关键词或关闭 4K 筛选。", "Try another keyword or turn off the 4K filter.")))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            else {
                GeometryReader { geometry in
                    ScrollView {
                        LazyVGrid(columns: wallpaperColumns(for: geometry.size.width), alignment: .leading, spacing: 18) {
                            ForEach(displayedWallpapers) { wallpaper in
                                WallpaperCard(wallpaper: wallpaper)
                                    .frame(minWidth: 0, maxWidth: .infinity)
                                    .onTapGesture { selection = wallpaper }
                                    .onAppear { Task { await catalog.loadMoreIfNeeded(for: wallpaper) } }
                            }
                            if !showingFavorites && catalog.canLoadMore {
                                HStack(spacing: 8) {
                                    if catalog.isLoadingMore { ProgressView().controlSize(.small) }
                                    Text(catalog.isLoadingMore ? t("正在加载更多壁纸…", "Loading more wallpapers…") : t("继续下滑，加载更多壁纸", "Scroll down to load more"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .gridCellColumns(3)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 14)
                                .id(catalog.loadMoreMarker)
                            }
                        }
                        .frame(minWidth: 0, maxWidth: .infinity)
                        .padding(.horizontal, 1)
                        .padding(.bottom, 8)
                    }
                }
            }
            HStack {
                Text(wallpaperManager.statusMessage ?? t("来源：\(catalog.selectedSource.displayName(for: appSettings.language)) · 每张壁纸均保留作者与许可信息", "Source: \(catalog.selectedSource.displayName(for: appSettings.language)) · Creator and license are retained"))
                    .font(.caption).foregroundStyle(wallpaperManager.statusMessage == nil ? Color.secondary : Color.cyan)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.primary)
    }

    private func wallpaperColumns(for availableWidth: CGFloat) -> [GridItem] {
        // LazyVGrid's flexible columns can retain a card's intrinsic width on macOS,
        // which makes long metadata visually overlap the adjacent column. Give every
        // column an explicit, equal width based on the scroll region instead.
        let spacing: CGFloat = 18
        let columnWidth = max(180, floor((availableWidth - spacing * 2) / 3))
        return Array(repeating: GridItem(.fixed(columnWidth), spacing: spacing), count: 3)
    }

    private var displayedWallpapers: [Wallpaper] {
        showingFavorites ? favoriteWallpapers.wallpapers : catalog.filteredWallpapers
    }

    private func performSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        catalog.searchText = query
        Task { await catalog.load() }
    }

    private func t(_ chinese: String, _ english: String) -> String { appSettings.text(chinese, english) }
}

private struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit)
        field.sendsSearchStringImmediately = false
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        if field.placeholderString != placeholder { field.placeholderString = placeholder }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        init(parent: NativeSearchField) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSSearchField else { return }
            parent.text = field.stringValue
        }
        @MainActor @objc func submit() { parent.onSubmit() }
    }
}

private struct AppLogo: View {
    let size: CGFloat
    var body: some View {
        // Do not use Bundle.module here. SwiftPM's generated Bundle.module accessor
        // asserts when its companion resource bundle is absent after a PKG install,
        // which turns a missing decorative image into an application-launch crash.
        // AppIcon.png is copied into the app bundle's Resources directory.
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: size * 0.23))
        } else {
            Image(systemName: "sparkles").foregroundStyle(.cyan)
        }
    }
}

private struct WallpaperCard: View {
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @EnvironmentObject private var appSettings: AppSettings
    let wallpaper: Wallpaper
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            AsyncImage(url: wallpaper.previewURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    Rectangle().fill(.white.opacity(0.08)).overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 10.0, contentMode: .fit)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(wallpaper.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            HStack {
                Text(wallpaper.resolution).lineLimit(1)
                Spacer(minLength: 4)
                if wallpaperManager.isDownloaded(wallpaper) {
                    Label(appSettings.text("已下载", "Downloaded"), systemImage: "checkmark.circle.fill").foregroundStyle(.cyan)
                }
                Button {
                    Task { await wallpaperManager.apply(wallpaper) }
                } label: {
                    Image(systemName: "desktopcomputer")
                }
                .buttonStyle(.borderless)
                .disabled(wallpaperManager.isApplying)
                .help(appSettings.text("下载 4K 优化版并设为壁纸", "Download 4K version and set as wallpaper"))
                Text(wallpaper.source.displayName(for: appSettings.language)).lineLimit(1)
            }
            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            .frame(minWidth: 0, maxWidth: .infinity)
        }
        .padding(9)
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button { Task { await wallpaperManager.apply(wallpaper) } } label: { Label(appSettings.text("下载 4K 优化版并设为壁纸", "Set as wallpaper"), systemImage: "desktopcomputer") }
            Button { NSWorkspace.shared.open(wallpaper.fullURL) } label: { Label(appSettings.text("下载原图", "Download original"), systemImage: "arrow.down.circle") }
        }
    }
}

private struct WallpaperDetail: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var favoriteWallpapers: FavoriteWallpapers
    let wallpaper: Wallpaper
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill").font(.title2).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(appSettings.text("关闭预览", "Close preview"))
            }
            AsyncImage(url: wallpaper.previewURL) { $0.image?.resizable().scaledToFit() }
                .frame(maxWidth: .infinity, minHeight: 300)
                .background(.black, in: RoundedRectangle(cornerRadius: 16))
            Text(wallpaper.title).font(.title2.bold())
            Text("\(wallpaper.resolution) · \(appSettings.text("静态壁纸", "Static wallpaper"))").foregroundStyle(.secondary)
            Divider()
            LabeledContent(appSettings.text("创作者", "Creator"), value: wallpaper.creator)
            LabeledContent(appSettings.text("许可证", "License"), value: wallpaper.license)
            HStack {
                Button(appSettings.text("查看来源与许可证", "View source and license")) { openURL(wallpaper.sourcePage) }
                Spacer()
                Button {
                    favoriteWallpapers.toggle(wallpaper)
                } label: {
                    Label(
                        favoriteWallpapers.contains(wallpaper) ? appSettings.text("已收藏", "Favorited") : appSettings.text("收藏", "Favorite"),
                        systemImage: favoriteWallpapers.contains(wallpaper) ? "heart.fill" : "heart"
                    )
                }
                .buttonStyle(.bordered)
                .tint(favoriteWallpapers.contains(wallpaper) ? .pink : nil)
                Button { Task { await wallpaperManager.apply(wallpaper) } } label: {
                    Label(wallpaperManager.isApplying ? appSettings.text("正在设置…", "Setting…") : appSettings.text("设为壁纸", "Set as wallpaper"), systemImage: "desktopcomputer")
                }
                .disabled(wallpaperManager.isApplying)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 650)
        .interactiveDismissDisabled(false)
    }
}

private struct DownloadSettings: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var wallpaperManager: WallpaperManager
    @EnvironmentObject private var appSettings: AppSettings
    @EnvironmentObject private var rotationManager: WallpaperRotationManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
            HStack { Text(appSettings.text("设置", "Settings")).font(.title2.bold()); Spacer(); Button(appSettings.text("完成", "Done")) { dismiss() }.keyboardShortcut(.defaultAction) }
            VStack(alignment: .leading, spacing: 8) {
                Text(appSettings.text("语言与外观", "Language & Appearance")).font(.subheadline.weight(.semibold))
                Picker(appSettings.text("语言", "Language"), selection: $appSettings.language) {
                    Text(appSettings.text("简体中文", "Chinese (Simplified)")).tag(AppLanguage.chinese)
                    Text("English").tag(AppLanguage.english)
                }
                .pickerStyle(.segmented)
                Picker(appSettings.text("外观", "Appearance"), selection: $appSettings.appearance) {
                    Text(appSettings.text("跟随系统", "System")).tag(AppAppearance.system)
                    Text(appSettings.text("浅色", "Light")).tag(AppAppearance.light)
                    Text(appSettings.text("深色", "Dark")).tag(AppAppearance.dark)
                }
                .pickerStyle(.segmented)
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            rotationSettings
            Text(appSettings.text("点击“设为壁纸”时，应用会先下载适配显示器的高质量版本（最高 4K）到下方目录，再将它应用到所有已连接的显示器。", "When setting a wallpaper, LumenWall downloads the best available version (up to 4K) to the folder below, then applies it to your displays."))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                Text(appSettings.text("默认保存位置", "Default download location")).font(.subheadline.weight(.medium))
                Text(wallpaperManager.directoryLabel).font(.caption).textSelection(.enabled).foregroundStyle(.secondary)
                Button(appSettings.text("更改位置…", "Change location…")) { wallpaperManager.chooseDownloadDirectory() }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            Toggle(appSettings.text("同步设置所有已连接显示器", "Sync all connected displays"), isOn: $wallpaperManager.applyToAllDisplays)
            Text(appSettings.text("将同步到 \(wallpaperManager.connectedDisplayCount) 个已连接显示器", "Will sync to \(wallpaperManager.connectedDisplayCount) connected display(s)"))
                .font(.caption.weight(.medium)).foregroundStyle(.cyan)
            Toggle(appSettings.text("同步所有虚拟桌面（Spaces）", "Sync all virtual desktops (Spaces)"), isOn: $wallpaperManager.applyToAllSpaces)
            Text(appSettings.text("启用后，切换到桌面 1、桌面 2 等任一虚拟桌面时，应用会立即将当前选择的图片重新应用；不会修改系统的私有壁纸配置。", "When enabled, the selected image is reapplied whenever you switch Spaces. LumenWall does not modify macOS private wallpaper data."))
                .font(.caption).foregroundStyle(.secondary)
            Text(wallpaperManager.applyToAllDisplays ? appSettings.text("设为壁纸时，所有已连接显示器将使用同一张图片。macOS 不提供为不同虚拟桌面分别设图的公开 API。", "All connected displays use the same image. macOS has no public API for different images per Space.") : appSettings.text("设为壁纸时，仅设置当前主显示器。", "Only the main display is updated."))
                .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(width: 520, height: 700)
    }

    private var rotationSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(appSettings.text("随机定时更换壁纸", "Rotate wallpapers automatically"), isOn: $rotationManager.isEnabled)
                .font(.headline)
                HStack {
                    Text(appSettings.text("图片来源", "Image sources"))
                    Spacer()
                    Button(appSettings.text("全选", "Select all")) { rotationManager.selectAllSources() }
                        .buttonStyle(.borderless)
                }
                ForEach(WallpaperSource.allCases.filter { $0 != .all }) { source in
                    Toggle(source.displayName(for: appSettings.language), isOn: Binding(
                        get: { rotationManager.selectedSources.contains(source) },
                        set: { _ in rotationManager.toggleSource(source) }
                    ))
                    .toggleStyle(.checkbox)
                }
            Picker(appSettings.text("更换间隔", "Interval"), selection: $rotationManager.interval) {
                Text(appSettings.text("30 分钟", "30 minutes")).tag(WallpaperRotationInterval.thirtyMinutes)
                Text(appSettings.text("1 小时", "1 hour")).tag(WallpaperRotationInterval.oneHour)
                Text(appSettings.text("2 小时", "2 hours")).tag(WallpaperRotationInterval.twoHours)
                Text(appSettings.text("自定义", "Custom")).tag(WallpaperRotationInterval.custom)
            }
            if rotationManager.interval == .custom {
                HStack {
                    Text(appSettings.text("自定义分钟", "Custom minutes"))
                    TextField("30–1440", value: $rotationManager.customMinutes, format: .number)
                        .frame(width: 100)
                    Text(appSettings.text("分钟（30–1440）", "minutes (30–1440)"))
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Button {
                    Task { await rotationManager.rotateNow() }
                } label: {
                    Label(rotationManager.isRotating ? appSettings.text("正在更换…", "Rotating…") : appSettings.text("立即随机更换", "Rotate now"), systemImage: "shuffle")
                }
                .disabled(rotationManager.isRotating)
                Spacer()
                if let date = rotationManager.nextRotationDate, rotationManager.isEnabled {
                    Text(appSettings.text("下次：", "Next: ") + date.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Text(appSettings.text("定时更换仅在 LumenWall 保持运行时生效。应用完全退出后不会在后台唤醒。", "Rotation runs while LumenWall remains open. It does not wake the app after it has fully quit."))
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}
