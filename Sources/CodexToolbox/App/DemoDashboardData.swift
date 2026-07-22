#if DEBUG
import CodexToolboxCore
import Foundation

actor DemoUsageReader: CodexUsageReading, UsageHistoryClearing {
    func readUsage(now: Date, calendar: Calendar) async throws -> UsageHistory {
        let totals: [Int64] = [182_400, 296_800, 241_100, 418_600, 387_900, 512_300, 684_200]
        let days = totals.enumerated().compactMap { index, total -> DailyUsageSummary? in
            guard let date = calendar.date(byAdding: .day, value: index - 6, to: now) else { return nil }
            let key = dayKey(date, calendar: calendar)
            if index == totals.count - 1 {
                return DailyUsageSummary(
                    dateKey: key,
                    totalTokens: total,
                    tasks: [
                        DailyTaskUsage(
                            dateKey: key,
                            rootTaskID: "dashboard",
                            title: "为 Codex Toolbox 优化菜单栏看板",
                            tokens: 286_400,
                            descendantCount: 2
                        ),
                        DailyTaskUsage(
                            dateKey: key,
                            rootTaskID: "usage",
                            title: "审计本机 Token 用量聚合算法",
                            tokens: 191_700,
                            descendantCount: 1
                        ),
                        DailyTaskUsage(
                            dateKey: key,
                            rootTaskID: "release",
                            title: "完善 PKG 与 DMG 发布流程",
                            tokens: 132_800,
                            descendantCount: 0
                        ),
                        DailyTaskUsage(
                            dateKey: key,
                            rootTaskID: "docs",
                            title: "同步 GitHub README 与隐私说明",
                            tokens: 18_000,
                            descendantCount: 0
                        ),
                        DailyTaskUsage(
                            dateKey: key,
                            rootTaskID: "quota",
                            title: "实现账户额度占比估算",
                            tokens: 15_000,
                            descendantCount: 0
                        ),
                        DailyTaskUsage(
                            dateKey: key,
                            rootTaskID: "charts",
                            title: "为模型趋势图增加时间范围",
                            tokens: 12_000,
                            descendantCount: 0
                        ),
                        DailyTaskUsage(
                            dateKey: key,
                            rootTaskID: "tests",
                            title: "补充用量与账户窗口测试",
                            tokens: 10_000,
                            descendantCount: 0
                        ),
                        DailyTaskUsage(
                            dateKey: key,
                            rootTaskID: "accessibility",
                            title: "检查 VoiceOver 榜单提示",
                            tokens: 8_000,
                            descendantCount: 0
                        ),
                        DailyTaskUsage(
                            dateKey: key,
                            rootTaskID: "migration",
                            title: "验证旧版缓存迁移",
                            tokens: 6_000,
                            descendantCount: 0
                        ),
                        DailyTaskUsage(
                            dateKey: key,
                            rootTaskID: "release-notes",
                            title: "更新发布说明",
                            tokens: 4_300,
                            descendantCount: 0
                        )
                    ],
                    isComplete: true
                )
            }
            return DailyUsageSummary(
                dateKey: key,
                totalTokens: total,
                tasks: [],
                isComplete: true
            )
        }
        return UsageHistory(
            generatedAt: now,
            timezoneIdentifier: calendar.timeZone.identifier,
            days: days,
            quotaObservations: quotaObservations(now: now)
        )
    }

    func clearHistory() async throws {}

    private func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func quotaObservations(now: Date) -> [LocalQuotaUsageObservation] {
        let fiveHourReset = now.addingTimeInterval(3 * 3_600)
        let weeklyReset = now.addingTimeInterval(4 * 86_400)
        func observation(
            offset: TimeInterval,
            task: String,
            tokens: Int64,
            fiveHourPercent: Double,
            weeklyPercent: Double
        ) -> LocalQuotaUsageObservation {
            LocalQuotaUsageObservation(
                timestamp: now.addingTimeInterval(offset),
                rootTaskID: task,
                tokenIncrement: tokens,
                windows: [
                    AccountQuotaWindow(
                        durationMinutes: 300,
                        usedPercent: fiveHourPercent,
                        resetsAt: fiveHourReset
                    ),
                    AccountQuotaWindow(
                        durationMinutes: 10_080,
                        usedPercent: weeklyPercent,
                        resetsAt: weeklyReset
                    )
                ]
            )
        }
        return [
            observation(offset: -600, task: "dashboard", tokens: 0, fiveHourPercent: 16.4, weeklyPercent: 40.7),
            observation(offset: -550, task: "dashboard", tokens: 71_600, fiveHourPercent: 16.4, weeklyPercent: 40.7),
            observation(offset: -500, task: "dashboard", tokens: 71_600, fiveHourPercent: 16.9, weeklyPercent: 41.2),
            observation(offset: -450, task: "dashboard", tokens: 71_600, fiveHourPercent: 16.9, weeklyPercent: 41.2),
            observation(offset: -400, task: "dashboard", tokens: 71_600, fiveHourPercent: 17.4, weeklyPercent: 41.7),
            observation(offset: -350, task: "usage", tokens: 95_850, fiveHourPercent: 17.4, weeklyPercent: 41.7),
            observation(offset: -300, task: "usage", tokens: 95_850, fiveHourPercent: 18.4, weeklyPercent: 42.7),
            observation(offset: -250, task: "release", tokens: 132_800, fiveHourPercent: 18.4, weeklyPercent: 42.7),
            observation(offset: -200, task: "docs", tokens: 18_000, fiveHourPercent: 18.4, weeklyPercent: 42.7),
            observation(offset: -180, task: "quota", tokens: 15_000, fiveHourPercent: 18.4, weeklyPercent: 42.7),
            observation(offset: -160, task: "charts", tokens: 12_000, fiveHourPercent: 18.4, weeklyPercent: 42.7),
            observation(offset: -140, task: "tests", tokens: 10_000, fiveHourPercent: 18.4, weeklyPercent: 42.7),
            observation(offset: -120, task: "accessibility", tokens: 8_000, fiveHourPercent: 18.4, weeklyPercent: 42.7),
            observation(offset: -100, task: "migration", tokens: 6_000, fiveHourPercent: 18.4, weeklyPercent: 42.7),
            observation(offset: -80, task: "release-notes", tokens: 4_300, fiveHourPercent: 18.4, weeklyPercent: 42.7)
        ]
    }
}

