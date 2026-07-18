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
            days: days
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
