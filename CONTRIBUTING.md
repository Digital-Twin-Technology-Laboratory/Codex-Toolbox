# Contributing

1. 使用 macOS 14+ 和 Swift 6 工具链保持核心代码兼容。
2. 修改 `project.yml` 后运行 `xcodegen generate`，并一起提交生成的 Xcode 工程。
3. 在提交前运行 `swift run CoreVerification` 和完整 Xcode 单元测试。
4. 数据模型必须容错；新字段不得让旧快照无法读取。
5. Token 数据源必须保持只读；重置卡客户端只允许 `account/rateLimits/read`，不得引入 consume 请求或 opaque ID 持久化。
6. 不要加入分析 SDK、账号凭据或 HTML 抓取。
7. 不要将 PKG、DMG、Developer ID 证书、公证凭据或用户数据提交到仓库。
8. 用户可见变更应加入 `CHANGELOG.md` 的 Unreleased 区段；发布版本只在 `Sources/CodexToolbox/Config/Version.xcconfig` 中维护。

版本号、构建号、标签与 Release 流程见 [docs/releasing.md](docs/releasing.md)。公开发布与数据使用必须遵守 [docs/data-source.md](docs/data-source.md) 中的归属与授权说明。