actor DemoResetCreditsReader: AccountRateLimitsReading {
    func readResetCredits() async throws -> ResetCreditsSnapshot {
        let now = Date()
        return ResetCreditsSnapshot(
            availableCount: 3,
            credits: [
                ResetCreditSummary(
                    sequence: 1,
                    status: "available",
                    grantedAt: now.addingTimeInterval(-2 * 86_400),
                    expiresAt: now.addingTimeInterval(2 * 86_400)
                ),
                ResetCreditSummary(
                    sequence: 2,
                    status: "available",
                    grantedAt: now.addingTimeInterval(-86_400),
                    expiresAt: now.addingTimeInterval(5 * 86_400)
                ),
                ResetCreditSummary(
                    sequence: 3,
                    status: "available",
                    grantedAt: now,
                    expiresAt: now.addingTimeInterval(7 * 86_400)
                )
            ],
            quotaWindows: [
                AccountQuotaWindow(
                    durationMinutes: 300,
                    usedPercent: 18.4,
                    resetsAt: now.addingTimeInterval(3 * 3_600)
                ),
                AccountQuotaWindow(
                    durationMinutes: 10_080,
                    usedPercent: 42.7,
                    resetsAt: now.addingTimeInterval(4 * 86_400)
                )
            ],
            fetchedAt: now
        )
    }
}
#endif
