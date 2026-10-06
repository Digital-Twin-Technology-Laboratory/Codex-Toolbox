# Codex Toolbox 发布指南

Codex Toolbox 使用 Semantic Versioning 和 `v<版本号>` 注释标签。v1.0.0 及以后只发布普通 GitHub Release，不标记 Pre-release。

## 版本与固定附件名

唯一版本源是 `Sources/CodexToolbox/Config/Version.xcconfig`：

- `CODEX_TOOLBOX_RELEASE_VERSION`：完整 SemVer。
- `MARKETING_VERSION`：`CFBundleShortVersionString` 的数字核心。
- `CURRENT_PROJECT_VERSION`：单调递增的正整数构建号。
- `SPARKLE_PUBLIC_ED_KEY`：可公开提交的 Sparkle Ed25519 公钥；对应私钥只保存在发布者钥匙串或离线备份中。

v1.4.0 附件固定为：

```text
Codex-Toolbox-1.4.0-universal.pkg
Codex-Toolbox-1.4.0-universal.pkg.sha256
Codex-Toolbox-1.4.0-universal.dmg
Codex-Toolbox-1.4.0-universal.dmg.sha256
appcast.xml
```

## 候选版准备与正式发布

1.4.0 正式构建为 Build 58，于 2026-10-05 按用户明确指令发布。发布沿用 `codex/1.4.0` 已通过本地及远端 CI 验证的源码和签名公证产物；原始候选附件保存在 `dist/candidates/1.4.0-build58/`。证据见 [准备记录](verification/v1.4.0-release-readiness.md)。

准备阶段仅提交、推送候选分支，生成本地签名公证附件和 Appcast；不创建 `v1.4.0` 标签或公开 Release，不上传更新源。用户明确下达发布指令后再执行正式流程。

用户自行安装和界面验收时，可对构建、公证与验证命令设置 `SKIP_APP_LAUNCH_VERIFICATION=1`；此开关只跳过真实应用启动，不跳过签名、公证、版本、架构和包内容检查。记录中必须注明实际安装、启动及兼容性验收尚未由自动化验证。

## 发布门禁

下列条件任一未满足都不得发布：

- `swift test`、`swift run CoreVerification` 和完整 Xcode 测试通过。
- Release 应用是 arm64 + x86_64 Universal 2，CodexToolboxCore 保持静态链接。
- 应用使用 Developer ID Application 签名并开启 Hardened Runtime。
- PKG 使用 Developer ID Installer 签名。
- DMG 内应用与 DMG 使用 Developer ID Application 签名。
- Sparkle framework、Updater、Autoupdate 和 XPC helper 均使用同一 Developer ID Application 身份从内到外重签，Downloader entitlement 保持不变。
- PKG 和 DMG 的 Apple 公证均成功，ticket 已 staple，对应 Gatekeeper 检查通过。
- `appcast.xml` 使用项目专用 Ed25519 密钥签署，下载 URL 指向当前不可变版本的 GitHub Release DMG。
- PKG 实际验证了 Bundle ID、版本、双架构、签名、安装脚本与 SHA-256。
- `codex-rate-card-v1.json` 与 `api-price-card-v1.json` 必须先随源码到达远端 `main`，两个 GitHub Raw 地址返回 200 且内容与发布提交一致。
- 从最后一个 Show Codex IQ beta 升级后，只留下一个 Codex Toolbox，设置、榜单缓存与登录启动正常继承。
- DMG 背景、内附说明和 Release Notes 均明确要求升级用户先删除 `Show Codex IQ.app`。
- README、CHANGELOG、真实截图和 `docs/releases/v1.4.0.md` 与产物一致。
- GitHub 仓库名为 `Digital-Twin-Technology-Laboratory/Codex-Toolbox`，本地 `origin` 指向新 URL。

## 构建与测试

```bash
bash scripts/test_all.sh
```

该入口固定在 `/private/tmp` 内生成 SwiftPM 与 Xcode 测试产物，并在退出时终止、注销和删除临时 Debug 应用，避免 Spotlight 或 LaunchServices 把它暴露为第二个 Codex Toolbox。需要真实界面验收时，必须安装本轮 PKG 替换 `/Applications/Codex Toolbox.app`，不得直接运行 `DerivedData/Build/Products` 中的 `.app`。

本地真实安装验收使用 `bash scripts/build_local_test_pkg.sh`。该入口强制 Developer ID Application/Installer 签名、嵌套 Team ID 一致性校验和包内应用启动烟雾测试；不执行公证、staple、appcast 或发布。`build_pkg.sh` 不再自动退回 ad-hoc 签名，避免 Hardened Runtime 下的 Sparkle Team ID 不匹配产物通过静态校验。

