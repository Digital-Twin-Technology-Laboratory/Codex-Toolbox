# Codex Radar 接口复核与恢复方案（2026-10-06）

状态：诊断完成，修复设计待实施。没有修改应用代码、用户缓存、安装包或线上服务。

## 结论与前次结论更正

并非所有上游数据源都不可用。当前客户端使用的聚合入口持续返回 502；但明确指定旧基准的原始题目表仍可读取真实历史成绩。前次仅验证不带参数的 `/api/v1/table`，得到 410 后对旧接口可用范围的判断不完整。进一步检查发现这些 200 响应来自 Cloudflare 的过期缓存，不能据此宣称旧实时服务已经恢复。

- `/api/v1/table`：410，提示取分接口停用。
- `/api/v1/table?benchmark=deep-swe`：200，有旧软件工程基准的逐题成绩。
- `/api/v1/table?benchmark=pompeii-adjacency`：200，有旧视觉推理基准的逐题成绩。
- 两个带基准的 200 响应都标记 `CF-Cache-Status: STALE`。对 DeepSWE 追加请求头 `Cache-Control: no-cache` 后，仍是 STALE，`Age: 183187`（约 50.9 小时），内容 ETag 未变。
- 按众测站现有 JavaScript 的完整参数访问 `table?ui=20260818-unified-median-points-v1&benchmark=…`，两个旧基准均返回 503。不能把可读旧缓存配置成一个已经验证稳定的实时服务；内部究竟是路由校验、迁移还是源站故障，需要提供方确认。

截至本次核查，旧题目表最新判分仍在 10 月 4 日，与本机最后成功快照同一时期；新 Radar Bench 的 34 个公开模型档位全部没有当前有效分数。可以修复取数和错误降级，不能承诺恢复 10 月 6 日的新成绩。

众测站已公开公告正在重构与试运行。来源：<https://deng.codexradar.com/>。

## 范围、方法与证据

检查主站与众测站 HTML、实际加载的 JavaScript 模块、公开 binding/catalog，以及既往使用过的地址。共验证 76 个不同 GET URL（包含 34 个新基准模型档位组合），另做一次 no-cache 对照。请求只覆盖与榜单、成绩、历史、推荐和社区评分相关的公开读取入口；不枚举隐藏路由，不操作登录、领题、运行、提交或管理接口。本报告不是对服务器所有内部 API 的穷举。

网络检查使用 HTTPS，关闭 curl 显式代理以排除此前本机 HTTP 代理故障；这不代表从另一台机器或独立网络探测。未跳过 TLS 校验，未使用账号凭据。分别检查 HTTP、JSON 格式、数据日期、模型档位、有效数值与口径。

原始响应和响应头保存在本机 `.build/radar-api-audit-20261006/`（不提交 Git）：

- `index.json`：逐个 URL 的状态、时间、响应文件名、字段和记录数量。
- `audit.py`、`extend_audit.py`：公开 GET 探测脚本。
- `table-comparison.json`：题目表与本机最后成功快照的 IQ 比对。
- `gpt-cost-duration-comparison.json`：按网页旧基准规则计算的 GPT 费用、耗时比对。
- `compare_snapshot.py`：仅在本机执行的可复现比对脚本。

本机缓存仅用于回归对照，不写入或上传；不把原始逐题表中的参与者资料放进本报告或未来的客户端聚合结果。

## 数据源可用性

