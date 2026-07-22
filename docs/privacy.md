# 隐私与本机数据边界

Codex Toolbox 不包含分析、广告或遥测 SDK，不调用模型处理 Token 用量，不上传任务标题或对话内容。

## Token 用量

- 只读访问当前用户的 `~/.codex/state_*.sqlite` 和 rollout JSONL。
- 本机 Usage Ledger 包含逐线程、逐日 Token 总量、文件路径检查点、文件偏移与累计 Token；为估算任务额度，还保存 rollout 已包含的事件时间、单轮 Token、窗口时长、已用百分比和重置时间，不保存对话正文。
- rollout 中的额度快照会在写入账本前脱敏；不保存额度 limit ID、套餐字段、积分余额或其他账户字段。
- 看板使用 Codex SQLite 中的具体对话/任务标题；通用标题会回退到本机首条用户消息或预览摘要，数据不会上传。
- 用户可清除历史账本；不会因 rollout 被删除而自动删除已记录历史。

## 重置卡

- 只通过本机 Codex app-server 请求 `account/rateLimits/read`。
- 缓存仅保存可用数量、本地顺序号、可用状态、授予时间、过期时间和最后更新时间。
- 不保存、记录或输出 access token、refresh token、cookie、说明文字、opaque credit ID 或其他完整唯一 ID。app-server 错误详情也不会直接显示。
- 客户端不实现、不调用 `account/rateLimitResetCredit/consume`。

## 模型排名

该模块只请求 `https://codexradar.com/current.json`，使用 ETag 和 Last-Modified 缓存验证，不抓取 HTML。

## 更新检查

开启“自动检查并在后台下载”时，Sparkle 按用户选择的每小时或每天频率读取 GitHub Release 中的 `appcast.xml`。发现更新后会从同一 GitHub Release 下载 DMG，在本机使用 Ed25519 与 Apple 代码签名验证后暂存，等待用户点击“立即更新”或退出应用。

更新请求不携带 GitHub token、Codex/ChatGPT 账户凭据、本机任务信息或系统画像；应用未启用 Sparkle 的系统信息上报。

## 应用支持文件

Codex Toolbox 的快照、用量账本和重置卡脱敏缓存存放在 `~/Library/Application Support/CodexToolbox/`。v1.0.0 首次升级会保留 `~/Library/Application Support/ShowCodexIQ/` 中的旧快照，作为回滚保障。
