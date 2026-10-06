# 隐私与本机数据边界

Codex Toolbox 不包含分析、广告或遥测 SDK，不调用模型处理 Token 用量，不上传任务标题或对话内容。

## 用量分析

- 只读访问当前用户的 `~/.codex/state_*.sqlite` 和 rollout JSONL。
- 本机 Usage Ledger schema 7 包含逐日 Token 总量、文件检查点，以及逐轮输入、缓存输入、缓存写入、输出、推理输出和总 Token；同时保存当时的模型、推理强度、Standard/Fast、脱敏计划类型和费率版本，用于按事件时间重算 Credits。
- rollout 与账户时间线会在写入账本前脱敏；不保存额度 limit ID、积分余额、凭据、opaque ID 或任务正文。
- 看板使用 Codex SQLite 中的具体对话/任务标题；通用标题会回退到本机首条用户消息或预览摘要，数据不会上传。
- 用户可清除历史账本；不会因 rollout 被删除而自动删除已记录历史。

## 账户额度&重置卡

- 通过随应用打包的固定版本官方认证组件区分 ChatGPT、API、未登录和无法确认状态。界面接收登录模式及安装盐参与计算的账户指纹；任务报表另包含脱敏账户归属、更新时间、完整性和累计额度比例。
- 账户额度通过本机 Codex app-server 的 `account/rateLimits/read` 查询。每日任务额度通过固定版本辅助程序向官方原生任务接口发送根聊天 ID、创建日期和子代理 ID；不发送标题、正文或文件内容。API 登录不查询 ChatGPT 套餐或任务额度，不查询套餐历史。
- 账户缓存保存已验证的脱敏归属、套餐类型、额度窗口、重置时间，以及重置卡可用数量、本地顺序号、状态、授予和过期时间。
- 本机 Token 和 API 等值成本汇总可读取的本机全部历史，独立于当前账户。历史记录缺少逐轮账户证据时保持未知，不利用当前登录或聊天创建者补填。
- 不保存、记录或输出 access token、refresh token、cookie、原始账户 ID、opaque credit ID。错误详情不会直接输出。
- 不兑换、删除或自动使用重置卡，不包含任意 API 代理。切换账户后清除旧显示并拒收旧请求，仅在确认同一账户时保留离线缓存。

原生任务快照与本机 Token 历史分别保存，按脱敏账户隔离并保留 90 天，不保存任何任务正文或账户凭据。

## 模型排名

自 1.4.1 起，榜单和兼容历史统一请求 `https://zjwspace.cn/api/codex-toolbox/v1/radar.json`，由网站定时抓取、校验并发布上游聚合成绩，客户端刷新不触发上游抓取。请求只使用普通 GET 与 HTTP 缓存校验标识，不上传账户、Token、任务或设备信息。网站公开结果不包含原始参与者资料。

用户开启默认关闭的站长推荐后，另外请求 `https://codexradar.com/api/radar-insights`；其缓存和错误状态与榜单相互隔离。

## 官方费率

仅在启用实验性“本机成本换算”及自动更新时，应用每 6 小时对项目托管的版本化费率 JSON 发送 GET/ETag，不携带 Codex/ChatGPT 账户或本机用量。该 JSON 由 GitHub Actions 从 OpenAI 公开费率页与 Speed 页严格解析、校验并保留历史版本；应用在远程数据无效时回退到最后有效缓存或内置版本。

## 更新检查

开启“自动检查并在后台下载”时，Sparkle 按用户选择的每小时或每天频率读取 GitHub Release 中的 `appcast.xml`。发现更新后会从同一 GitHub Release 下载 DMG，在本机使用 Ed25519 与 Apple 代码签名验证后暂存，等待用户点击“立即更新”或退出应用。

更新请求不携带 GitHub token、Codex/ChatGPT 账户凭据、本机任务信息或系统画像；应用未启用 Sparkle 的系统信息上报。

## 应用支持文件

Codex Toolbox 的快照、用量账本和重置卡脱敏缓存存放在 `~/Library/Application Support/CodexToolbox/`。旧模型快照继续保留作为回滚保障；聚合口径使用独立缓存文件，不会读取或覆盖旧累计费用、累计耗时历史。
