import CodexToolboxCore
import SwiftUI

struct TokenUsageSettingsView: View {
    @Bindable var appModel: AppModel
    @State private var confirmsClearHistory = false

    var body: some View {
        Form {
            Section("刷新") {
                Picker("刷新间隔", selection: refreshIntervalBinding) {
                    ForEach(UsageRefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
            }

            Section("菜单栏显示") {
                Toggle("显示估算成本", isOn: costEstimatesInMenuBarBinding)
                Text("仅控制展开菜单栏中的成本数字和 Token／成本趋势切换；设置页仍会计算并显示成本。新用户默认关闭。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("当前用量概览") {
                usageDetail("本机 Token", value: currentTokenText)
                usageDetail("API 等值成本（估算）", value: currentCostText)
                usageDetail("定价覆盖率", value: costCoverageText)
                usageDetail("本机 Credits", value: currentCreditsText)
                usageDetail("账户已用", value: accountUsedText)
                usageDetail("估算置信度", value: estimateConfidenceText)
            }

            Section("官方费率与 Credits") {
                Toggle("自动更新费率与价格", isOn: automaticRateUpdatesBinding)
                Picker("费率制度", selection: rateCardModeBinding) {
                    ForEach(RateCardMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前版本 \(appModel.rateCardState.manifest.currentVersion)")
                        Text(rateCardStatus)
                            .foregroundStyle(appModel.isRateCardStale ? .orange : .secondary)
                    }
                    .font(.caption)
                    Spacer()
                    Button("立即检查") {
                        Task { await appModel.refreshRateCard() }
                    }
                    .disabled(appModel.isRefreshingRateCard)
                }

                Text("自动模式仅在可确认 ChatGPT 计划时计算 Credits；API Key 用量不套用 ChatGPT Credits。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let errorMessage = appModel.rateCardState.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("API 等值成本明细") {
                usageDetail("新输入", value: componentCostText(\.freshInputUSD))
                usageDetail("缓存读取", value: componentCostText(\.cachedInputUSD))
                usageDetail("缓存写入", value: componentCostText(\.cacheWriteUSD))
                usageDetail("输出（含推理）", value: componentCostText(\.outputUSD))

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("价格版本 \(appModel.apiPriceCardState.manifest.currentVersion)")
                        Text(apiPriceStatus)
                            .foregroundStyle(appModel.isAPIPriceCardStale ? .orange : .secondary)
                    }
                    .font(.caption)
                    Spacer()
                    Button("立即检查") {
                        Task { await appModel.refreshRateCard() }
                    }
                    .disabled(appModel.isRefreshingRateCard || appModel.isRefreshingAPIPriceCard)
                }

                Text("OpenAI 使用官方 API 价格，其他供应商使用 models.dev；金额是 API 等值估算，并非 ChatGPT/Codex 订阅账单。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let errorMessage = appModel.apiPriceCardState.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Section("任务榜单") {
                Picker("榜单展开后", selection: expandedTaskLimitBinding) {
                    ForEach(UsageExpandedTaskLimit.allCases) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
                Text("默认显示 Top 3；点击任务卡后按此设置展开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("每日趋势") {
                Picker("趋势范围", selection: trendRangeBinding) {
                    ForEach(UsageTrendRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
            }

            Section("本机历史") {
                Button("清除 Token 历史…", role: .destructive) {
                    confirmsClearHistory = true
                }
                Text("清除后会立即从仍可读取的 rollout 文件重新回填；已删除文件对应的历史无法恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .confirmationDialog("清除本机 Token 历史？", isPresented: $confirmsClearHistory) {
            Button("清除并重新扫描", role: .destructive) {
                Task { await appModel.clearUsageHistory() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只删除 Codex Toolbox 的本机账本，不会修改 Codex 任务或账户数据。")
        }
    }

    private var refreshIntervalBinding: Binding<UsageRefreshInterval> {
        Binding(
            get: { appModel.settings.usageRefreshInterval },
            set: {
                appModel.settings.usageRefreshInterval = $0
                appModel.settingsDidChange()
            }
        )
    }

    private var trendRangeBinding: Binding<UsageTrendRange> {
        Binding(
            get: { appModel.settings.usageTrendRange },
            set: { appModel.settings.usageTrendRange = $0 }
        )
    }

    private var costEstimatesInMenuBarBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.showsAPICostEstimatesInMenuBar },
            set: { appModel.settings.showsAPICostEstimatesInMenuBar = $0 }
        )
    }

    private var expandedTaskLimitBinding: Binding<UsageExpandedTaskLimit> {
        Binding(
            get: { appModel.settings.usageExpandedTaskLimit },
            set: { appModel.settings.usageExpandedTaskLimit = $0 }
        )
    }

    private var automaticRateUpdatesBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.automaticRateCardUpdatesEnabled },
            set: {
                appModel.settings.automaticRateCardUpdatesEnabled = $0
                appModel.settingsDidChange()
            }
        )
    }

    private var rateCardModeBinding: Binding<RateCardMode> {
        Binding(
            get: { appModel.settings.rateCardMode },
            set: {
                appModel.settings.rateCardMode = $0
                appModel.settingsDidChange()
            }
        )
    }

    private var rateCardStatus: String {
        if appModel.isRateCardStale { return "费率可能过期" }
        switch appModel.rateCardState.source {
        case .bundled: return "内置回退数据"
        case .cached: return "上次有效缓存"
        case .remote: return "已从项目托管清单校验"
        }
    }

    private func usageDetail(_ title: String, value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .textSelection(.enabled)
        }
    }

    private var todaySummary: DailyUsageSummary? {
        appModel.usageHistory?.summary(for: dayKey(Date()))
    }

    private var currentTokenText: String {
        todaySummary?.totalTokens.formatted(.number.grouping(.automatic)) ?? "--"
    }

    private var currentCreditsText: String {
        guard let summary = todaySummary, let credits = summary.totalCredits else { return "--" }
        let value = credits > 0 && credits < 0.01
            ? "<0.01"
            : String(format: "%.2f", credits)
        return "\(creditPrefix(summary.creditPrecision))\(value) Cr"
    }

    private var currentCostText: String {
        guard let summary = todaySummary else { return "--" }
        return MetricFormatter.apiCost(summary.totalCostUSD, precision: summary.costPrecision)
    }

    private var costCoverageText: String {
        guard let summary = todaySummary, summary.totalTokens > 0 else { return "--" }
        return String(format: "%.1f%%", summary.costCoverage * 100)
    }

    private func componentCostText(_ keyPath: KeyPath<APICostBreakdown, Decimal>) -> String {
        guard let breakdown = todaySummary?.costBreakdown else { return "--" }
        return MetricFormatter.apiCost(breakdown[keyPath: keyPath])
    }

    private var apiPriceStatus: String {
        if appModel.isAPIPriceCardStale { return "价格来源可能过期" }
        switch appModel.apiPriceCardState.source {
        case .bundled: return "内置 OpenAI + models.dev 快照"
        case .cached: return "上次有效缓存"
        case .remote: return "已从项目托管清单校验"
        }
    }

    private var accountUsedText: String {
        let windows = (appModel.resetCreditsSnapshot?.quotaWindows ?? []).filter {
            Date() < $0.resetsAt
        }
        guard !windows.isEmpty else { return "--" }
        return windows.map {
            "\($0.displayName) \(String(format: "%.1f%%", $0.usedPercent))"
        }
        .joined(separator: " / ")
    }

    private var estimateConfidenceText: String {
        let estimates = appModel.taskQuotaEstimatesByDuration.values.flatMap(\.values)
        guard !estimates.isEmpty else { return "--" }
        let confidence: QuotaEstimateConfidence
        if estimates.contains(where: { $0.confidence == .low }) {
            confidence = .low
        } else if estimates.contains(where: { $0.confidence == .medium }) {
            confidence = .medium
        } else {
            confidence = .high
        }
        return estimates.contains(where: \.hasConcurrentInterference)
            ? "\(confidence.displayName) · 并发干扰"
            : confidence.displayName
    }

    private func creditPrefix(_ precision: CreditEstimatePrecision?) -> String {
        switch precision {
        case .exact: ""
        case .upperBound: "≤"
        case .lowerBound: "≥"
        case .approximate, nil: "≈"
        }
    }

    private func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

}
