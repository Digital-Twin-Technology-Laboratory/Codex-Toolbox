import Foundation

public struct UsageTrendPoint: Identifiable, Sendable {
    public let date: Date
    public let dateKey: String
    public let tokens: Int64
    public let costUSD: Double?
    public let costPrecision: CostEstimatePrecision?
    public var id: String { dateKey }
}

public struct UsagePresentation: Sendable {
    public let summariesByDay: [String: DailyUsageSummary]
    public let trendPoints: [UsageTrendPoint]
    public let calendarDay: Date
    public let timezoneIdentifier: String

    public static func prepare(history: UsageHistory, now: Date, calendar: Calendar) throws -> Self {
        var summaries: [String: DailyUsageSummary] = [:]
        for day in history.days {
            try Task.checkCancellation()
            if summaries[day.dateKey] == nil { summaries[day.dateKey] = day }
        }
        var points: [UsageTrendPoint] = []
        for offset in (0..<90).reversed() {
            try Task.checkCancellation()
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            let summary = summaries[key]
            points.append(UsageTrendPoint(date: date, dateKey: key, tokens: summary?.totalTokens ?? 0,
                costUSD: summary?.totalCostUSD.map { NSDecimalNumber(decimal: $0).doubleValue },
                costPrecision: summary?.costPrecision))
        }
        return Self(summariesByDay: summaries, trendPoints: points,
            calendarDay: calendar.startOfDay(for: now), timezoneIdentifier: calendar.timeZone.identifier)
    }
}

public struct QuotaComputationInput: Sendable {
    public let history: UsageHistory
    public let nativeSnapshots: [NativeTaskQuotaSnapshot]
    public let accountKey: String
    public let accountSnapshot: ResetCreditsSnapshot?
    public let unattributedSince: Date?
    public let now: Date

    public init(history: UsageHistory, nativeSnapshots: [NativeTaskQuotaSnapshot], accountKey: String,
                accountSnapshot: ResetCreditsSnapshot?, unattributedSince: Date?, now: Date) {
        self.history = history; self.nativeSnapshots = nativeSnapshots; self.accountKey = accountKey
        self.accountSnapshot = accountSnapshot; self.unattributedSince = unattributedSince; self.now = now
    }
}

public struct QuotaComputationOutput: Sendable {
    public let daily: [Int: [String: DailyTaskQuotaValue]]
    public let windows: [Int: [String: TaskQuotaEstimate]]

    public static func calculate(_ input: QuotaComputationInput) throws -> Self {
        try Task.checkCancellation()
        var daily = DailyTaskQuotaAnalyzer.values(history: input.history, snapshots: input.nativeSnapshots,
            accountKey: input.accountKey, now: input.now)
        try Task.checkCancellation()
        let fallback = TaskQuotaEstimator.dailyEstimates(history: input.history, accountKey: input.accountKey,
            now: input.now, accountSnapshot: input.accountSnapshot, unattributedSince: input.unattributedSince)
        for (duration, tasks) in fallback {
            try Task.checkCancellation()
            for (id, percent) in tasks where daily[duration]?[id] == nil {
                daily[duration, default: [:]][id] = DailyTaskQuotaValue(percent: percent, isExact: false,
                    updatedAt: input.history.generatedAt,
                    help: "本机逐轮额度观测校准的当日估算；未标账户历史仅按已验证套餐和窗口作近似匹配，不回填账户身份。")
            }
        }
        let supported = Set(TaskQuotaMetric.supported(by: input.accountSnapshot?.quotaWindows ?? []).map(\.rawValue))
        daily = daily.filter { supported.contains($0.key) }
        var windows: [Int: [String: TaskQuotaEstimate]] = [:]
        for window in input.accountSnapshot?.quotaWindows ?? [] where input.now < window.resetsAt {
            try Task.checkCancellation()
            windows[window.durationMinutes] = TaskQuotaEstimator.estimates(history: input.history,
                window: window, now: input.now, accountKey: input.accountKey)
        }
        try Task.checkCancellation()
        return Self(daily: daily, windows: windows)
    }
}
