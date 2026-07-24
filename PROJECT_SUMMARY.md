# LumenWall 项目概览

## 基本信息

| 项目 | 内容 |
| --- | --- |
| 名称 | LumenWall |
| 类型 | 原生 SwiftUI macOS 静态壁纸应用 |
| 当前版本 | 0.1.21 |
| 最低系统版本 | macOS 14 |
| 技术栈 | Swift 6、SwiftUI、AppKit、Swift Package Manager |
| 仓库 | https://github.com/vwin/Mac-wallpaper |
| 最新发布 | 待发布：0.1.21 |

## 产品能力

- 聚合搜索：全部来源、必应中国、360 壁纸（4K）、Wallhaven、Wikimedia Commons。
- 高清筛选与适配：支持 4K+ 筛选，以及 MacBook Pro 14 英寸和 4K 显示器匹配。
- 本地缓存与分页：优先读取缓存，并支持持续下滑加载更多结果。
- 壁纸操作：预览、下载、选择默认下载目录、设置主显示器或全部已连接显示器。
- 收藏：预览页点亮爱心收藏，左侧“收藏”页浏览本地收藏。
- 定时随机更换：可多选图片来源，支持 30 分钟、1 小时、2 小时或自定义 30–1440 分钟。
- 虚拟桌面与菜单栏：支持在切换 Spaces 时重新应用当前壁纸；关闭窗口后仍可通过菜单栏收藏当前 LumenWall 壁纸、随机换图与调整定时任务。
- 国际化与外观：简体中文/English，以及跟随系统、浅色、深色模式。

## 关键源码

| 文件 | 职责 |
| --- | --- |
| `Sources/LumenWall/ContentView.swift` | 主界面、搜索、预览、收藏与设置入口 |
| `Sources/LumenWall/WallpaperCatalog.swift` | 多来源搜索、聚合、分页与筛选 |
| `Sources/LumenWall/WallpaperCatalogCache.swift` | 搜索结果本地缓存 |
| `Sources/LumenWall/WallpaperManager.swift` | 下载、文件命名与设置 macOS 壁纸 |
| `Sources/LumenWall/WallpaperRotationManager.swift` | 定时随机更换与系统唤醒补偿 |
| `Sources/LumenWall/FavoriteWallpapers.swift` | 本地收藏持久化 |
| `Sources/LumenWall/AppSettings.swift` | 语言、主题、下载目录和应用偏好 |

## 构建、测试与发布

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
```

- 正式安装包以 GitHub Release 附件形式发布；当前包为 `LumenWall-0.1.21-installer.pkg`。
- 打包前必须使用独立、干净的构建目录，禁止复用未知来源的旧 `.build` 产物。
- 完整的构建、回归、提交与发布约束见根目录 [AGENTS.md](AGENTS.md)。

## 约束与注意事项

- 当前仅支持静态壁纸。
- macOS 公共 API 不支持为每个虚拟桌面永久保存不同的壁纸；应用会在切换 Space 后重新应用当前选图。
- 随机定时更换要求应用保持运行；关闭窗口不会退出，完全退出后系统不会自动唤醒该任务。
- 图片版权及许可证归各数据来源与作者所有，应以应用内来源页和许可信息为准。
