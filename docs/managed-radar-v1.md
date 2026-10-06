# Codex Toolbox 榜单适配服务

实现版本：客户端 1.4.1 / Build 59。此文描述实现与运维；部署验证结果另见末尾记录。网站 CMS、通行密钥、计数器和静态内容发布均不参与此服务。

## 数据协议 v1

公开 `GET/HEAD https://zjwspace.cn/api/codex-toolbox/v1/radar.json`，JSON UTF-8，ETag 条件读取，缓存 60 秒。同步由定时进程运行，访问接口不会调用上游。除精确路径外没有公开管理/文件目录；写请求拒绝。

顶层字段：

| 字段 | 含义 |
| --- | --- |
| `schemaVersion` | 固定 `codex-toolbox.radar.v1`；破坏性变化另开版本并保留 v1 |
| `revision` | 每次发布单调递增的正整数；相同编号的内容不得改变 |
| `generation` | 首次发布、显式启用或回退递增；允许未在线客户端跨过中间发布识别切换 |
| `change` | `sync`、`status`、`activation`、`rollback` |
| `dataset` | `id`、`name`、`scoreLabel`、`semanticsKey`；口径标识包含任务集合和统计方法 |
| `status` | `current`、`historical`、`upstream_error`、`no_data` |
| `sourceUpdatedAt` | 实际成绩日期；上游没提供时为 null，不用同步时间冒充 |
| `publishedAt` / `checkedAt` / `lastSuccessAt` | 发布、检查、最后成功同步时间（ISO 8601 带时区） |
| `sources` | 公开来源名称 `name` 和 HTTPS `url` |
| `models` | 模型档位数组，下述格式 |

模型字段：`id`、`label`、`model`、`reasoningEffort`、`latest`、`recentDays`。同一模型档位的 ID 沿用客户端旧映射。`latest` 与历史记录的键包括 `date`、`score`、`passed`、`tasks`、`cost_usd`、`wall_seconds`、`combined_cost_index`、`priceAggregation`、`priceBasis`、`priceSamples`、`durationSamples`。时间未知时 latest.date 为 `""`，不生成历史点。历史最多 90 条，必须有真实成绩日期，不能跨基准/口径连接。

评分为有限数值，越高越好；费用单位美元、耗时秒，缺失用 null/省略，不能填 0。依赖不完整指标的综合排名不可用。允许新增可选字段；旧客户端忽略未知可选字段。未知协议版本/状态、重复档位、无效数值、日期倒退拒绝覆盖缓存。合法 `no_data` 仅用于没有成绩的冷启动；已有客户端缓存保留。

## 适配与发布

- DeepSWE 表仅接受 schema 1 / deep-swe / binary-majority / rolling_window 3。评分沿用 `150 × sum(score_sum 或 p) / sum(n)`（两位小数）。GPT 费用是每格最近三次有效运行的中位数（六位小数），ultra 排除不完整费用；耗时为有效运行平均分钟保留两位后换算为秒。输入口径变化拒绝自动接收。
- 非 GPT 费用存在尚未验证的上游纠正逻辑，当前置空；旧 Radar 综合成本指数也置空，不重新发明公式。本地加权可对完整指标的 GPT 档位计算。状态固定 historical，不能把 Cloudflare STALE 响应当实时恢复。
- Radar Bench 验证 binding、任务集合 hash、catalog、模型档位、64 题覆盖和评分策略；完整且有限的 0–100 分可发布，空结果不能启用。公开摘要不提供判分日期、费用、耗时，所以这些字段不补造。它目前只作为可预览/手动启用的适配器。
- 兼容的旧历史快照每 6 小时检查一次，仅保留各模型最近 90 个真实日期点；历史费用缺少统计口径时不接入费用曲线。历史读取失败不阻止有效榜单发布。
- 默认同步 DeepSWE，每 30 分钟检查，失败后 60/120/240/360 分钟退避；force 绕过退避但不绕过回退暂停。服务器启动后 2 分钟检查。单次进程最多 15 分钟、256 MiB、50% CPU。
- `state.json` 是规范状态，使用 fsync + 原子替换；对外 JSON 随后原子导出，重启会修复中断或损坏的导出。快照存档不记录原始逐题表/参与者信息。回退暂停和发布在同一规范状态写入中完成。
- 有效旧数据一直保留。HTTP 成功和源成绩更新分别记录。同步异常仅更改状态/修订号；原成绩日期不变。同口径时间倒退需要显式启用/回退。
- Nginx 静态 ETag 由文件长度与秒级 mtime 组成；发布器保证输出 mtime 单调递增，避免同秒同长度数据误判 304。忽略 If-Modified-Since，以 ETag 为准。快速手动发布可能令文件 mtime 略晚于实际时钟，正文时间仍真实。

