# Codex Toolbox 数据源说明

本文档主要记录模型智商模块的 Codex Radar 来源。Token 与重置卡的只读边界见 [privacy.md](privacy.md)。

## 请求范围

- 端点：`https://codexradar.com/data/intelligence-efficiency.json`
- 应用不抓取网页 HTML，不请求网页使用的原始任务表或需要 Key 的完整 API。
- 默认请求频率为 30 分钟一次，最短可设为 15 分钟。
- 客户端发送明确的 `User-Agent`、`Accept: application/json`、`If-None-Match` 和 `If-Modified-Since`。
- 同一时刻的重复刷新会合并为一个网络请求。
- 聚合快照由 Codex 雷达通过 CDN 发布，页面与应用看到的更新时间可能相差约 10 分钟；应用始终展示快照自己的 `source_updated_at`，不把本机下载时间冒充数据时间。

## 字段依赖

当前支持 `schema = 2`，核心数据位于 `points`：

- `model`、`effort`、`iq`
- `passed`、`valid_tasks`
- `average_price_usd`、`average_minutes`
- 顶层 `source_updated_at`
- `history[].at` 与其中同结构的 `points`

应用把 `average_minutes` 转换为内部统一使用的秒数；费用和耗时均是每题平均值，不再使用旧 `current.json` 的累计值。未知字段和无效单点会被忽略；单个核心指标缺失时，该模型只会被排除出相应榜单，不会导致其他榜单或整份快照失效。整份快照没有任何有效模型时才判定刷新失败。

## 历史、综合分与缓存迁移

- 智商、费用和耗时趋势优先使用 `history` 中的同口径观察点。
- 只有远端费用历史完全缺失时，才从安装后的新聚合快照继续积累平均费用，不做累计值换算或伪造。
- 历史观察按快照时间排序，不依赖 CDN 返回的数组顺序。
- “综合最佳”不是 Codex 雷达直接发布的字段，而是应用基于智商、平均费用和平均耗时的百分位，按用户配置权重在本机计算。
- 新数据源使用 `radar-intelligence-efficiency-v2.json`；旧 `radar-latest.json` 和 Show Codex IQ 快照不会迁移、覆盖或删除，避免累计值与平均值混用。

## 模型标识兼容

已在旧快照出现的模型档位继续沿用原 ID，因此用户设置的菜单栏简称不会丢失。Sol ultra/max、Terra ultra、DeepSeek V4 Flash 等新增档位使用由 `model + effort` 生成的稳定 ID；未来出现未知模型时也不会因客户端没有硬编码名称而被整批过滤。

## 归属与授权状态

应用弹窗和“关于”页固定显示：

> 数据来自 Codex 雷达 codexradar.com

公开 URL 可访问不等于自动获得再分发或商业使用授权。当前代码并非 Codex 雷达官方客户端；在公开发布二进制、大范围分发或商业使用前，维护者应重新检查数据提供方当时的声明，并取得所需授权。
