<div align="center">
  <img src="design/icon-concepts/codex-radar-terminal-b-preview.png" width="160" alt="Show Codex IQ 应用图标">
  <h1>Show Codex IQ</h1>
  <p>在 macOS 菜单栏快速查看 Codex 模型的智商、费用、耗时与综合排名。</p>

  [![GitHub Release](https://img.shields.io/github/v/release/Digital-Twin-Technology-Laboratory/Show-Codex-IQ?include_prereleases&sort=semver)](https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/releases)
  [![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple)](https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ#系统要求)
  [![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
</div>

Show Codex IQ 是一款原生 macOS 菜单栏应用。它读取 Codex 雷达的公开快照，把不同模型与推理强度的表现整理为四类榜单，并在本地保留最近一次成功数据，方便快速比较。

> [!IMPORTANT]
> 本项目与 OpenAI、Codex 雷达均无官方隶属关系。数据来自 [codexradar.com](https://codexradar.com/)，公开分发或二次开发前请阅读[数据来源与授权说明](docs/data-source.md)。

## 应用预览

<p align="center">
  <img src="docs/assets/screenshots/dashboard.png" width="430" alt="Show Codex IQ 菜单栏仪表盘，展示智商、费用、耗时、综合排名与趋势图">
</p>

<p align="center"><sub>菜单栏仪表盘：快速查看四类排名、数据状态与近期趋势。</sub></p>

## 功能亮点

- 菜单栏用两行紧凑展示前两名，可切换智商、综合、费用或耗时指标。
- 序号支持隐藏、`#1`、`1.`、`1、` 四种样式，并可选择是否显示详细数值。
- 弹窗展示四组前三榜单；点击卡片可展开前五名，其余榜单自动收为摘要。
- 模型名称支持悬停查看全名，趋势图使用 Swift Charts 绘制并可在设置中隐藏。
- macOS 26+ 使用原生 Liquid Glass，macOS 14–15 自动回退为系统材质。
- 启动时优先加载最后一次成功快照；离线或请求失败时不清空现有排名。
- 默认每 30 分钟自动刷新，支持 15 / 30 / 60 / 120 / 240 分钟或关闭自动刷新。
- 综合排名使用三段式双滑块调节整数权重，三项始终合计 100%；默认智商 50%、费用 25%、耗时 25%。
- 支持登录时启动，不含分析 SDK，不收集个人信息或账号凭据。

## 安装

1. 前往 [Releases](https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/releases) 下载最新 DMG 和对应的 `.sha256` 文件。
2. 打开 DMG，将 **Show Codex IQ** 拖入 **Applications**。
3. 从“应用程序”启动。应用只显示在菜单栏，不会出现在程序坞中。

### 首次打开时的安全警告

> [!IMPORTANT]
> 首次启动时，macOS 可能提示“Apple 无法检查 App 是否包含恶意软件”。这是因为维护者目前没有付费的 Apple Developer Program 账户，发布包只能使用 ad-hoc 签名，无法获得 Developer ID 签名及 Apple 公证。

该提示表示 Gatekeeper 无法验证发布者身份与公证记录，**不等同于 macOS 已检测到恶意软件**。当前源码不包含分析、广告或遥测 SDK，不收集个人信息、个人文件或账号凭据；应用的网络访问仅用于获取公开排名数据。项目代码完全公开，欢迎在安装前审查源码或自行构建。

仅当安装包下载自本项目的官方 [GitHub Releases](https://github.com/Digital-Twin-Technology-Laboratory/Show-Codex-IQ/releases)，并且校验值一致时，按以下步骤放行：

1. 在“应用程序”中打开 **Show Codex IQ**；出现警告后关闭提示。
2. 打开“系统设置 → 隐私与安全性”。
3. 向下滚动至“安全性”，点击 **仍要打开**。该按钮通常会在尝试启动后的约一小时内显示。
4. 再次点击 **打开**，并按提示使用登录密码或 Touch ID 确认。

完成后，系统会把该应用保存为例外，后续可正常启动。具体说明请参阅 [Apple 官方文档：通过覆盖安全性设置打开 App](https://support.apple.com/guide/mac-help/open-an-app-by-overriding-security-settings-mh40617/mac)。如果系统提示应用“将损坏您的电脑”或明确报告恶意软件，请勿绕过警告，应删除安装包并提交 Issue。

可在终端校验下载文件：

```bash
shasum -a 256 -c Show-Codex-IQ-0.1.0-beta.4-universal.dmg.sha256
```

> [!WARNING]
> 当前为预发布版本，界面、配置和数据结构仍可能调整。重要使用场景请先自行验证。

## 系统要求

- macOS 14.0 或更高版本
- Apple Silicon 或 Intel Mac（Universal 2）
- 访问 `https://codexradar.com/current.json` 的网络连接

## 排名规则

- 智商按高到低排序，费用和耗时按低到高排序；模型与推理强度的组合视为独立候选项。
- 综合榜将三个单项名次换算为百分位分数，并列项使用平均名次；只有一个候选项时记 100 分。
- 综合分同分时依次比较智商、费用、耗时和稳定 model id。
- 缺少某项指标的模型只会从对应单项榜排除；进入综合榜需要三项指标完整。

## 数据与隐私

应用仅请求 `https://codexradar.com/current.json`，不抓取网页 HTML。请求包含缓存验证器，重复刷新会被合并。

本地数据存放于：

```text
~/Library/Application Support/ShowCodexIQ/
```

其中只包含最后一次成功快照、HTTP 缓存验证器，以及安装后累积的费用趋势。应用不会补造数据源未提供的历史费用。字段、刷新策略和授权状态详见 [docs/data-source.md](docs/data-source.md)。

## 本地开发

项目使用 SwiftUI、AppKit `NSStatusItem`、Swift Charts、Observation、URLSession 和 ServiceManagement，不包含第三方运行时依赖。Xcode 工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 的 `project.yml` 生成。

```bash
brew install xcodegen
xcodegen generate
open ShowCodexIQ.xcodeproj
```

当前工程使用 Swift 6 language mode；正式归档和 macOS 26 API 验证需要 Xcode 27 或兼容版本。

### 测试

```bash
swift run CoreVerification
swift test
```

完整 Xcode 测试：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
xcodebuild \
  -project ShowCodexIQ.xcodeproj \
  -scheme ShowCodexIQ \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

### 打包与校验

```bash
# Xcode 归档构建
bash scripts/build_dmg.sh

# 便携 Universal 2 构建
bash scripts/build_portable_dmg.sh

# 校验版本、签名、安装布局、静态 Core、实际启动、校验值和双架构
bash scripts/verify_dmg.sh dist/Show-Codex-IQ-0.1.0-beta.4-universal.dmg
```

`dist/` 与安装包不会提交到 Git；它们只作为 GitHub Release 附件发布。

## 版本与发布

项目遵循 [Semantic Versioning 2.0.0](https://semver.org/lang/zh-CN/)：

- `MAJOR`：不兼容的行为或公开接口变更。
- `MINOR`：向后兼容的新功能。
- `PATCH`：向后兼容的问题修复。
- `alpha.N`、`beta.N`、`rc.N`：对应阶段的预发布版本。

完整版本、Apple 营销版本和构建号统一维护在 `Sources/ShowCodexIQ/Config/Version.xcconfig`。每次发布必须同步更新 [CHANGELOG.md](CHANGELOG.md)，创建 `v<版本号>` 标签，并发布对应 GitHub Release。具体流程见 [docs/releasing.md](docs/releasing.md)。

## 参与贡献

欢迎提交 Issue 和 Pull Request。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，并确保核心验证器与测试全部通过。

## 致谢

- 排名数据由 [Codex 雷达](https://codexradar.com/) 提供。
- 菜单栏的左侧图标与右侧两行信息层级参考了 MIT 许可的 [debugtheworldbot/keyStats](https://github.com/debugtheworldbot/keyStats)。

## 许可

项目代码采用 [MIT License](LICENSE) 发布。第三方数据仍受其来源方条款约束。
