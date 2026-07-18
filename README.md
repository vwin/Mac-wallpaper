# LumenWall

macOS 壁纸应用第一版。运行 `swift run LumenWall`。

若系统仍指向旧版 Command Line Tools，则在当前终端使用已安装 Xcode：

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift run LumenWall
```

开发构建会同时生成标准应用包：`.build/LumenWall.app`。请通过 Finder 或
`open .build/LumenWall.app` 启动，而非直接打开裸可执行文件，以确保输入法和系统服务正常工作。

## 已完成

- 面向 MacBook Pro 14 英寸（3024 × 1964 Retina）的默认显示器档案，并可切换至 4K；资源筛选以 4K 优先。
- 搜索、静态/动态分类入口、壁纸网格、预览详情、分辨率、作者、许可与原图下载入口。
- 使用 Wikimedia Commons API：无 API Key、可分页检索、持续更新；展示创作者和许可证，保留来源页。
- 动态壁纸在数据模型、导航和 UI 中预留类型；下一阶段接入 HEIC/video 素材、下载缓存和多显示器设定。

## 下一步（Widget 阶段）

1. 增加本地资源库、收藏、下载进度与磁盘配额。
2. 通过 `NSWorkspace` 设置静态壁纸，结合屏幕实际尺寸选择最合适源图。
3. 接入经授权的动态 HEIC / 视频资源与播放、节能策略。
4. 新增 WidgetKit：每日精选、收藏轮播和一键换图。

## 数据源说明

Wikimedia Commons 的 MediaWiki API 可搜索和读取媒体文件；实际每张作品的许可不同，因此应用始终展示来源和许可证。发布前应加入缓存、速率限制、用户代理，以及许可证/敏感内容审核策略。