| 来源 | 本次结果 | 数据价值及限制 |
| --- | --- | --- |
| 主站 `/api/intelligence-efficiency-metrics`，含 `refresh=1` | 502 | 当前客户端单一主源故障 |
| 主站 `/api/radar-insights` | 502 | 推荐入口同样不可用 |
| 上游 `/api/v1/intelligence-efficiency`，无参数及两个旧基准参数 | 404 | 不能直接把主源换成这个旧聚合地址 |
| 上游 `/api/v1/table?benchmark=deep-swe` | 200；112 题，91 个模型档位组合，7,663 个有成绩的格子 | 仍有真实旧基准结果；最近判分 `2026-10-04T02:03:45+00:00` |
| 上游 `/api/v1/table?benchmark=pompeii-adjacency` | 200；86 题，58 个组合，3,772 个有成绩的格子 | 旧视觉基准；最近判分 `2026-10-04T01:59:02+00:00`，不能替换 DeepSWE |
| 上述两种 `table` 请求加上网站实际使用的 `ui=20260818-unified-median-points-v1` | 503 | 原样复现网站调用仍失败；无 `ui` 的成功响应为 STALE CDN 缓存 |
| `/api/v1/iq-history?benchmark=…`（两个旧基准） | 404 | 无法依赖它恢复实时历史接口 |
| `/api/v1/radar-insights?benchmark=deep-swe` | 404 | 不能用作推荐备用源 |
| `/api/v1/leaderboard?view=live&benchmark=deep-swe` | 404 | 该旧天梯查询不可用；贡献积分也不是模型能力分 |
| `/api/v1/benchmarks` | 200 | 基准目录，不是模型成绩 |
| `/api/v1/library-catalog` | 200 | 四个题库各有 34 档查询结果，但全部 `missing_bindings`；目录存在不代表有有效分数 |
| 四个 catalog 指定的 `library-table` 与 `library-leaderboard` | 200 | 新题库表格/配置可读取，但未发现当前有效判分；天梯无贡献记录 |
| `/api/v1/radar-bench?model=…&effort=…` | 410 | 旧新基准入口已被替换 |
| `/api/v1/radar-bench-score?model=gpt-6.1-sol&effort=high` | 200 | 原始新基准结构、64 道任务、0 个判分事件、分数为空 |
| 主站 `/api/radar-bench-score?...&view=summary` | 34 档全部 200 | 34 档全部 `missing_current_result`、`score=null`、覆盖 0；不能生成当前排名 |
| `/data/intelligence-efficiency.json` | 200；89 条 | IQ、价格、时间及历史存在，但日期为 `2026-10-01T23:00:27+08:00` |
| `/data/intelligence-efficiency-codex.json` | 200；36 条 | GPT 旧快照，同样停在 10 月 1 日 |
| `/data/radar-legacy-software.json` | 200；36 条，379 个历史快照 | 可作为旧软件工程历史/冷启动资料，不应覆盖 10 月 4 日缓存 |
| `/data/radar-legacy-visual.json` | 200；36 条，257 个历史快照 | 9 月 30 日旧视觉口径，不能混进 DeepSWE 趋势 |
| `/data/radar-legacy-comprehensive.json` | 200；36 条 | 9 月 30 日旧综合口径，没有费用、耗时及历史；不同于 Toolbox 本地综合加权 |
| `/api/model-ratings?view=public&window=24h` | 200；49 个条目，29 个有投票 | 当日仍在更新的社区主观评分，不是客观 IQ |
| `/api/model-ratings?view=public&history=14&window=7d` | 200；49 个条目，39 个有投票 | 有 14 天社区历史；可以单独展示，不能充当能力榜备用源 |
| `/current.json` | 200 | 顶层日期 9 月 29 日；`model_iq.updated_at` 为 9 月 13 日；更旧且统计口径不同 |
| `/api/v1/current`（主站的 full_api 链接） | 401 | 明确要求授权，不是可直接替换的公开备用接口；未尝试认证或绕过 |
| `/feed.xml` | 200 | RSS 内容，不是完整 IQ/费用/耗时聚合源 |
| `/data/readout-comprehensive-intelligence.json`、`/data/readout-visual-spatial-reasoning.json`、根目录 `/intelligence-efficiency.json` | HTTP 200，但返回首页 HTML | 不是有效 JSON 数据源，证明不能只检查状态码 |

日期必须按原始时区解析。本机缓存的原始时间为 `2026-10-04T02:03:45+00:00`（北京时间 10 月 4 日 10:03:45）；不能把抓取时间作为判分时间。

