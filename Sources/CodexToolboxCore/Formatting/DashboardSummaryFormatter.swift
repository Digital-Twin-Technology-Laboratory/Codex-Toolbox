import Foundation

/// Text-only summaries shared by the dashboard and offline regression tests.
public enum DashboardSummaryFormatter {
    public static func usage(
        _ summary: DailyUsageSummary?,
        isLoading: Bool,
        showsCost: Bool
    ) -> String {
        if isLoading { return "正在读取…" }
        guard let summary else { return "今日暂无数据" }
        let suffix = summary.isComplete ? "" : " · 不完整"
        let cost = showsCost
            ? summary.totalCostUSD.map {
                " · \(MetricFormatter.apiCost($0, precision: summary.costPrecision))"
            } ?? ""
            : ""
        return "今日 \(summary.totalTokens.formatted(.number.grouping(.automatic)))\(cost)\(suffix)"
    }

    public static func account(
        _ snapshot: ResetCreditsSnapshot?,
        isLoading: Bool,
        isStale: Bool,
        now: Date
    ) -> String {
        if isLoading { return "正在读取…" }
        guard let snapshot else { return "暂无数据" }
        let window = snapshot.quotaWindows.first { $0.durationMinutes == 10_080 }
            ?? snapshot.quotaWindows.first { $0.durationMinutes == 300 }
            ?? snapshot.quotaWindows.first
        let quota: String
        if let window {
            quota = window.resetsAt > now
                ? window.displayName + remainingPercent(100 - window.usedPercent)
                : "额度待更新"
        } else {
            quota = "额度暂无数据"
        }
        return quota + " · 重置卡 \(snapshot.availableCount) 张"
    }

    public static func remainingPercent(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1))) + "%"
    }
}
