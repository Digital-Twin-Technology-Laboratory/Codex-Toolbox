# Codex Toolbox 发布指南

Codex Toolbox 使用 Semantic Versioning 和 `v<版本号>` 注释标签。v1.0.0 及以后只发布普通 GitHub Release，不标记 Pre-release。

## 版本与固定附件名

唯一版本源是 `Sources/CodexToolbox/Config/Version.xcconfig`：

- `CODEX_TOOLBOX_RELEASE_VERSION`：完整 SemVer。
- `MARKETING_VERSION`：`CFBundleShortVersionString` 的数字核心。
- `CURRENT_PROJECT_VERSION`：单调递增的正整数构建号。

v1.0.0 附件固定为：

```text
Codex-Toolbox-1.0.0-universal.pkg
Codex-Toolbox-1.0.0-universal.pkg.sha256
```

## 发布门禁

下列条件任一未满足都不得发布：

- `swift test`、`swift run CoreVerification` 和完整 Xcode 测试通过。
- Release 应用是 arm64 + x86_64 Universal 2，CodexToolboxCore 保持静态链接。
- 应用使用 Developer ID Application 签名并开启 Hardened Runtime。
- PKG 使用 Developer ID Installer 签名。
- Apple 公证成功，ticket 已 staple，`spctl --type install` 通过。
- PKG 实际验证了 Bundle ID、版本、双架构、签名、安装脚本与 SHA-256。
- 从最后一个 Show Codex IQ beta 升级后，只留下一个 Codex Toolbox，设置、榜单缓存与登录启动正常继承。
- README、CHANGELOG、真实截图和 `docs/releases/v1.0.0.md` 与产物一致。
- GitHub 仓库名为 `Digital-Twin-Technology-Laboratory/Codex-Toolbox`，本地 `origin` 指向新 URL。

## 构建与测试

```bash
xcodegen generate
bash scripts/version.sh

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swift test \
  --scratch-path /tmp/codex-toolbox-spm

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcrun --toolchain com.apple.dt.toolchain.XcodeDefault swift run \
  --scratch-path /tmp/codex-toolbox-spm CoreVerification

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
TOOLCHAINS=com.apple.dt.toolchain.XcodeDefault \
xcodebuild -project CodexToolbox.xcodeproj -scheme CodexToolbox \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

没有证书时可运行 `bash scripts/build_pkg.sh` 生成本地测试 PKG。它使用 ad-hoc 应用签名和未签名安装器，仅用于验证打包结构，不能作为 Release 附件。

## Developer ID 签名、公证与 staple

先把 Developer ID Application、Developer ID Installer 证书导入钥匙串，再使用 `notarytool store-credentials` 创建钥匙串 profile。不要在仓库或 shell 历史中保存密码、API key 或 P8 内容。

```bash
APP_SIGN_IDENTITY='Developer ID Application: Team Name (TEAMID)' \
INSTALLER_SIGN_IDENTITY='Developer ID Installer: Team Name (TEAMID)' \
bash scripts/build_pkg.sh

REQUIRE_DISTRIBUTION_SIGNATURE=1 \
bash scripts/verify_pkg.sh dist/Codex-Toolbox-1.0.0-universal.pkg

NOTARY_PROFILE='codex-toolbox-notary' \
bash scripts/notarize_pkg.sh dist/Codex-Toolbox-1.0.0-universal.pkg
```

`notarize_pkg.sh` 会等待公证结果、staple ticket、验证 ticket、运行 `spctl --assess --type install`，然后重新生成 SHA-256。任一步失败即终止。

## 提交、标签与普通 Release

1. 提交全部源码、文档和生成工程，保持 `dist/` 不入 Git。
2. 在签名、公证、升级 VM 和系统兼容矩阵全部通过后，才允许执行：

   ```bash
   ALLOW_GITHUB_RELEASE=YES bash scripts/release_github.sh
   ```

3. 脚本会重新执行签名、staple 和 Gatekeeper 门禁，确认本地 `main` 与 `origin/main` 没有分叉，推送 `main`，创建签名注释标签 `v1.0.0`，并创建不带 `--prerelease` 的普通 GitHub Release。

已发布的标签与附件不得覆盖；任何修复使用新版本号。
