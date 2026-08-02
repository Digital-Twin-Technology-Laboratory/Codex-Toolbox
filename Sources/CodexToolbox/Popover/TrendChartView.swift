import Charts
import CodexToolboxCore
import SwiftUI

@MainActor
private final class TrendChartState: ObservableObject {
    @Published var metric: RankingMetric = .iq
    @Published var hoveredDay: Date?
}

struct TrendChartView: View {
    @Bindable var appModel: AppModel
    @Binding var isExpanded: Bool
    let namespace: Namespace.ID

    @StateObject private var state = TrendChartState()

    private let availableMetrics: [RankingMetric] = [.iq, .cost, .duration]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            trendEntry

            if isExpanded {
                expandedContent
            }
        }
        .padding(12)
        .adaptiveGlassCard(tint: .indigo, id: "model-trend", namespace: namespace)
        .onChange(of: state.metric) { _, _ in
            state.hoveredDay = nil
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                state.hoveredDay = nil
            }
        }
    }

    private var trendEntry: some View {
        Button(action: toggleExpansion) {
            HStack(spacing: 8) {
                Label("变化趋势", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 12, weight: .bold))

                Spacer()

                if !isExpanded {
                    Text("默认当前指标 Top 3")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Text("最近 \(appModel.settings.modelTrendRange.rawValue) 天")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 14)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("模型变化趋势")
        .accessibilityValue(isExpanded ? "已展开" : "已折叠")
        .accessibilityHint(isExpanded ? "按下可收起趋势图" : "按下可展开趋势图")
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Picker("趋势指标", selection: $state.metric) {
                    ForEach(availableMetrics) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 210)

                modelSelector
            }

            Text(selectionDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if TrendPointBuilder.hasDrawableSeries(chartPoints) {
                chart
                    .frame(height: 185)
            } else {
                emptyState
            }
        }
    }

    private var modelSelector: some View {
        Menu {
            if selectableGroups.isEmpty {
                Text("当前范围内暂无可绘制趋势的模型")
            } else {
                ForEach(selectableGroups) { group in
                    Menu(group.title) {
                        ForEach(group.models) { model in
                            modelSelectionRow(for: model)
                        }
                    }
                }
            }

            Divider()

            Button("恢复默认 Top 3") {
                appModel.settings.resetModelTrendSelection(for: state.metric)
            }
            .disabled(!hasCustomSelection)
        } label: {
            Label(
                "模型 \(selectedModelIDs.count)/3",
                systemImage: "line.3.horizontal.decrease.circle"
            )
            .font(.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("选择 \(state.metric.displayName) 趋势模型")
    }

    private func modelSelectionRow(for model: ModelBenchmark) -> some View {
        let isSelected = selectedModelIDs.contains(model.id)
        return Button {
            toggleSelection(for: model.id)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(model.catalogEntry.rowTitle)
                    Spacer(minLength: 8)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .accessibilityHidden(true)
                    }
                }
                Text(model.catalogEntry.displayLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!isSelected && selectedModelIDs.count >= 3)
        .accessibilityLabel(model.catalogEntry.displayLabel)
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }

    private var chart: some View {
        Chart {
            ForEach(chartPoints) { point in
                if let day = point.day {
                    LineMark(
                        x: .value("日期", day),
                        y: .value(state.metric.displayName, point.value),
                        series: .value("模型", point.modelID)
                    )
                    .foregroundStyle(by: .value("模型", MetricFormatter.compactModelName(point.modelLabel)))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("日期", day),
                        y: .value(state.metric.displayName, point.value)
                    )
                    .foregroundStyle(by: .value("模型", MetricFormatter.compactModelName(point.modelLabel)))
                    .symbolSize(20)
                }
            }

            if let hoveredDay = state.hoveredDay {
                RuleMark(x: .value("选中日期", hoveredDay))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(
                        position: .top,
                        alignment: .center,
                        spacing: 6,
                        overflowResolution: .init(x: .fit(to: .chart), y: .automatic)
                    ) {
                        hoverCard(for: hoveredDay)
                    }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
        .chartXAxis {
            AxisMarks(values: TrendPointBuilder.axisDays(chartPoints, maximumCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisTick()
                AxisValueLabel {
                    if let day = value.as(Date.self) {
                        Text(day.formatted(.dateTime.month(.twoDigits).day(.twoDigits)))
                    }
                }
                .font(.system(size: 9))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(MetricFormatter.menuBarValue(number, metric: state.metric))
                    }
                }
                .font(.system(size: 9))
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
                                if state.hoveredDay != nil {
                                    state.hoveredDay = nil
                                }
                                return
                            }
                            let x = location.x - frame.origin.x
                            let closestDay = proxy.value(atX: x, as: Date.self).flatMap {
                                TrendPointBuilder.nearestDay(to: $0, in: chartPoints)
                            }
                            if state.hoveredDay != closestDay {
                                state.hoveredDay = closestDay
                            }
                        case .ended:
                            if state.hoveredDay != nil {
                                state.hoveredDay = nil
                            }
                        }
                    }
            }
        }
        .accessibilityLabel("\(state.metric.displayName) 模型变化趋势")
        .accessibilityHint("将鼠标停留在数据点附近可查看该日详情")
    }

    private var allRecentPoints: [TrendPoint] {
        TrendPointBuilder.recentPoints(
            TrendPointBuilder.points(
                benchmarks: appModel.snapshot?.benchmarks ?? [],
                costHistory: appModel.costHistory,
                metric: state.metric,
                modelIDs: appModel.availableModels.map(\.id)
            ),
            days: appModel.settings.modelTrendRange.rawValue,
            now: Date(),
            calendar: .current
        )
    }

    private var drawableModelIDs: Set<String> {
        Set(
            Dictionary(grouping: allRecentPoints, by: \.modelID)
                .compactMap { modelID, points in
                    points.count >= 2 ? modelID : nil
                }
        )
    }

    private var automaticModelIDs: [String] {
        Array(
            appModel.rankings(for: state.metric)
                .lazy
                .map(\.id)
                .filter(drawableModelIDs.contains)
                .prefix(3)
        )
    }

    private var selectedModelIDs: [String] {
        let savedIDs = appModel.settings.modelTrendSelection(for: state.metric)
            .filter(drawableModelIDs.contains)
        return savedIDs.isEmpty ? automaticModelIDs : savedIDs
    }

    private var chartPoints: [TrendPoint] {
        let selectedIDs = Set(selectedModelIDs)
        return allRecentPoints.filter { selectedIDs.contains($0.modelID) && $0.day != nil }
    }

    private var selectableGroups: [ModelCatalogFamilyGroup] {
        ModelCatalog.grouped(
            appModel.availableModels.filter { drawableModelIDs.contains($0.id) }
        )
    }

    private var hasCustomSelection: Bool {
        !appModel.settings.modelTrendSelection(for: state.metric).isEmpty
    }

    private var selectionDescription: String {
        if hasCustomSelection {
            return "已为\(state.metric.displayName)保存自选模型；最多可显示 3 条曲线。"
        }
        return "默认显示当前\(state.metric.displayName)榜单中有足够按日数据的 Top 3；可选择 1–3 个模型。"
    }

    private var emptyState: some View {
        VStack(spacing: 7) {
            Image(systemName: state.metric == .cost ? "clock.badge.questionmark" : "chart.line.downtrend.xyaxis")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("趋势数据不足")
                .font(.subheadline.weight(.semibold))
            Text(emptyDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
    }

    private var emptyDescription: String {
        if state.metric == .cost {
            return "同一模型至少需要两个不同日期的有效平均费用点；远端历史完全缺失时才会使用本机新口径快照。"
        }
        return "同一模型至少需要两个不同日期的有效数据点。"
    }

    private func toggleExpansion() {
        isExpanded.toggle()
    }

    private func toggleSelection(for modelID: String) {
        var nextIDs = selectedModelIDs
        if let index = nextIDs.firstIndex(of: modelID) {
            guard nextIDs.count > 1 else { return }
            nextIDs.remove(at: index)
        } else {
            guard nextIDs.count < 3 else { return }
            nextIDs.append(modelID)
        }

        if nextIDs == automaticModelIDs {
            appModel.settings.resetModelTrendSelection(for: state.metric)
        } else {
            appModel.settings.setModelTrendSelection(nextIDs, for: state.metric)
        }
    }

    @ViewBuilder
    private func hoverCard(for day: Date) -> some View {
        let values = chartPoints
            .filter { $0.day == day }
            .sorted { $0.modelLabel.localizedStandardCompare($1.modelLabel) == .orderedAscending }
        let latest = values.max { lhs, rhs in
            (lhs.recordedAt ?? .distantPast) < (rhs.recordedAt ?? .distantPast)
        }

        VStack(alignment: .leading, spacing: 3) {
            Text(
                latest.map { MetricFormatter.benchmarkDateLabel($0.dateKey, includesDetailedTime: true) }
                    ?? day.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
            )
            .font(.caption2.bold())

            ForEach(values) { point in
                HStack(spacing: 8) {
                    Text(point.modelLabel)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(MetricFormatter.detailValue(point.value, metric: state.metric))
                        .monospacedDigit()
                }
                .font(.system(size: 10))
            }
        }
        .frame(minWidth: 150, maxWidth: 230, alignment: .leading)
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
