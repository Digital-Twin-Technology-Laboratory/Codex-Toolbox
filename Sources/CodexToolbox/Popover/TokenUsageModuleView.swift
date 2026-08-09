import AppKit
import Charts
import Combine
import CodexToolboxCore
import SwiftUI

struct TokenUsageModuleView: View {
    @Bindable var appModel: AppModel
    @Namespace private var glassNamespace
    @State private var isTaskListExpanded = false
    @State private var isTaskCardHovered = false
    @State private var hoveredDateKey: String?
    @State private var selectedDateKey: String?
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
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            resetDateSelection()
        }
        .onDisappear {
            resetDateSelection()
        }
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
        Button(action: toggleTaskList) {
            taskBreakdownContent
        }
        .buttonStyle(ToolboxPressButtonStyle())
        .accessibilityLabel("\(selectedPeriodName) Token Top \(currentTaskLimit) 任务榜单")
        .accessibilityHint(taskCardHelp)
        .overlay(alignment: .topTrailing) {
            if !isViewingToday {
                Button(action: returnToToday) {
                    Label("返回今日", systemImage: "arrow.uturn.backward")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.indigo)
                        .frame(width: 78, height: 26)
                        .background(.indigo.opacity(0.10), in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 11)
                .padding(.trailing, 11)
                .help("恢复今日任务明细")
                .accessibilityLabel("返回今日 Token 用量")
            }
        }
        .adaptiveGlassCard(tint: .indigo, id: "token-tasks", namespace: glassNamespace)
        .onHover { hovering in
            withAnimation(reduceMotion ? .easeOut(duration: 0.20) : .easeOut(duration: 0.16)) {
                isTaskCardHovered = hovering
            }
        }
        .help(taskCardHelp)
    }

    private var taskBreakdownContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            taskCardHeader

            if visibleTasks.isEmpty {
                Text(emptyTaskMessage)
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
                        Text(
                            usageAndQuotaText(
                                tokens: remainingTokens,
                                taskIDs: remainingTaskIDs
                            )
                        )
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                            .help(quotaEstimateHelp(taskIDs: remainingTaskIDs))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Text(accountQuotaFootnote)
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    Color.indigo.opacity(isTaskCardHovered && hasAdditionalTasks ? 0.44 : 0.12),
                    lineWidth: isTaskCardHovered && hasAdditionalTasks ? 1.25 : 0.75
                )
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var taskCardHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label("\(selectedPeriodName) Top \(currentTaskLimit) 任务", systemImage: "list.number")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.indigo)
                    .lineLimit(1)

                Spacer()

                if selectedSummary?.isComplete == false {
                    Label("不完整", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                if taskCount > 0 {
                    Text(hasAdditionalTasks ? "共 \(taskCount) 项" : "当日仅 \(taskCount) 项")
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
                        .accessibilityHidden(true)
                }
            }
            .padding(.trailing, isViewingToday ? 0 : 78 + 8)

            Text(format(selectedSummary?.totalTokens ?? 0))
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.64)
                .allowsTightening(true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(isViewingToday ? "今日本机原始 Token" : "当日本机原始 Token")
                .font(.caption2)
                .foregroundStyle(.secondary)
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
                Text(
                    usageAndQuotaText(
                        tokens: task.tokens,
                        taskIDs: [task.id]
                    )
                )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .help(quotaEstimateHelp(taskIDs: [task.id]))
            }
            ProgressView(value: Double(task.tokens), total: Double(max(1, selectedSummary?.totalTokens ?? 0)))
                .tint(.indigo)
                .accessibilityLabel(task.title)
                .accessibilityValue(
                    usageAndQuotaText(tokens: task.tokens, taskIDs: [task.id])
                )
        }
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label("每日用量趋势", systemImage: "chart.bar.xaxis")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.indigo)

                Spacer()

                Text(trendSummary)
                    .font(.caption2.weight(hasTrendEmphasis ? .semibold : .regular))
                    .foregroundStyle(hasTrendEmphasis ? Color.indigo : Color.gray)
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
                        point.dateKey == selectedDateKey
                            ? Color.indigo
                            : point.dateKey == hoveredDateKey
                                ? Color.indigo.opacity(0.86)
                                : Color.indigo.opacity(0.66)
                    )
                    .cornerRadius(3)
                }

                if let selectedPoint {
                    RuleMark(x: .value("已选日期", selectedPoint.date, unit: .day))
                        .foregroundStyle(.indigo.opacity(0.60))
                        .lineStyle(StrokeStyle(lineWidth: 1.25))
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
                                    if hoveredDateKey != nil { hoveredDateKey = nil }
                                    return
                                }
                                let x = location.x - frame.origin.x
                                let nextDateKey = proxy.value(atX: x, as: Date.self).map(dayKey)
                                if hoveredDateKey != nextDateKey {
                                    hoveredDateKey = nextDateKey
                                }
                            case .ended:
                                if hoveredDateKey != nil { hoveredDateKey = nil }
                            }
                        }
                        .gesture(
                            SpatialTapGesture()
                                .onEnded { value in
                                    guard let plotFrame = proxy.plotFrame else { return }
                                    let frame = geometry[plotFrame]
                                    guard frame.contains(value.location) else { return }
                                    let x = value.location.x - frame.origin.x
                                    guard let date = proxy.value(atX: x, as: Date.self) else {
                                        return
                                    }
                                    selectDate(dayKey(date))
                                }
                        )
                }
            }
            .frame(height: 124)
            .accessibilityLabel("每日本机原始 Token 趋势")
            .accessibilityHint("点击柱形查看该日任务明细")
        }
        .padding(11)
        .adaptiveGlassCard(tint: .indigo, id: "token-trend", namespace: glassNamespace)
    }

    private var todayDateKey: String {
        dayKey(Date())
    }

    private var selectedSummaryDateKey: String {
        selectedDateKey ?? todayDateKey
    }

    private var selectedSummary: DailyUsageSummary? {
        appModel.usageHistory?.summary(for: selectedSummaryDateKey)
    }

    private var isViewingToday: Bool {
        selectedSummaryDateKey == todayDateKey
    }

    private var selectedPeriodName: String {
        isViewingToday ? "今日" : localizedDate(selectedSummaryDateKey)
    }

    private var emptyTaskMessage: String {
        isViewingToday
            ? "今天还没有可读取的本机 Token 记录"
            : "\(localizedDate(selectedSummaryDateKey))没有可读取的本机 Token 记录"
    }

    private var currentTaskLimit: Int {
        isTaskListExpanded ? appModel.settings.usageExpandedTaskLimit.rawValue : 3
    }

    private var visibleTasks: [DailyTaskUsage] {
        selectedSummary?.topTasks(limit: currentTaskLimit) ?? []
    }

    private var hasAdditionalTasks: Bool {
        taskCount > 3
    }

    private var taskCount: Int {
        selectedSummary?.tasks.count ?? 0
    }

    private var remainingTokens: Int64 {
        selectedSummary?.remainingTokens(afterTop: currentTaskLimit) ?? 0
    }

    private var remainingTaskIDs: Set<String> {
        guard let tasks = selectedSummary?.tasks else { return [] }
        return Set(tasks.dropFirst(currentTaskLimit).map(\.id))
    }

    private var taskCardHelp: String {
        if !hasAdditionalTasks {
            return "\(selectedPeriodName)仅有 \(taskCount) 个根任务，没有更多可展开项"
        }
        return isTaskListExpanded
            ? "点击收起为 Top 3"
            : "点击展开为 \(appModel.settings.usageExpandedTaskLimit.displayName)"
    }

    private var accountQuotaFootnote: String {
        let windows = appModel.resetCreditsSnapshot?.quotaWindows ?? []
        let activeWindows = windows.filter { Date() < $0.resetsAt }
        if !activeWindows.isEmpty {
            let usage = activeWindows.map {
                "\($0.displayName)已用 \(formatPercent($0.usedPercent))"
            }.joined(separator: " / ")
            let estimateStatus = appModel.taskQuotaEstimatesByDuration.values.contains { !$0.isEmpty }
                ? "任务额度按本机逐轮快照估算"
                : "任务额度快照不足"
            return "\(estimateStatus)；账户总用量（含所有设备）：\(usage)。"
        }
        if !windows.isEmpty {
            return "账户额度窗口已过期，刷新后重新估算任务额度。"
        }
        return "账户未返回 5 小时/周窗口，暂不能估算任务额度。"
    }

    private func usageAndQuotaText(tokens: Int64, taskIDs: Set<String>) -> String {
        let estimates = quotaEstimateSummaries(taskIDs: taskIDs)
        guard !estimates.isEmpty else { return format(tokens) }
        let quota = estimates.map {
            "\($0.window.displayName)≈\(formatPercent($0.percent))"
        }.joined(separator: " / ")
        return "\(format(tokens)) · \(quota)"
    }

    private func quotaEstimateHelp(taskIDs: Set<String>) -> String {
        let estimates = quotaEstimateSummaries(taskIDs: taskIDs)
        guard !estimates.isEmpty else { return "暂无足够的逐轮额度快照" }
        return estimates.map {
            "\($0.window.displayName)估算置信度：\($0.confidence.displayName)"
        }.joined(separator: "；")
            + "；已按模型输入、缓存输入与输出权重校准"
    }

    private func quotaEstimateSummaries(taskIDs: Set<String>) -> [TaskQuotaEstimate] {
        guard !taskIDs.isEmpty else { return [] }
        let windows = (appModel.resetCreditsSnapshot?.quotaWindows ?? []).filter {
            Date() < $0.resetsAt
        }
        return windows.compactMap { window in
            let estimates = taskIDs.compactMap {
                appModel.taskQuotaEstimatesByDuration[window.durationMinutes]?[$0]
            }
            guard estimates.count == taskIDs.count else { return nil }
            return TaskQuotaEstimate(
                window: window,
                percent: estimates.reduce(0) { $0 + $1.percent },
                confidence: combinedConfidence(estimates.map(\.confidence)),
                observedStepCount: estimates.reduce(0) { $0 + $1.observedStepCount },
                observedTokenCoverage: estimates.map(\.observedTokenCoverage).min() ?? 0
            )
        }
    }

    private func combinedConfidence(
        _ confidences: [QuotaEstimateConfidence]
    ) -> QuotaEstimateConfidence {
        if confidences.contains(.low) { return .low }
        return .medium
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

    private var selectedPoint: TokenTrendPoint? {
        guard let selectedDateKey else { return nil }
        return trendPoints.first { $0.dateKey == selectedDateKey }
    }

    private var hasTrendEmphasis: Bool {
        hoveredPoint != nil || selectedPoint != nil
    }

    private var trendSummary: String {
        if let point = hoveredPoint {
            return "\(localizedDate(point.dateKey)) · \(format(point.tokens)) Token"
        }
        if let point = selectedPoint {
            return "\(localizedDate(point.dateKey)) · \(format(point.tokens)) Token · 已选"
        }
        return "最近 \(appModel.settings.usageTrendRange.rawValue) 天 · 点击柱形查看"
    }

    private func selectDate(_ dateKey: String) {
        // Empty trend slots do not render a usable bar and should not replace
        // today's task list when the user taps the chart background.
        guard appModel.usageHistory?.summary(for: dateKey) != nil else { return }
        withAnimation(ToolboxMotion.dashboard(reduceMotion: reduceMotion)) {
            selectedDateKey = dateKey == todayDateKey ? nil : dateKey
            isTaskListExpanded = false
        }
    }

    private func returnToToday() {
        withAnimation(ToolboxMotion.dashboard(reduceMotion: reduceMotion)) {
            selectedDateKey = nil
            isTaskListExpanded = false
        }
    }

    private func resetDateSelection() {
        selectedDateKey = nil
        hoveredDateKey = nil
        isTaskListExpanded = false
    }

    private func toggleTaskList() {
        guard hasAdditionalTasks else { return }
        withAnimation(ToolboxMotion.dashboard(reduceMotion: reduceMotion)) {
            isTaskListExpanded.toggle()
        }
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