## 备用路径的数值验证

题目表不是只有空壳或模型名称。把当前表按网站旧基准展示规则作只读计算，与本机最后一次成功读取的 schema 3 快照对照：

- 85 个可对照档位的 IQ 均匹配，包括 36 个 GPT 档位。
- 36 个 GPT 档位的费用中位数，在上游 6 位小数精度内全部匹配。
- 36 个 GPT 档位的平均耗时，在上游 0.01 分钟精度内全部匹配。
- 比对对象和当前原始表的数据期相同，所以这是兼容性证据，不是数据比缓存更新的证据。

旧网页算法的关键点：

1. 以当前表 `tasks` 与 `combos` 限定范围，格子键为 `task.id|model|effort`。
2. IQ 使用服务器提供的滚动 `score_sum` / `n` 汇总，再乘 150；不能改成每题均值再平均。虽然旧 schema 字段叫 `equal_latest_3`，实际已发布快照的数值应通过逐字段对照确认，不能只凭名称重定义。
3. 费用和耗时取各格子的 `ran_by` 最近最多三条。费用是中位数，不是均值，也不是格子里的预计 `cost`。
4. GPT ultra 排除没有 `cost_complete=true` 的费用；其他 GPT 档遵循旧网页对公开实际费用的规则。全部强制该标记会改变部分原有价格。该历史兼容规则不能被描述成每条非 ultra 记录都具备完整账本证明。
5. 耗时为有效正数秒数的平均，按原源分钟精度处理。

这次完成 GPT 三项指标及所有可对照 IQ 的离线验证。其他供应商的价格修正、峰谷价、harness 和完整账本规则未全面回归，不能宣称所有模型的全部指标都已完成生产适配。当前表也没有 `gpt-6.1-sol` 的旧基准成绩。

## ADR：优先恢复原榜单，另行支持新基准

状态：Proposed。以下为本次推荐，未修改当前产品行为。

### 选择

采用有校验的历史恢复路径，保留旧榜单与最后有效快照；把“数据仍可查看”和“实时服务已恢复”分开。新 Radar Bench 作为独立数据类型接入，不作为旧 IQ/费用/耗时榜的无提示替代品。

近期优先在客户端提供取数适配边界，不把修复阻塞在新建服务器上。若后续继续扩大发布，可把较大的题目表抓取与适配迁到自有服务，通过稳定的版本化聚合协议供客户端读取；该服务不会创造上游缺失的成绩。

### 数据选择规则

1. 原聚合入口可继续作为小体积探测源，但连续 502 后退避，避免每次刷新都重新等待失败。
2. 聚合失败且需恢复数据时，可以读取明确指定 `deep-swe` 的题目表，校验基准、版本、任务范围、滚动窗口、数值和时间，再生成有来源标记的历史快照。STALE 响应只进入历史恢复路径，不把主源标为健康；这条缓存未来可能失效，不能作为唯一恢复保障。
3. 有同口径最后成功快照时，优先保留它。备用结果同日期同内容只更新“检查时间”，不伪造新的评测日期、不追加重复趋势点。更旧数据不覆盖较新缓存。
4. 没有本地快照时，优先使用通过验证的题目表恢复旧榜；静态旧快照是最后备用，并明确显示历史日期。缺失指标保持为空，不当作零。
5. 新基准响应成功但无成绩时，状态为“暂无有效判分”，不作为网络故障，也不清掉旧榜。新分数采用 0–100 雷达分，新旧历史隔离，不转换成旧 IQ。
6. 社区主观评分若展示，单独命名与计分，不参与 IQ/费用/耗时综合加权。

### 用户可见结果

- 原榜单仍可展示，并可在当前公开逐题缓存仍可读时恢复。生产方案应保留经过验证的最后完整快照，避免依赖这条 CDN 缓存永久存在。
- 当聚合源失败、历史恢复源可用时，显示“数据源维护中，正在展示历史快照；最近判分：10 月 4 日”。连接详情保留 502 和备用源状态。
- 数据停更和连接失败分别表达；展开详情可查看来源、最后判分时间、最后检查时间及错误。
- 新基准未出成绩时明确显示空态，未来出现真实成绩再启用对应排名。

