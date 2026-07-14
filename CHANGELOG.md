# Changelog

本项目的所有重要变更都会记录在此文件中。

格式参考 [Keep a Changelog 1.1.0](https://keepachangelog.com/zh-CN/1.1.0/)，版本号遵循 [Semantic Versioning 2.0.0](https://semver.org/lang/zh-CN/)。

## [Unreleased]

### Changed

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

[Unreleased]: https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/compare/v0.1.0-beta.1...HEAD
[0.1.0-beta.1]: https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/releases/tag/v0.1.0-beta.1
