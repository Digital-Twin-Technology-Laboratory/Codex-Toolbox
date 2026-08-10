<div align="center">
  <img src="design/icon-concepts/codex-toolbox-preview.png" width="160" alt="Codex Toolbox 应用图标">
  <h1>Codex Toolbox</h1>
  <p>把模型排名、本机 Token 用量与账户重置卡放进 macOS 菜单栏。</p>

  [![GitHub Release](https://img.shields.io/github/v/release/Digital-Twin-Technology-Laboratory/Codex-Toolbox?sort=semver)](https://github.com/Digital-Twin-Technology-Laboratory/Codex-Toolbox/releases)
  [![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple)](#系统要求)
  [![Swift 6](https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white)](https://www.swift.org/)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
</div>

Codex Toolbox 是一款原生 macOS 菜单栏工具。它保留 Show Codex IQ 的模型智商、费用、耗时和综合排名，同时新增完全本机的 Token 审计与账户重置卡只读查询。三个模块各自刷新、各自缓存，任一数据源失败都不会清空其他结果。

> [!NOTE]
> **v1.2.1 已于 2026 年 8 月 10 日正式发布。** 本版修复大数字 Token 总量换行和模型名称过早省略，重新整理设置分组与隐私说明，并对新用户默认展示榜单的其他指标。

> [!IMPORTANT]
> 本项目与 OpenAI、ChatGPT 和 Codex 雷达均无官方隶属关系。模型排名来自 [codexradar.com](https://codexradar.com/)，详见[数据来源与授权说明](docs/data-source.md)。

## 应用预览

<p align="center">
  <img src="docs/assets/screenshots/dashboard.png" width="390" alt="Codex Toolbox 模型智商看板，显示智商、费用、耗时与综合排名">
  <img src="docs/assets/screenshots/model-ranking-expanded.png" width="390" alt="Codex Toolbox 模型智商榜单展开视图，显示完整前五名排名">
  <img src="docs/assets/screenshots/token-reset-expanded.png" width="390" alt="Codex Toolbox Token 用量趋势与账户重置卡展开视图">
  <img src="docs/assets/screenshots/dashboard-collapsed.png" width="390" alt="Codex Toolbox 默认折叠看板，显示模型智商、Token 用量与重置卡摘要">
</p>

## 三项核心功能

### 模型智商

- 从 Codex 雷达公开聚合快照读取当前 21 个模型档位；智商、每题平均费用与每题平均耗时采用同一数据口径，并保留公开历史趋势。
- 第四榜单默认是本地 IQ/费用/耗时加权百分位，也可切换为 Codex Radar 发布的“成本效率”（只含费用和耗时，越低越好）；两者不混称。
- 可选站长推荐默认关闭，开启后支持日常开发、困难任务、后台自动化和龙虾类任务四类场景，并可选择放在四宫格上方或下方。
- 完整保留四类榜单、前三/前五展开、趋势图与离线快照。模型趋势图默认不显示，可开启并选择 7/14/30/90 天范围。
- 菜单栏可切换智商、综合、费用或耗时，并支持序号、图标、详细数值和模型别名。
- 失败时继续展示最后一次成功数据，不会用空榜单覆盖有用状态。

### Token 用量

- 只读解析 `~/.codex/state_*.sqlite` 和本机 rollout JSONL，不调用模型，不上传任务内容。
- Token 内容分为上下两张独立卡片：当日总量与根任务 Top 3、每日用量趋势。点击趋势柱可切换到该日任务明细，并可“返回今日”；每次关闭弹窗都会清除日期选择。任务榜单可按设置展开为 Top 5 或 Top 10，悬停柱子仍可查看精确 Token。
- Token 卡分别显示本机可读日志的原始 Token、按版本化官方费率计算的 Credits、账户全设备/共享产品权威已用比例，以及逐任务 `≈额度%`。费率数据每 6 小时自动检查，并按事件时间选择历史版本。
- 计算会跟踪中途模型、推理强度与 Standard/Fast 切换，区分缓存命中与免费缓存写入，且不重复计算已包含在输出中的 reasoning Token。字段不完时显示近似或上界，API Key 模式不套用 ChatGPT Credits。
- 活动任务期间会每分钟只读采样账户窗口；其他设备或共享产品消耗、同一分钟并发会被标记并不用于学习换算率。无可用样本时不显示任务百分比。
- 任务按根任务及全部子任务聚合，标题使用 Codex 在本机保存的具体对话或任务名称；趋势支持 7/14/30/90 天。
- 以累计 `total_token_usage.total_tokens` 去重，把 `last_token_usage.total_tokens` 按系统时区记账。`cached_input_tokens` 已属于 input，`reasoning_output_tokens` 已属于 output，不另行重复相加。
- 历史账本默认永久保留；源文件缺失或损坏时保留已记录数据并标记为“不完整”。

### 重置卡

- 通过已安装且登录的 Codex/ChatGPT 启动短生命周期 `codex app-server --listen stdio://`。
- 只请求 `account/rateLimits/read`，展示权威可用数量、最近过期时间和脱敏详情，并只保留额度窗口的时长、已用百分比与重置时间用于估算。
- 逐卡只缓存并展示发放时间和过期时间，统一转换为北京时间。
- 不保存或输出 access token、refresh token、cookie、说明文字或完整唯一 ID，永不发送 `account/rateLimitResetCredit/consume`。
- 未安装、未登录、超时或协议不兼容时给出可操作的恢复提示；有缓存时仍显示最后成功状态。

## 看板与设置

弹窗是一个连续的纵向看板。三个模块默认全部显示，Token 用量和重置卡默认折叠，折叠标题仍会直接显示今日 Token 总量与可用卡数。标题整行都是至少 44pt 高的展开/折叠按钮，刷新按钮仍保持独立。模块可隐藏、拖动排序或用键盘上移/下移。

设置页顺序为“通用与看板”、“智商显示”、“Token 用量”、“重置卡”和“关于”。模型榜单与 Token 选项按功能分组，数据访问说明集中在“关于 → 数据与隐私详情”。通用页可调整模块顺序、登录启动，以及每小时或每天自动检查更新。新版本会在后台下载；准备完成后设置齿轮显示红点，点击“立即更新”即可让应用自动退出、替换并重新打开。

macOS 26+ 使用原生 Liquid Glass，macOS 14–15 回退为系统 Material。动效采用无弹跳的临界阻尼过渡；Reduced Motion 下只保留短交叉淡化。

## 安装与从 Show Codex IQ 升级

1. 从 [Releases](https://github.com/Digital-Twin-Technology-Laboratory/Codex-Toolbox/releases) 下载 PKG 或 DMG，并下载对应 `.sha256`。
2. 校验文件：

   ```bash
   shasum -a 256 -c Codex-Toolbox-1.2.1-universal.pkg.sha256
   # 或
   shasum -a 256 -c Codex-Toolbox-1.2.1-universal.dmg.sha256
   ```

3. **PKG（升级推荐）：**双击安装。它会在新应用验证成功后精确删除 `/Applications/Show Codex IQ.app`。
4. **DMG（手动拖拽）：**升级前先退出并删除“应用程序”中的 `Show Codex IQ.app`，再把 `Codex Toolbox.app` 拖入 Applications，避免新旧两个应用并存。DMG 内附中文升级说明。

Bundle ID 保持为 `io.github.zzzzzzjw.ShowCodexIQ`，因此原设置与登录启动偏好可直接继承。旧版累计口径榜单缓存会保留用于回滚，但新版本使用独立的聚合快照缓存，不会混入旧费用和耗时历史。PKG 会请求已运行的旧应用退出；新应用的目标路径、Bundle ID、签名与 Universal 2 架构全部验证成功后，才会删除精确路径 `/Applications/Show Codex IQ.app`。详见[升级与回滚说明](docs/upgrade-from-show-codex-iq.md)。

> [!NOTE]
> v1.0.0 尚未内置 Sparkle，因此从 v1.0.0 升级到 v1.1.0 仍需手动安装一次。从 v1.1.0 开始，后续正式版本会通过 Ed25519 与 Apple 代码签名校验，并可在应用内完成更新。

> [!WARNING]
> 不要对非官方、未签名或未公证的 PKG 绕过 Gatekeeper。仓库中的本地开发包只用于测试，不是可发布产物。

## 系统要求

- macOS 14.0 或更高版本
- Apple Silicon 或 Intel Mac（Universal 2）
- 模型排名需要访问 `https://codexradar.com/data/intelligence-efficiency.json`
- Token 模块需要当前 Mac 上可读取的 Codex 本地数据
- 重置卡模块需要已安装并登录的 Codex 或 ChatGPT；其他模块不受影响

## 数据与隐私

Token 总量仅代表当前 Mac 仍可读取的日志；归档或删除的 rollout、未落盘记录、云端及其他设备都不在其中。Credits 是本机事件按公开费率的计算值；账户已用比例来自账户接口，任务百分比始终是带置信度的估算。

应用级数据存放在：

```text
~/Library/Application Support/CodexToolbox/
```

旧版 `radar-latest.json` 和 `Application Support/ShowCodexIQ/latest.json` 不会被删除，便于回滚；新聚合口径使用独立的 `radar-intelligence-efficiency-v2.json`，不会迁移旧累计费用和耗时。更完整的边界见[隐私说明](docs/privacy.md)。

## 本地开发

项目使用 SwiftUI、AppKit `NSStatusItem`、Swift Charts、Observation、URLSession、SQLite3 和 ServiceManagement；应用内更新使用 [Sparkle 2](https://sparkle-project.org/)。Xcode 工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 生成。

```bash
brew install xcodegen
xcodegen generate
open CodexToolbox.xcodeproj
```

核心和完整 Xcode 测试：

```bash
bash scripts/test_all.sh
```

`test_all.sh` 会把 SwiftPM 与 Xcode 产物隔离到 `/private/tmp`，并在结束时终止、注销和清理临时 Debug 应用，不会在 Spotlight 中留下第二个 Codex Toolbox。真实界面手测只安装 PKG，由安装器替换 `/Applications/Codex Toolbox.app`；不直接启动 `DerivedData/Build/Products` 中的应用。

### PKG / DMG 构建、签名与公证

`scripts/build_pkg.sh` 在没有证书时会生成 ad-hoc 应用签名和未签名的本地测试 PKG。正式发布必须使用两类独立证书重建：

```bash
APP_SIGN_IDENTITY='Developer ID Application: ...' \
INSTALLER_SIGN_IDENTITY='Developer ID Installer: ...' \
bash scripts/build_pkg.sh

NOTARY_PROFILE='codex-toolbox-notary' \
bash scripts/notarize_pkg.sh

APP_SIGN_IDENTITY='Developer ID Application: ...' \
bash scripts/build_dmg.sh

NOTARY_PROFILE='codex-toolbox-notary' \
bash scripts/notarize_dmg.sh
```

证书和公证凭据只存在钥匙串，不写入脚本、环境文件或仓库。PKG 和 DMG 都必须签名、公证并 staple 后才能进入普通（非 Pre-release）GitHub Release。详见[发布指南](docs/releasing.md)与 [DMG 安装说明](docs/distribution/dmg-legacy.md)。

## OpenAI Build Week 项目沿革

Codex Toolbox 的前身 **Show Codex IQ** 在 OpenAI Build Week 期间是一个可运行的菜单栏模型榜单原型。仓库保留了用户原有的提交资料与人机协作记录：

- **Pre-period baseline:** 前六个提交，截止 `fb4219f`，包含初始骨架、排名/缓存核心、最初的菜单栏 UI 和打包。
- **In-period extension:** 后续工作增加了三段式权重、趋势、自适应弹窗与菜单栏、模型别名、开源文档、静态链接启动修复与端到端 DMG 验证。
- **Primary in-period `/feedback` Session ID:** `019f60dc-d23e-7ad2-84a2-a739947f1277`
- **Codex accelerated:** 功能实现、截图驱动的 UI 优化、测试、Universal 2 打包、已安装应用诊断和发布验证。
- **Human decisions:** 紧凑的两行菜单栏体验、用户可调的质量/成本/延迟权重、非破坏性失败行为，以及对界面与打包结果的审阅。

当时的[评委指南](docs/hackathon/judges-guide.md)和[完整提交包](docs/hackathon/README.md)作为历史资料继续保留，其中的 Show Codex IQ 名称与 DMG 命令反映当时版本。

## 参与贡献

欢迎提交 Issue 和 Pull Request。开始前请阅读 [CONTRIBUTING.md](CONTRIBUTING.md)，并确保核心验证器、Swift 测试与完整 Xcode 测试全部通过。

## 许可

项目代码采用 [MIT License](LICENSE)发布。第三方数据仍受其来源方条款约束。