### 开销、风险与约束

- DeepSWE 原始表本次约 11.9 MB；不能让每个客户端按原 15–30 分钟频率持续下载。故障状态下采用缓存和较长退避（建议表恢复检查 6–12 小时，手动刷新合并），并在上游支持时使用条件请求。具体频率在实现时验证。
- raw table 包含公开参与者信息。适配时仅保留模型、档位、基准、指标、样本及时间，不把参与者信息写进发布聚合源。
- 旧时间相同但内容有修正时，需要内容指纹与数据修订记录，不能仅按日期忽略，也不能声称出现了新判分。
- 代码已支持 schema 3，但 `docs/data-source.md` 仍写 schema 2 静态来源，且写明不读取原始表；实施此方案时需要同步更新来源和请求范围文档。
- `current.json` 的 `api_access` 明确写有二次开发授权说明。诊断读取已完成；生产接入/公开分发原始表适配源前，应核对项目已有数据授权是否覆盖该用途，不能把匿名可读等同于新增使用授权。

### 对比其他方案

| 方案 | 评价 |
| --- | --- |
| 只等待旧聚合接口恢复 | 无恢复时限，不能解决客户端缺少备用路径的问题 |
| 只切换到新 Radar Bench | 当前 34 档无成绩，且没有原费用/耗时，直接切换会丢失主要功能 |
| 无条件切换静态 JSON | 10 月 1 日数据会覆盖 10 月 4 日缓存，造成倒退 |
| 社区评分替代 IQ | 有新数据但语义不同，不成立 |
| 抓首页上的可见数值 | 页面本身依赖同一批接口，容易取到旧截图、空占位或主观评分 |
| 先做完整自有数据平台 | 可降低长期分发流量和适配成本，但增加运维；不是本次恢复所必需 |
| 显式基准历史恢复 + 持久最后有效快照 + 新基准隔离 | 当前证据最充分、能保留原功能的推荐方案；不保证旧实时接口继续工作 |

### 实施验收

- 502/404/410、HTML 伪 JSON、超时、取消和来源结构改变分别验证；不得无限重试。
- 对保存的真实表与成功快照验证 85 档 IQ、36 档 GPT 费用/耗时精度；扩展到非 GPT 前补齐各价格口径的回归。
- 验证断网有缓存、全新安装、静态源更旧、相同时间修订、新基准全空以及缺失成本等情形。
- 多来源 ETag、历史、时间和错误状态分别保存；不把一个源的验证器用于另一个源。
- 不把累计次数、预计价签、缺失值、社区分或新基准分混进旧聚合。
- 编码与自动检查通过后再构建候选；用户安装验收和公开发布另行处理。

## 证据链接