## Developer ID 签名、公证与 staple

先把 Developer ID Application、Developer ID Installer 证书导入钥匙串，再使用 `notarytool store-credentials` 创建钥匙串 profile。不要在仓库或 shell 历史中保存密码、API key 或 P8 内容。

```bash
APP_SIGN_IDENTITY='Developer ID Application: Team Name (TEAMID)' \
INSTALLER_SIGN_IDENTITY='Developer ID Installer: Team Name (TEAMID)' \
bash scripts/build_pkg.sh

APP_SIGN_IDENTITY='Developer ID Application: Team Name (TEAMID)' \
bash scripts/build_dmg.sh

REQUIRE_DISTRIBUTION_SIGNATURE=1 \
bash scripts/verify_pkg.sh dist/Codex-Toolbox-1.4.0-universal.pkg

NOTARY_PROFILE='codex-toolbox-notary' \
bash scripts/notarize_pkg.sh dist/Codex-Toolbox-1.4.0-universal.pkg

NOTARY_PROFILE='codex-toolbox-notary' \
bash scripts/notarize_dmg.sh dist/Codex-Toolbox-1.4.0-universal.dmg
```

`notarize_pkg.sh` 和 `notarize_dmg.sh` 会分别等待公证结果、staple ticket、验证 ticket、运行对应 `spctl` 检查，然后重新生成 SHA-256。任一步失败即终止。

## Sparkle 更新签名

项目使用钥匙串账户 `Digital-Twin-Technology-Laboratory.Codex-Toolbox`。首次在新的发布机上配置时，应从安全备份导入既有私钥，禁止生成另一把密钥覆盖公钥：

```bash
SPARKLE_BIN=/path/to/Sparkle/bin
"$SPARKLE_BIN/generate_keys" \
  --account Digital-Twin-Technology-Laboratory.Codex-Toolbox \
  -f /secure/offline/location/codex-toolbox-sparkle-private-key
```

当前发布机上的私钥可用 `generate_keys -x` 导出到离线加密介质。导出文件等同于签名凭据，不得放进仓库、云盘或 shell 历史。

签名、公证并 staple DMG 后，可单独验证 appcast 生成：

```bash
bash scripts/generate_appcast.sh \
  dist/Codex-Toolbox-1.4.0-universal.dmg
```

正式的 `release_github.sh` 会自动执行这一步，并把 `appcast.xml` 与 PKG、DMG、SHA-256 一起上传。应用固定读取 `releases/latest/download/appcast.xml`，appcast 内的 DMG 地址则固定到 `releases/download/v<版本>/...`，已发布附件不得覆盖。

## 提交、标签与普通 Release

1. 提交全部源码、文档和生成工程，保持 `dist/` 不入 Git。
2. 在签名、公证、升级 VM 和系统兼容矩阵全部通过后，才允许执行：

   ```bash
   ALLOW_GITHUB_RELEASE=YES bash scripts/release_github.sh
   ```

3. 脚本会重新执行 PKG 与 DMG 的签名、staple 和 Gatekeeper 门禁，生成 Ed25519 签名 appcast，确认本地 `main` 与 `origin/main` 没有分叉，推送 `main`，验证两个远端价格清单已可读取且与本地一致，再创建注释标签 `v1.4.0`，并上传两种格式、各自校验和与 `appcast.xml`，创建不带 `--prerelease` 的普通 GitHub Release。

已发布的标签与附件不得覆盖；任何修复使用新版本号。

## 1.4.1 / Build 63 准备状态

最终候选的验证与限制见 [最终审查](verification/v1.4.1-final-audit.md)。准备的附件为 `Codex-Toolbox-1.4.1-universal.pkg`、`.pkg.sha256`、`Codex-Toolbox-1.4.1-universal.dmg`、`.dmg.sha256` 和 `appcast.xml`。公开发布须在用户手动验收并明确授权后，从最终提交的干净 main checkout 执行。既有工作区用户未跟踪文件不应删除。

1.4.1 四类公共数据直接读取数据服务。两个 GitHub 价格文件继续作为旧版本兼容镜像；发布脚本检查网站快照保留所有内置历史。接口成功不等于上游数据更新，实际状态以后台源日期和诊断为准。

## 对外发布文案

发布页、更新日志、README 和应用内更新说明统一描述稳定的数据接口、动态调整及减少软件更新适配，不写部署归属或具体域名。现有协议范围内的数据和来源调整无需客户端更新；新的原生能力或协议变更仍按正常版本发布。GitHub 发布说明与 appcast 内嵌说明应同步核对。
