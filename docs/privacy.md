# 隐私与本机数据边界

Codex Toolbox 不包含分析、广告或遥测 SDK，不调用模型处理 Token 用量，不上传任务标题或对话内容。

## Token 用量

- 只读访问当前用户的 `~/.codex/state_*.sqlite` 和 rollout JSONL。
- 本机 Usage Ledger schema 7 包含逐日 Token 总量、文件检查点，以及逐轮输入、缓存输入、缓存写入、输出、推理输出和总 Token；同时保存当时的模型、推理强度、Standard/Fast、脱敏计划类型和费率版本，用于按事件时间重算 Credits。
- rollout 与账户时间线会在写入账本前脱敏；不保存额度 limit ID、积分余额、凭据、opaque ID 或任务正文。
- 看板使用 Codex SQLite 中的具体对话/任务标题；通用标题会回退到本机首条用户消息或预览摘要，数据不会上传。
- 用户可清除历史账本；不会因 rollout 被删除而自动删除已记录历史。

## 重置卡

- 只通过本机 Codex app-server 请求 `account/rateLimits/read`。
- 缓存仅保存可用数量、本地顺序号、可用状态、授予时间、过期时间和最后更新时间。
- 不保存、记录或输出 access token、refresh token、cookie、说明文字、opaque credit ID 或其他完整唯一 ID。app-server 错误详情也不会直接显示。
- 客户端不实现、不调用 `account/rateLimitResetCredit/consume`。

## 模型排名

榜单请求 `https://codexradar.com/data/intelligence-efficiency.json`；用户开启站长推荐后，另外请求 `https://codexradar.com/api/radar-insights`。两者只发送普通 GET 与 ETag/Last-Modified，缓存、错误状态相互隔离，不上传账户、Token、任务或设备信息。

## 官方费率

应用每 6 小时对项目托管的版本化费率 JSON 发送 GET/ETag，不携带 Codex/ChatGPT 账户或本机用量。该 JSON 由 GitHub Actions 从 OpenAI 公开费率页与 Speed 页严格解析、校验并保留历史版本；应用在远程数据无效时回退到最后有效缓存或内置版本。

## 更新检查

开启“自动检查并在后台下载”时，Sparkle 按用户选择的每小时或每天频率读取 GitHub Release 中的 `appcast.xml`。发现更新后会从同一 GitHub Release 下载 DMG，在本机使用 Ed25519 与 Apple 代码签名验证后暂存，等待用户点击“立即更新”或退出应用。

更新请求不携带 GitHub token、Codex/ChatGPT 账户凭据、本机任务信息或系统画像；应用未启用 Sparkle 的系统信息上报。

## 应用支持文件

Codex Toolbox 的快照、用量账本和重置卡脱敏缓存存放在 `~/Library/Application Support/CodexToolbox/`。旧模型快照继续保留作为回滚保障；聚合口径使用独立缓存文件，不会读取或覆盖旧累计费用、累计耗时历史。
