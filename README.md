# Show Codex IQ

Show Codex IQ 是一个原生 macOS 菜单栏应用，用两行快速展示 Codex 模型当前排名，并在弹窗中集中展示智商、费用、耗时、综合排名与趋势。

![Show Codex IQ 应用图标](Sources/ShowCodexIQ/Resources/Assets.xcassets/AppIcon.appiconset/icon_256x256.png)

## 功能

- 菜单栏使用“指标图标 + 两行名次 / 紧凑模型名 / 数值”格式，可切换智商、综合、费用或耗时。
- 点击后展示四组前三榜单、数据日期、网络状态、立即刷新和 Swift Charts 趋势。
- 开机先读取最后一次成功快照；离线或请求失败不会清空已有排名。
- 自动刷新默认 30 分钟，可选 15 / 30 / 60 / 120 / 240 分钟，也可关闭。
- 综合排名支持 0–100 整数权重；默认智商 50%、费用 25%、耗时 25%，合计必须为 100%。
- 支持登录时启动；设置未移入 `/Applications` 的应用时会给出提示。
- 无分析 SDK，不收集个人信息，不保存账号凭据。

## 系统与工程

- macOS 14.0+
- Swift 6 language mode；当前验证编译器为 Apple Swift 6.4
- Xcode 27 beta 用于正式归档与 Universal 2 打包
- SwiftUI、AppKit `NSStatusItem`、Swift Charts、Observation、URLSession、ServiceManagement
- 不引入第三方运行时依赖

Xcode 工程由 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 的 `project.yml` 生成：

```bash
brew install xcodegen
xcodegen generate
open ShowCodexIQ.xcodeproj
```

## 验证与测试

核心验证器不依赖 Xcode，覆盖解码、排名、自定义权重、趋势、缓存、设置与 repository 状态：

```bash
swift run CoreVerification
```

完整 XCTest 使用 Xcode 运行：

```bash
xcodebuild \
  -project ShowCodexIQ.xcodeproj \
  -scheme ShowCodexIQ \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## 打包

正式 beta 打包脚本显式使用 `/Applications/Xcode-beta.app`，生成 `arm64 + x86_64` 的 ad-hoc 签名 DMG 和 SHA-256 文件：

```bash
bash scripts/build_dmg.sh
```

如果当前机器只有 Swift 6.4 Command Line Tools，可交叉编译用于验证的 Universal 2 便携构建：

```bash
bash scripts/build_portable_dmg.sh
```

可重复检查 DMG 的校验值、签名、内容和双架构：

```bash
bash scripts/verify_dmg.sh dist/Show-Codex-IQ-0.1.0-beta.1-universal-portable.dmg
```

`dist/` 和 DMG 被 Git 忽略，本 beta 不创建公开 GitHub Release。

## 首次打开

`0.1.0-beta.1` 是免费 ad-hoc 签名、未经 Apple 公证的 beta。将应用拖入 Applications 后，如果 macOS 拦截启动，请前往“系统设置 → 隐私与安全性”，在页面下方点击“仍要打开”。这是当前免费分发方案的预期提示。

## 排名规则

- 智商降序，费用和耗时升序；模型与推理强度组合视为独立候选项。
- 综合榜先将三个单项名次转为百分位分数，并列使用平均名次；只有一个候选项时记 100 分。
- 同分依次比较智商、费用、耗时和稳定 model id。
- 缺少某个指标的项仅从相应榜单排除；综合榜需要三项完整。

## 数据来源与授权

**数据来自 Codex 雷达 [codexradar.com](https://codexradar.com/)。** 应用只请求 `https://codexradar.com/current.json`，不抓取 HTML。

该公开 JSON 当前的 `api_access` 声明指出，完整 API 与二次开发使用需授权。本项目与 Codex 雷达无官方隶属关系；个人或小范围验证之外的分发、公开发布或商业使用，应先向数据源方确认授权。详见 [docs/data-source.md](docs/data-source.md)。

## 隐私

应用只在 `~/Library/Application Support/ShowCodexIQ/` 保存最后一次成功快照、HTTP 缓存验证器和安装后累积的费用历史。费用历史不伪造网站未提供的旧数据。

## 致谢

菜单栏的左侧图标 + 右侧两行信息层级参考了 MIT 许可的 [debugtheworldbot/keyStats](https://github.com/debugtheworldbot/keyStats)。

## License

MIT
