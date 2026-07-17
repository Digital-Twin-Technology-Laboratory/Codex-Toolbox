# Codex Toolbox 数据源说明

本文档主要记录模型智商模块的 Codex Radar 来源。Token 与重置卡的只读边界见 [privacy.md](privacy.md)。

## 请求范围

- 端点：`https://codexradar.com/current.json`
- 应用不抓取网页 HTML，不请求需要 Key 的完整 API。
- 默认请求频率为 30 分钟一次，最短可设为 15 分钟。
- 客户端发送明确的 `User-Agent`、`Accept: application/json`、`If-None-Match` 和 `If-Modified-Since`。
- 同一时刻的重复刷新会合并为一个网络请求。

## 字段依赖

当前支持 `schema_version = 2.0`，核心数据位于 `model_iq.comparisons`：

- `label`、`model`、`reasoning_effort`
- `latest.date`、`latest.score`、`latest.cost_usd`、`latest.wall_seconds`
- `latest.passed`、`latest.tasks`、`latest.status`
- `recent_days` 中的日期、智商和耗时

未知字段会被忽略。单个核心指标缺失时，该模型只会被排除出相应榜单，不会导致整份快照失效。

## 费用历史

CodexRadar 的 `recent_days` 不保证提供历史费用。应用仅从安装后按模型和测试日期记录 `latest.cost_usd`：

- 同日同模型覆盖更新；
- 不追溯、不推算、不伪造历史费用；
- 少于两个本地数据点时显示空状态说明。

## 归属与授权状态

应用弹窗和“关于”页固定显示：

> 数据来自 Codex 雷达 codexradar.com

`current.json` 当前的 `api_access.message_zh` 声明完整 JSON API 与二次开发使用需要授权，并要求说明用途、展示位置、请求频率和是否商业化。

当前代码用于个人与小范围验证，并非 Codex 雷达官方客户端。在公开发布二进制、大范围分发或商业使用前，维护者应重新检查数据源当时声明并获得需要的授权。
