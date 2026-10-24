# 2026-10-17 Codex Toolbox 卡顿核查

后续状态（2026-10-22）：用户要求留待后续更新修复；已补充[高能耗核查](2026-10-22-energy-investigation.md)及[待修清单](../plans/2026-10-22-performance-energy-fix-backlog.md)，并加入 PROJECT_MEMORY.md。本文件的 10/17 基准与现场记录保持为历史证据。

## 结论与边界

已确认 1.4.1 / Build 63 存在重复大量磁盘写入。用户补充柱状图选日、用量明细及滚动触发后，进一步实测发现主线程调用的历史额度估算单次约 2.71–2.72 秒，是与症状高度吻合的明确性能缺陷，建议准备客户端更新。尚未通过界面复现并捕获原始转圈现场，因此不宣称已排除其他界面问题。

本次未修改代码、用户设置或缓存，未重启或替换应用，未发布更新。

## 当前设备证据

- 已安装及运行：/Applications/Codex Toolbox.app，1.4.1 (63)，arm64，UUID E9B554F6-C5D6-3380-9A21-02FE4ED7C0E6。
- 系统：macOS 27.0.1 (26A434)，Apple M4 Pro，48 GB 内存。
- 17:27 的 5 秒采样主线程正常等待事件；后续 15 秒采样也几乎全部等待事件，未捕获持续阻塞。采样位于 /tmp/codex-toolbox-hang-sample.txt 与 /tmp/codex-toolbox-ui-sample.txt，临时文件可能被系统清理。
- 采样时 footprint 159.4 MB，峰值 580.2 MB；17:28 系统 CPU 约 88% 空闲，当前未显示计算资源耗尽，不能反推此前卡顿时资源状态。
- 17:24:51–17:24:52 日志出现 RBLayer: full image queue、RBDrawable: no surface, dropping frame。属于渲染异常线索，不足以证明主因。
- 自动化读取应用状态两次超时，无法完成点击复现；该超时本身不作为应用死锁证据。

## 重复写盘的系统证据

系统诊断原文件均位于 /Library/Logs/DiagnosticReports/：

- Codex Toolbox_2026-10-14-201721_MacBook-Pro.diag：16:22:25–20:17:20，8602 MB / 14095 秒，Event: disk writes。
- Codex Toolbox_2026-10-17-154311_MacBook-Pro.diag：13:22:50–15:43:10，2156.18 MB / 8420 秒，Event: disk writes。

两个报告均为 Build 63、相同二进制 UUID；主要写入栈为 Swift 异步任务到 Foundation Data.write。系统 Action taken 均为 none，不能解释为系统因告警强制退出。缺少匹配调试符号，尚未将报告中的地址精确映射到源码函数。

## 源码与文件核查

- ~/Library/Application Support/CodexToolbox/usage-ledger.json 约 53 MiB；native-task-quota-v1.json 约 17 MiB。
- AppModel.reconfigureSchedulers 每分钟检查活跃账户额度；最近 15 分钟有本地活动时调用 refreshResetCredits。
- refreshResetCredits 调用 recordAccountQuotaSnapshot；LocalCodexUsageReader.recordAccountQuotaSnapshot 读取整个账本、更新观察记录并整份保存。
- UsageLedgerStore.save 使用 prettyPrinted/sortedKeys JSON 编码和原子整文件写入；readUsage 也会整份保存。
- NativeTaskQuotaStore.append 读取历史快照并整份写入；AppModel.refreshNativeTaskQuota 在每个批次 append 后再次加载快照并重新计算。
- 用量读取及缓存存储使用 actor，不能仅凭上述整份写入就断言同步阻塞主线程。

## 建议修复及验收

优先优化小量新增额度记录引起的大账本整份读写，合并任务额度批次落盘，减少无变化写入，保留历史数据与账户隔离语义。无需改变界面。

需补充精确点击步骤并在复现时采样，区分界面布局/渲染、主线程计算与后台 I/O。修复验收应包括相同数据规模的读写量对比、持续刷新、菜单栏打开/收起及原触发操作；测试通过和新包安装不能替代实际卡顿消失的确认。

## 用户补充后的计算基准

用户确认触发点为柱状图某根柱子、用量明细及上下滚动。

使用当前 Core 源码以 swiftc -O 编译独立探针，账本复制到 /tmp/toolbox-perf-audit/ledger.json；数据库和 rollout 只读，应用原始账本未被探针写入。探针不调用远程额度服务。代码与末次结果保存在 /tmp/toolbox-perf-audit/Probe.swift、results.txt。

- 输入：144 天、约 61,755 条额度观测、25,384 条原生快照；活跃会话导致各次观测数略有变化。
- readUsage（副本读写及历史汇总）：1.31–1.49 秒，该路径原本在独立 actor 上，不能据此归因主线程阻塞。
- TaskQuotaEstimator.dailyEstimates：两次独立运行分别 2.7218 秒、2.7072 秒。
- DailyTaskQuotaAnalyzer.values：约 0.113–0.123 秒。
- 测试使用快照末项账户键，未输出账户键；dailyEstimates 未提供 accountSnapshot/unattributedSince，因此不是完整 UI 调用的逐参数复刻。数据规模和源码路径真实，但完整应用耗时仍需交互采样确认。

关键调用关系：TokenUsageModuleView 日期变化 → updateQuotaPriorities → AppModel.prioritizeNativeQuotaTasks → refreshNativeTaskQuota(force: true) → 每批结果后 recalculateTaskQuotaEstimates。AppModel 为 @MainActor；recalculateTaskQuotaEstimates 同步调用上述两个计算函数，此外还计算当前额度窗口估算。函数运行期间主线程无法处理界面事件。

dailyEstimates 会遍历多个历史额度窗口，每个窗口调用 estimates，后者又在 calibrationRates 中扫描历史窗口和观测。每批刷新重复执行这条路径，对当前历史规模已产生秒级开销。切换日期会在优先任务集合变化时启动刷新；滚动本身不一定启动计算，但会被同时运行的主线程计算阻塞。

修复优先级调整：先将额度计算移出主线程，并对刷新请求合并、取消过期结果、校验账户和数据版本；随后优化重复历史扫描及整文件写入。保持现有 UI、额度口径、账户隔离与历史数据。修复后还需验证原始交互，不能只凭基准下降宣布完全解决。
