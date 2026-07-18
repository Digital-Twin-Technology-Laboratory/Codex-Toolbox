import Charts
import CodexToolboxCore
import SwiftUI

struct TokenUsageModuleView: View {
    @Bindable var appModel: AppModel
    @Namespace private var glassNamespace
    @State private var isTaskListExpanded = false
    @State private var isTaskCardHovered = false
    @State private var hoveredDateKey: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if appModel.isUsageInitialLoading {
                loadingCard
            } else {
                usageCards
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
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var usageCards: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                cardStack
            }
        } else {
            cardStack
        }
    }

    private var cardStack: some View {
        VStack(spacing: 10) {
            taskBreakdown
            trendChart
        }
    }

    private var loadingCard: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("正在回填本机 Token 历史…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .padding(11)
        .adaptiveGlassCard(tint: .indigo, id: "token-loading", namespace: glassNamespace)
    }

    private var taskBreakdown: some View {
        Button {
            guard hasAdditionalTasks else { return }
            withAnimation(ToolboxMotion.dashboard(reduceMotion: reduceMotion)) {
                isTaskListExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 9) {
                taskCardHeader

                if visibleTasks.isEmpty {
                    Text("今天还没有可读取的本机 Token 记录")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                } else {
                    ForEach(visibleTasks) { task in
                        taskRow(task)
                    }

                    if remainingTokens > 0 {
                        HStack {
                            Text("其余任务")
                            Spacer()
                            Text(usageAndQuotaText(tokens: remainingTokens))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Text(quotaEstimateFootnote)
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(11)
            .adaptiveGlassCard(tint: .indigo, id: "token-tasks", namespace: glassNamespace)
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        Color.indigo.opacity(isTaskCardHovered && hasAdditionalTasks ? 0.44 : 0.12),
                        lineWidth: isTaskCardHovered && hasAdditionalTasks ? 1.25 : 0.75
                    )
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(ToolboxPressButtonStyle())
        .onHover { hovering in
            withAnimation(reduceMotion ? .easeOut(duration: 0.20) : .easeOut(duration: 0.16)) {
                isTaskCardHovered = hovering
            }
        }
        .help(taskCardHelp)
        .accessibilityLabel("今日 Token Top \(currentTaskLimit) 任务榜单")
        .accessibilityHint(hasAdditionalTasks ? taskCardHelp : "当前没有更多任务")
    }

    private var taskCardHeader: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Label("今日 Top \(currentTaskLimit) 任务", systemImage: "list.number")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.indigo)
                Text(format(todaySummary?.totalTokens ?? 0))
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("今日本机原始 Token")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if todaySummary?.isComplete == false {
                Label("不完整", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
            }

            if taskCount > 0 {
                Text(hasAdditionalTasks ? "共 \(taskCount) 项" : "今日仅 \(taskCount) 项")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            if hasAdditionalTasks {
                Image(systemName: isTaskListExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }
        }
    }

    private func taskRow(_ task: DailyTaskUsage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(task.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(task.title)
                if task.descendantCount > 0 {
                    Text("+\(task.descendantCount)")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(usageAndQuotaText(tokens: task.tokens))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            ProgressView(value: Double(task.tokens), total: Double(max(1, todaySummary?.totalTokens ?? 0)))
                .tint(.indigo)
                .accessibilityLabel(task.title)
                .accessibilityValue(usageAndQuotaText(tokens: task.tokens))
        }
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("每日用量趋势", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.indigo)

                Spacer()

                Text(hoverSummary)
                    .font(.caption2.weight(hoveredPoint == nil ? .regular : .semibold))
                    .foregroundStyle(hoveredPoint == nil ? Color.gray : Color.indigo)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(minHeight: 16)

            Chart {
                ForEach(trendPoints) { point in
                    BarMark(
                        x: .value("日期", point.date, unit: .day),
                        y: .value("Token", point.tokens)
                    )
                    .foregroundStyle(
                        point.dateKey == hoveredDateKey
                            ? Color.indigo
                            : Color.indigo.opacity(0.66)
                    )
                    .cornerRadius(3)
                }

                if let hoveredPoint {
                    RuleMark(x: .value("选中日期", hoveredPoint.date, unit: .day))
                        .foregroundStyle(.indigo.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { value in
                    AxisValueLabel {
                        if let date = value.as(Date.self) {
                            Text(String(dayKey(date).suffix(5))).font(.system(size: 8))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                    AxisValueLabel {
                        if let tokens = value.as(Int64.self) {
                            Text(compact(tokens)).font(.system(size: 8))
                        }
                    }
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case let .active(location):
                                guard let plotFrame = proxy.plotFrame else { return }
                                let frame = geometry[plotFrame]
                                guard frame.contains(location) else {
                                    hoveredDateKey = nil
                                    return
                                }
                                let x = location.x - frame.origin.x
                                hoveredDateKey = proxy.value(atX: x, as: Date.self).map(dayKey)
                            case .ended:
                                hoveredDateKey = nil
                            }
                        }
                }
            }
            .frame(height: 124)
            .accessibilityLabel("每日本机原始 Token 趋势")
        }
        .padding(11)
        .adaptiveGlassCard(tint: .indigo, id: "token-trend", namespace: glassNamespace)
    }

    private var todaySummary: DailyUsageSummary? {
        appModel.usageHistory?.summary(for: dayKey(Date()))
    }

    private var currentTaskLimit: Int {
        isTaskListExpanded ? appModel.settings.usageExpandedTaskLimit.rawValue : 3
    }

    private var visibleTasks: [DailyTaskUsage] {
        todaySummary?.topTasks(limit: currentTaskLimit) ?? []
    }

    private var hasAdditionalTasks: Bool {
        taskCount > 3
    }

    private var taskCount: Int {
        todaySummary?.tasks.count ?? 0
    }

    private var remainingTokens: Int64 {
        todaySummary?.remainingTokens(afterTop: currentTaskLimit) ?? 0
    }

    private var taskCardHelp: String {
        if !hasAdditionalTasks { return "今日仅有 \(taskCount) 个根任务，没有更多可展开项" }
        return isTaskListExpanded
            ? "点击收起为 Top 3"
            : "点击展开为 \(appModel.settings.usageExpandedTaskLimit.displayName)"
    }

    private func usageAndQuotaText(tokens: Int64) -> String {
        "\(format(tokens)) · \(quotaEstimateText(tokens: tokens))"
    }

    private func quotaEstimateText(tokens: Int64) -> String {
        guard let history = appModel.usageHistory else { return "额度—" }
        let windows = appModel.resetCreditsSnapshot?.quotaWindows ?? []
        let estimates = windows.compactMap { window -> String? in
            guard let percent = QuotaUsageEstimator.estimatedPercent(
                taskTokens: tokens,
                history: history,
                window: window,
                now: Date(),
                calendar: .current
            ) else { return nil }
            return "\(window.displayName)≈\(formatPercent(percent))"
        }
        return estimates.isEmpty ? "额度—" : estimates.joined(separator: " / ")
    }

    private var quotaEstimateFootnote: String {
        if appModel.resetCreditsSnapshot?.quotaWindows.isEmpty == false {
            return "额度占比按账户窗口已用比例与本机同期 Token 推算，仅供参考。"
        }
        return "账户未返回 5 小时/周窗口，额度占比暂不可估算。"
    }

    private func formatPercent(_ value: Double) -> String {
        if value > 0, value < 0.05 { return "<0.1%" }
        return String(format: "%.1f%%", value)
    }

    private var trendPoints: [TokenTrendPoint] {
        let calendar = Calendar.current
        let range = appModel.settings.usageTrendRange.rawValue
        return (0..<range).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            let key = dayKey(date)
            return TokenTrendPoint(
                date: date,
                dateKey: key,
                tokens: appModel.usageHistory?.summary(for: key)?.totalTokens ?? 0
            )
        }
    }

    private var hoveredPoint: TokenTrendPoint? {
        guard let hoveredDateKey else { return nil }
        return trendPoints.first { $0.dateKey == hoveredDateKey }
    }

    private var hoverSummary: String {
        guard let point = hoveredPoint else {
            return "最近 \(appModel.settings.usageTrendRange.rawValue) 天 · 悬停查看"
        }
        return "\(localizedDate(point.dateKey)) · \(format(point.tokens)) Token"
    }

    private func localizedDate(_ dateKey: String) -> String {
        let components = dateKey.split(separator: "-").compactMap { Int($0) }
        guard components.count == 3 else { return dateKey }
        return "\(components[1])月\(components[2])日"
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
    let date: Date
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