- [主站](https://codexradar.com/)
- [众测站及重构公告](https://deng.codexradar.com/)
- [可用旧 DeepSWE 题目表](https://api.codexradar.com/api/v1/table?benchmark=deep-swe)
- [可用旧视觉题目表](https://api.codexradar.com/api/v1/table?benchmark=pompeii-adjacency)
- [新题库目录](https://api.codexradar.com/api/v1/library-catalog)
- [新基准绑定](https://codexradar.com/data/radar-bench-binding.json)
- [社区公开评分](https://codexradar.com/api/model-ratings?view=public&window=24h)
- [网站旧新基准展示脚本](https://codexradar.com/assets/radar-bench-display.mjs?v=six-model-efforts-v4)

## 逐 URL 检查索引

核查时间为北京时间 2026-10-06 13:09–13:15；可用性仅代表本次响应。表中 200 还需结合前文的日期、空成绩和 HTML 检查。

| HTTP | URL | 本机响应文件 |
| --- | --- | --- |
| 502 | `https://codexradar.com/api/intelligence-efficiency-metrics` | `96fac1c325b7.body` |
| 502 | `https://codexradar.com/api/intelligence-efficiency-metrics?refresh=1` | `bf1a87f4b4a3.body` |
| 502 | `https://codexradar.com/api/radar-insights` | `40c07e63553d.body` |
| 200 | `https://codexradar.com/api/model-ratings?view=public&history=14&window=7d` | `0ccd7597fafd.body` |
| 200 | `https://codexradar.com/api/model-ratings?view=public&window=24h` | `67470b400919.body` |
| 200 | `https://codexradar.com/data/intelligence-efficiency.json` | `d13614b4e0b7.body` |
| 200 | `https://codexradar.com/data/intelligence-efficiency-codex.json` | `5baf1dec7d01.body` |
| 200 | `https://codexradar.com/data/radar-legacy-comprehensive.json` | `76f91e501d2d.body` |
| 200 | `https://codexradar.com/data/radar-legacy-software.json` | `674405916a20.body` |
| 200 | `https://codexradar.com/data/radar-legacy-visual.json` | `2199cde69c9a.body` |
| 200 | `https://codexradar.com/data/radar-bench-binding.json` | `593abd91e0a3.body` |
| 200 | `https://codexradar.com/current.json` | `175d1ae29e20.body` |
| 200 | `https://codexradar.com/feed.xml` | `b4016347a09b.body` |
| 404 | `https://api.codexradar.com/api/v1/intelligence-efficiency` | `00f2a9d099f4.body` |
| 404 | `https://api.codexradar.com/api/v1/intelligence-efficiency?benchmark=deep-swe` | `9c7029d4970d.body` |
| 404 | `https://api.codexradar.com/api/v1/intelligence-efficiency?benchmark=pompeii-adjacency` | `d28c3f2a4332.body` |
| 200 | `https://api.codexradar.com/api/v1/table?benchmark=deep-swe` | `1fa0b1d31139.body` |
| 200 | `https://api.codexradar.com/api/v1/table?benchmark=pompeii-adjacency` | `bd3036183bf0.body` |
| 404 | `https://api.codexradar.com/api/v1/iq-history?benchmark=deep-swe` | `6e206c661705.body` |
| 404 | `https://api.codexradar.com/api/v1/iq-history?benchmark=pompeii-adjacency` | `2aa288f4a537.body` |
| 404 | `https://api.codexradar.com/api/v1/radar-insights?benchmark=deep-swe` | `77277183d7cb.body` |
| 200 | `https://api.codexradar.com/api/v1/library-catalog` | `b3e3c7175efd.body` |
| 200 | `https://api.codexradar.com/api/v1/benchmarks` | `e8fb6755d41b.body` |
| 404 | `https://api.codexradar.com/api/v1/leaderboard?view=live&benchmark=deep-swe` | `b09e01c5961f.body` |
| 410 | `https://api.codexradar.com/api/v1/radar-bench?model=gpt-6.1-sol&effort=high` | `5c73993cbf7f.body` |
| 200 | `https://api.codexradar.com/api/v1/radar-bench-score?model=gpt-6.1-sol&effort=high` | `f5feb2741221.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6.1-sol&effort=high&view=summary` | `157f76f90f54.body` |
| 200 | `https://api.codexradar.com/api/v1/library-table/deepswe15-20261003-v4` | `1909114ca6ec.body` |
| 200 | `https://api.codexradar.com/api/v1/library-leaderboard/deepswe15-20261003-v4` | `e2f7f38b104c.body` |
| 200 | `https://api.codexradar.com/api/v1/library-table/pompeii16-20261003-v2` | `4567ee23d34c.body` |
| 200 | `https://api.codexradar.com/api/v1/library-leaderboard/pompeii16-20261003-v2` | `1830a77df6e8.body` |
| 200 | `https://api.codexradar.com/api/v1/library-table/tb4-selected14-20261004-config64` | `513c931f7f4c.body` |
| 200 | `https://api.codexradar.com/api/v1/library-leaderboard/tb4-selected14-20261004-config64` | `0cbb13250f8e.body` |
| 200 | `https://api.codexradar.com/api/v1/library-table/science-selected19-20261004-config64` | `7ddad1f0fd5c.body` |
| 200 | `https://api.codexradar.com/api/v1/library-leaderboard/science-selected19-20261004-config64` | `d5b0bbed1f70.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6.1-sol&effort=low&view=summary` | `53fbe73355e4.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6.1-sol&effort=medium&view=summary` | `44c706e8adad.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6.1-sol&effort=xhigh&view=summary` | `97edbda9aa4f.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6.1-sol&effort=max&view=summary` | `95b189f513dd.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6.1-sol&effort=ultra&view=summary` | `d3b80a290e05.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-astra&effort=low&view=summary` | `6f31c11a9a32.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-astra&effort=medium&view=summary` | `de23bc939476.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-astra&effort=high&view=summary` | `9c0e1088400d.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-astra&effort=xhigh&view=summary` | `b343e4428d66.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-astra&effort=max&view=summary` | `835bc4269298.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-astra&effort=ultra&view=summary` | `f4a5dd79b1cd.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-sol&effort=low&view=summary` | `e5f0e40c6aa4.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-sol&effort=medium&view=summary` | `5a56b4437d3c.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-sol&effort=high&view=summary` | `141301cb9850.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-sol&effort=xhigh&view=summary` | `d4c0f98b0490.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-sol&effort=max&view=summary` | `7ffd6a8267f4.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-sol&effort=ultra&view=summary` | `f8c5e9513a2c.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-luna&effort=low&view=summary` | `b15dc22c651d.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-luna&effort=medium&view=summary` | `4cfe4bd12874.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-luna&effort=high&view=summary` | `fdeb887c86d1.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-luna&effort=xhigh&view=summary` | `a2d9736712a2.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-6-luna&effort=max&view=summary` | `6c72dc507da3.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-5.6-sol&effort=low&view=summary` | `99b1a0359a7f.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-5.6-sol&effort=medium&view=summary` | `3f58456ec15a.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-5.6-sol&effort=high&view=summary` | `be2518a061d5.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-5.6-sol&effort=xhigh&view=summary` | `dd87930574d0.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-5.6-sol&effort=max&view=summary` | `6e58e377b14f.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-5.6-sol&effort=ultra&view=summary` | `39866da80550.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-5.6-luna&effort=low&view=summary` | `a94f30a15ddc.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-5.6-luna&effort=medium&view=summary` | `a9b74a62059b.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-5.6-luna&effort=high&view=summary` | `658441665433.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-5.6-luna&effort=xhigh&view=summary` | `b03245eacc41.body` |
| 200 | `https://codexradar.com/api/radar-bench-score?model=gpt-5.6-luna&effort=max&view=summary` | `fb19cdec9ba5.body` |
| 200 | `https://codexradar.com/data/readout-comprehensive-intelligence.json` | `22a29c07ca39.body` |
| 200 | `https://codexradar.com/data/readout-visual-spatial-reasoning.json` | `22082c5474b4.body` |
| 200 | `https://codexradar.com/intelligence-efficiency.json` | `fd47342234b8.body` |
| 410 | `https://api.codexradar.com/api/v1/table` | `4260a46987ef.body` |
| 401 | `https://codexradar.com/api/v1/current` | `8cee977faccc.body` |
| 503 | `https://api.codexradar.com/api/v1/table?ui=20260818-unified-median-points-v1&benchmark=deep-swe` | `baf531801634.body` |
| 503 | `https://api.codexradar.com/api/v1/table?ui=20260818-unified-median-points-v1&benchmark=pompeii-adjacency` | `ca3a52490684.body` |
| 404 | `https://api.codexradar.com/api/v1/intelligence-efficiency?v=20260827-pompeii-trends-v1&benchmark=deep-swe` | `855111818f50.body` |
