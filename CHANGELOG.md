# Changelog

本项目的所有重要变更都会记录在此文件中。

格式参考 [Keep a Changelog 1.1.0](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning 2.0.0](https://semver.org/lang/zh-CN/)。

## [Unreleased]

## [0.1.0-beta.6.2] - 2026-07-17

### Added

- 设置中新增“显示数据详细时间”开关，默认开启；关闭后恢复 `YYYY-MM-DD · AM/PM` 简洁格式。

### Changed

- 弹窗默认以 `YYYY-MM-DD · HH:mm:ss` 24 小时制展示 Codex 雷达数据时间，同时隐藏 ISO 8601 中的 `T` 和时区偏移。

## [0.1.0-beta.6.1] - 2026-07-17

### Fixed

- 兼容 Codex 雷达将测试日期改为 ISO 8601 时间戳的数据格式变化，弹窗仍统一显示为 `YYYY-MM-DD · AM/PM`，不再暴露秒数和时区偏移。

## [0.1.0-beta.6] - 2026-07-17

### Changed

- 菜单栏弹窗不再强调本地“数据已更新”和获取时间，改为高亮展示 Codex 雷达网站实际提供的最新测试日期。
- 测试日期统一格式化为 `YYYY-MM-DD · AM/PM`，让数据时效性更容易识别。

## [0.1.0-beta.5] - 2026-07-15

### Added

- 新增菜单栏左侧图标开关，可进一步减少横向占用。
- 新增模型简称二级设置页，可为每个模型分别配置仅在菜单栏生效的简称。

### Changed

- 菜单栏改为按实际图标、名称、序号与数值内容自适应宽度，移除右侧硬编码留白并缩小内部间距。
- 菜单栏弹窗改为按内容自适应高度；仅在超过当前屏幕可用区域或 760pt 上限时滚动。

### Fixed

- 简称二级设置页使用独立页头与返回操作，修复返回按钮被错误提升为大型标签工具栏项、无法正常返回首页的问题，并支持按 Esc 返回。

## [0.1.0-beta.4] - 2026-07-14

### Fixed

- 关闭“显示展开面板趋势图”后，菜单栏弹窗会自动缩短，不再在四组榜单下方保留大面积空白。
- 弹窗已打开时切换趋势图设置，SwiftUI 内容与 AppKit 弹窗尺寸会立即同步；重新开启趋势图仍恢复完整高度。

## [0.1.0-beta.3] - 2026-07-14

修复 beta.2 安装包的启动与安装界面回归。

### Fixed

- 将应用 Core 静态链接进主程序，修复 ad-hoc 签名与 Hardened Runtime 组合下被 macOS Library Validation 终止、点击应用后无菜单栏图标的问题。
- 恢复 DMG 的引导背景、应用与 Applications 图标位置，同时保留首次打开说明。
- 统一正式归档与便携构建的 DMG 打包入口，新增安装布局、静态依赖及三秒真实启动检查，防止同类回归再次进入 Release。

## [0.1.0-beta.2] - 2026-07-14

第二个公开预发布版本，重点优化菜单栏展开面板与综合排名权重设置。

> [!WARNING]
> 此版本的 DMG 存在启动失败和安装引导布局缺失问题，请改用 `v0.1.0-beta.3` 或更高版本。

### Added

- 新增“显示展开面板趋势图”设置，可按需隐藏菜单栏展开后的趋势图；升级后默认保持显示。

### Changed

- 将三个独立权重输入框改为三段式双滑块，三项权重始终合计 100%，拖动时立即保存并重新计算综合排名。
- 权重滑块新增颜色区分、实时百分比与辅助功能增减操作，并保留 50 / 25 / 25 一键恢复。
- README 新增真实应用截图、未公证构建的安全警告说明及 Apple 官方首次打开步骤。

## [0.1.0-beta.1] - 2026-07-14

首个附带可下载安装包的公开预发布版本。

### Added

- 新增四类模型榜单：智商、费用、耗时和自定义权重综合排名。
- 新增两行菜单栏榜单，支持四种序号样式、详细数值开关和动态宽度。
- 新增榜单展开交互，可查看前五名，并在紧凑摘要与四宫格之间切换。
- 新增趋势图、离线快照、HTTP 缓存验证器、自动刷新和单次请求合并。
- 新增综合排名权重、登录时启动及刷新间隔设置。
- 新增 macOS 26 Liquid Glass 样式和 macOS 14–15 兼容材质。
- 换用雷达、Codex 徽章和终端符号组成的新应用图标，并完善 DMG 窗口视觉。
- 提供 Universal 2 便携 DMG、SHA-256 校验文件和首次打开指引。

### Fixed

- 修复费用等边界值的浮点舍入不稳定问题。
- 修复加权综合排名在稳定版 Swift 工具链中的兼容性问题。
- 修复测试夹具在 Xcode 测试包中无法可靠定位的问题。
- 修复离线或请求失败时已有榜单被清空的问题。

## 0.1.0-alpha.3 - 2026-07-13

内部测试版本，不提供安装包。

### Added

- 完成菜单栏弹窗、四榜单、趋势图和设置界面。
- 新增自定义权重、自动刷新间隔和登录时启动。

### Fixed

- 完善空数据、网络错误和缓存过期状态的界面反馈。

## 0.1.0-alpha.2 - 2026-07-13

内部测试版本，不提供安装包。

### Added

- 新增刷新调度、磁盘快照缓存和菜单栏状态管理。
- 新增离线保留上次成功数据与并发刷新合并。

### Fixed

- 修复请求失败后状态无法正确恢复的问题。

## 0.1.0-alpha.1 - 2026-07-13

内部测试版本，不提供安装包。

### Added

- 搭建 Swift Package、XcodeGen 工程和 macOS 菜单栏应用骨架。
- 实现 Codex 雷达 JSON 解码、四类排名和基础格式化。

### Fixed

- 完善缺失指标、未知字段和并列排名的容错行为。

[Unreleased]: https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/compare/v0.1.0-beta.6.2...HEAD
[0.1.0-beta.6.2]: https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/compare/v0.1.0-beta.6.1...v0.1.0-beta.6.2
[0.1.0-beta.6.1]: https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/compare/v0.1.0-beta.6...v0.1.0-beta.6.1
[0.1.0-beta.6]: https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/compare/v0.1.0-beta.5...v0.1.0-beta.6
[0.1.0-beta.5]: https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/compare/v0.1.0-beta.4...v0.1.0-beta.5
[0.1.0-beta.4]: https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/releases/tag/v0.1.0-beta.4
[0.1.0-beta.3]: https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/releases/tag/v0.1.0-beta.3
[0.1.0-beta.2]: https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/releases/tag/v0.1.0-beta.2
[0.1.0-beta.1]: https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/releases/tag/v0.1.0-beta.1
