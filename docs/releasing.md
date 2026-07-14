# 发布指南

Show Codex IQ 使用 [Semantic Versioning 2.0.0](https://semver.org/) 和 `v<版本号>` Git 标签。用户可见变更记录在根目录的 `CHANGELOG.md`，分类采用 Added、Changed、Deprecated、Removed、Fixed 和 Security。

## 版本字段

唯一版本配置位于 `Sources/ShowCodexIQ/Config/Version.xcconfig`：

- `SHOW_CODEX_IQ_RELEASE_VERSION`：完整 SemVer，例如 `0.2.0-beta.1` 或 `1.0.0`。
- `MARKETING_VERSION`：Apple `CFBundleShortVersionString`，只保留数字核心，例如 `0.2.0`。
- `CURRENT_PROJECT_VERSION`：Apple `CFBundleVersion`，每次构建发布都必须递增的正整数。

预发布阶段依次使用 `alpha.N`、`beta.N`、`rc.N`。`0.y.z` 表示公开接口仍可能变化；稳定公开接口从 `1.0.0` 开始。已经发布的版本不得覆盖附件或重写标签，任何修改都发布为新版本。

## 每次发布

1. 在 `Version.xcconfig` 中更新完整版本、数字核心和构建号。
2. 将 `CHANGELOG.md` 的 Unreleased 内容整理到带 ISO 日期的新版本标题下，并更新底部比较链接。
3. 重新生成工程并检查版本配置：

   ```bash
   xcodegen generate
   bash scripts/version.sh
   ```

4. 运行验证与测试：

   ```bash
   swift run CoreVerification
   swift test
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
     xcodebuild -project ShowCodexIQ.xcodeproj -scheme ShowCodexIQ \
     -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
   ```

5. 构建并校验 DMG。正式归档优先使用 `scripts/build_dmg.sh`；没有完整 Xcode 归档环境时，可使用 `scripts/build_portable_dmg.sh` 生成验证构建。
6. 提交发布变更，创建与完整版本一致的带注释标签并推送：

   ```bash
   git commit -m "chore(release): v0.2.0"
   git tag -a v0.2.0 -m "Show Codex IQ v0.2.0"
   git push origin main --follow-tags
   ```

7. 从对应的 `CHANGELOG.md` 章节编写 GitHub Release 说明，并上传 DMG 与 `.sha256`。预发布版本需要勾选 Pre-release：

   ```bash
   gh release create v0.2.0 \
     dist/Show-Codex-IQ-0.2.0-universal.dmg \
     dist/Show-Codex-IQ-0.2.0-universal.dmg.sha256 \
     --title "Show Codex IQ v0.2.0" \
     --notes-file /path/to/release-notes.md
   ```

8. 打开 Release 页面，确认版本标题、说明、附件、校验值和下载链接均正确。发布后立即将 `CHANGELOG.md` 恢复为新的空 Unreleased 区段。

内部测试版本可以只记录在 `CHANGELOG.md`，不创建 GitHub Release，也不附安装包。自 `v0.1.0-beta.1` 起，每个面向用户的版本都必须有对应标签、Release、更新说明、DMG 和 SHA-256 文件。
