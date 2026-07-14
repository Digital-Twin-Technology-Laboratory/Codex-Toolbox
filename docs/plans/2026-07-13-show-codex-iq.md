# Show Codex IQ v0.1 实施记录

## 目标

实现一个 macOS 14+ 原生菜单栏应用，定时读取 CodexRadar 公开摘要，用两行展示当前排名前两名，并提供榜单、趋势、离线缓存和自定义综合权重。

## 已实现架构

- `URLSessionRadarClient`：15 秒超时、ETag / Last-Modified、304、JSON Accept 和明确 User-Agent。
- `RadarRepository`：actor single-flight，失败保留旧数据，对 UI 暴露 stale / error 状态。
- `SnapshotStore`：Application Support 原子保存最新快照、缓存验证器和本地费用历史。
- `RankingEngine`：四类纯函数排名，并列平均名次百分位、稳定 tie-break 和 50/25/25 默认权重。
- `AppSettings`：UserDefaults 持久化菜单栏指标、序号格式、详细数值开关、刷新策略、有效权重和开机启动偏好。
- `AppModel`：MainActor + Observation 的单向 UI 状态，启动时先读缓存再刷新。
- `NSStatusItem + NSHostingView`：可靠控制左侧指标图标与右侧两行信息；详情、趋势与设置仍使用 SwiftUI。

## 产品行为

- 菜单栏默认以 94pt 紧凑宽度展示智商前两名，不显示序号和数值；可切换指标、序号格式和详细数值。
- 430 x 680 pt 弹窗展示四组前三榜单、数据日期、获取时间、在线/离线、立即刷新、三类趋势、设置和退出；榜单支持悬停全名、展开前五名和摘要切换。
- macOS 26+ 榜单卡片与图标按钮使用 SwiftUI 原生 Liquid Glass；macOS 14–15 使用系统材质兼容样式。
- 费用曲线仅使用安装后本地累积数据，少于两点显示说明。
- 自动刷新默认 30 分钟，支持 15/30/60/120/240 分钟；系统唤醒后会检查是否到期。
- 权重是 0–100 整数，合计不为 100 时禁用应用按钮，继续使用上次有效配置。
- 弹窗和关于页固定显示“数据来自 Codex 雷达 codexradar.com”。

## 工程与分发

- XcodeGen 生成标准 Xcode 工程，Swift 6 language mode，Deployment Target macOS 14。
- Xcode 27 beta 脚本通过 Archive 生成 Universal 2，然后 ad-hoc 签名并制作 DMG。
- Command Line Tools 备用脚本可交叉编译 `arm64 + x86_64` 验证构建。
- DMG 包含应用、Applications 快捷方式和首次打开说明，同时生成 SHA-256。
- `0.1.0-beta.1` 不公证、不创建公开 Release；正式对外发布前需重新检查 CodexRadar 授权状态。

## 验证状态

- Swift 6.4 核心验证器通过。
- 全量应用源码在 macOS 14 target 下通过 warnings-as-errors typecheck。
- 真实 `current.json` 已成功解码并在菜单栏、四类榜单和曲线中展示。
- Universal 2 便携 DMG 已完成签名、挂载、SHA-256、双架构和启动验证。
- 完整 XCTest 与 Xcode Archive 由安装 Xcode 的本机/稳定 CI 执行。