## 命令行

在服务器 `/srv/personal-site/toolbox-service` 执行：

```sh
python3 -m server.toolbox_feed --root /srv/personal-site/toolbox-data status
python3 -m server.toolbox_feed --root /srv/personal-site/toolbox-data sync --force
python3 -m server.toolbox_feed --root /srv/personal-site/toolbox-data --config /path/to/reviewed-config.json preview
python3 -m server.toolbox_feed --root /srv/personal-site/toolbox-data activate CANDIDATE_SHA256
python3 -m server.toolbox_feed --root /srv/personal-site/toolbox-data rollback REVISION
python3 -m server.toolbox_feed --root /srv/personal-site/toolbox-data resume
```

配置键 `adapter`（deep-swe / radar-bench）、`tableURL`、`bindingURL`、`scoreURL`、`historyURL`；只接受 HTTPS。配置文件只在初始化或 preview 时使用，编辑文件不会悄悄启用新来源。preview 保存在私有 candidates，24 小时内可启用，内容 hash 校验防止预览后被改写。启用是操作者确认基准与成绩含义的步骤，后期管理页复用此流程，无需更新客户端。所有命令通过同一个文件锁串行执行。

`rollback` 发布新的 revision/generation 并暂停自动同步，直到 resume 或新的 activate。不要直接把 public/radar.json 拷贝回旧文件或重置修订计数，否则客户端会拒绝倒退。

## 部署与恢复

1. 提交并推送网站分支，ECS 仓库只读 fetch。用指定完整 commit 的 git archive 提取本模块、测试和 ops 文件到 `/srv/personal-site/toolbox-releases/COMMIT`，不切换既有网站仓库/静态/CMS 版本。
2. 记录线上 `/etc/nginx/sites-available/personal-site-public` 的 SHA-256。
3. 执行 `python3 /srv/personal-site/toolbox-releases/COMMIT/ops/deploy_toolbox.py --commit COMMIT --expected-config-sha SHA`。脚本获取网站共享部署锁，备份触及的 Nginx/systemd 配置及原服务链接，先验证测试及非空快照，再启用路由和 timer。
4. 验证 HTTPS 正文、ETag/304、POST 拒绝、私有状态不暴露、主站健康、后台匿名401。部署清单位于 `/srv/personal-site/deployments/toolbox-COMMIT/manifest.json`。
5. 代码/路由回退：同一脚本加 `--rollback`，SHA 应为此时实际 Nginx 配置哈希。要求当前仍是该 Toolbox 版本，防止覆盖他人新部署；有效数据保留。

监测 `systemctl list-timers toolbox-feed.timer`、`systemctl status toolbox-feed.service` 与 CLI status 的 failures/nextAttemptAt/lastError/checkedAt。上游故障写公开状态，不以 systemd 进程成功代表数据新鲜。服务端错误详情只保留异常类型；客户端不上传账户、Token 日志或偏好。

备份整个 toolbox-data 与 deployments/toolbox-*（包含规范状态和修订存档）。恢复必须保留 revision/generation 单调性；若数据状态丢失，先恢复最新备份并确认编号高于线上最后发布，再重新发布。不要回退 CMS 数据库。

## 验证

运行 `python3 -m unittest server.test_toolbox_feed server.test_deploy_toolbox -v`。客户端协议测试使用两个服务端适配器生成的合成样本，真实数据另外校对，不把合成分数发布到线上。客户端冷启动、升级、断网、304、切换、回退和重启测试与 UI 手动验收分开记录。

后期若上游变化，只修改服务端 adapter 并通过契约测试；既有 v1 支持的评分/缺失指标/基准切换无需发客户端。新增客户端未知的能力、反向评分尺度、不同维度或原生功能仍须评估新版协议和客户端更新。
