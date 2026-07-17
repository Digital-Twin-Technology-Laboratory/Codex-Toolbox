import Charts
import CodexToolboxCore
import SwiftUI

struct TokenUsageModuleView: View {
    @Bindable var appModel: AppModel
    @Namespace private var glassNamespace

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(format(todaySummary?.totalTokens ?? 0))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("今日 · 本机原始 Token")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if todaySummary?.isComplete == false {
                    Label("不完整", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }

            if appModel.isUsageInitialLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在回填本机 Token 历史…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 58)
            } else {
                taskBreakdown
                trendChart
            }

            if let error = appModel.usageErrorMessage {
                InlineModuleNotice(
                    text: error,
                    systemImage: "exclamationmark.triangle.fill",
                    color: .orange
                )
            } else if let warning = appModel.usageHistory?.warnings.first {
                InlineModuleNotice(
                    text: warning,
                    systemImage: "info.circle.fill",
                    color: .orange
                )
            }

            if let generatedAt = appModel.usageHistory?.generatedAt {
                Text("更新于 \(generatedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(12)
        .adaptiveGlassCard(tint: .indigo, id: "token-usage", namespace: glassNamespace)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var taskBreakdown: some View {
        let tasks = todaySummary?.topTasks() ?? []
        let total = max(1, todaySummary?.totalTokens ?? 0)
        VStack(alignment: .leading, spacing: 8) {
            Text("今日 Top 3 任务")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            if tasks.isEmpty {
                Text("今天还没有可读取的本机 Token 记录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
            } else {
                ForEach(Array(tasks.enumerated()), id: \.element.id) { index, task in
                    let displayedTitle = taskTitle(task, index: index)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(displayedTitle)
                                .font(.caption.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(displayedTitle)
                            if task.descendantCount > 0 {
                                Text("+\(task.descendantCount)")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(format(task.tokens))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: Double(task.tokens), total: Double(total))
                            .tint(.indigo)
                            .accessibilityLabel(displayedTitle)
                            .accessibilityValue("\(format(task.tokens)) Token")
                    }
                }

                let remaining = todaySummary?.remainingTokens() ?? 0
                if remaining > 0 {
                    HStack {
                        Text("其余任务")
                        Spacer()
                        Text(format(remaining)).monospacedDigit()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("最近 \(appModel.settings.usageTrendRange.rawValue) 天")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Chart(trendPoints) { point in
                BarMark(
                    x: .value("日期", point.dateKey),
                    y: .value("Token", point.tokens)
                )
                .foregroundStyle(.indigo.gradient)
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel(anchor: .center) {
                        if let key = value.as(String.self) {
                            Text(String(key.suffix(5))).font(.system(size: 8))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel(anchor: .center) {
                        if let tokens = value.as(Int64.self) {
                            Text(compact(tokens)).font(.system(size: 8))
                        }
                    }
                }
            }
            .frame(height: 118)
            .accessibilityLabel("每日本机原始 Token 趋势")
        }
    }

    private var todaySummary: DailyUsageSummary? {
        appModel.usageHistory?.summary(for: dayKey(Date()))
    }

    private var trendPoints: [TokenTrendPoint] {
        let calendar = Calendar.current
        let range = appModel.settings.usageTrendRange.rawValue
        return (0..<range).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = dayKey(date)
            return TokenTrendPoint(
                dateKey: key,
                tokens: appModel.usageHistory?.summary(for: key)?.totalTokens ?? 0
            )
        }
    }

    private func taskTitle(_ task: DailyTaskUsage, index: Int) -> String {
        appModel.settings.anonymizesTaskTitles ? "任务 \(index + 1)" : task.title
    }

    private func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func format(_ value: Int64) -> String {
        value.formatted(.number.grouping(.automatic))
    }

    private func compact(_ value: Int64) -> String {
        switch value {
        case 1_000_000...: return String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...: return String(format: "%.1fK", Double(value) / 1_000)
        default: return "\(value)"
        }
    }
}

private struct TokenTrendPoint: Identifiable {
    let dateKey: String
    let tokens: Int64
    var id: String { dateKey }
}

struct InlineModuleNotice: View {
    let text: String
    let systemImage: String
    let color: Color

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.caption2)
            .foregroundStyle(color)
            .padding(7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
