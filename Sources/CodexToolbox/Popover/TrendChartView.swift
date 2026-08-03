import Charts
import CodexToolboxCore
import SwiftUI

private struct TrendChartSourceRevision: Hashable, Sendable {
    let metric: RankingMetric
    let rangeDays: Int
    let snapshotFetchedAt: Date?
    let sourceMonitoredAt: String?
    let benchmarkCount: Int
    let costHistoryCount: Int
    let timeZoneIdentifier: String
}

private struct TrendChartLoadInput: Sendable {
    let benchmarks: [ModelBenchmark]
    let costHistory: [CostHistoryPoint]
    let rankedModelIDs: [String]
    let metric: RankingMetric
    let days: Int
    let now: Date
    let calendar: Calendar
}

@MainActor
private final class TrendChartState: ObservableObject {
    @Published var metric: RankingMetric = .iq
    @Published private(set) var data: TrendSeriesData?
    @Published private(set) var loadedRevision: TrendChartSourceRevision?

    private var sourceData: TrendSeriesSourceData?
    private var requestedModelIDs: [String] = []
    private var cache: [TrendChartSourceRevision: TrendSeriesSourceData] = [:]

    func select(modelIDs: [String]) {
        guard requestedModelIDs != modelIDs || data == nil else { return }
        requestedModelIDs = modelIDs
        if let sourceData {
            data = sourceData.selecting(savedModelIDs: modelIDs)
        }
    }

    func load(input: TrendChartLoadInput, revision: TrendChartSourceRevision) async {
        guard loadedRevision != revision else { return }

        if let cached = cache[revision] {
            sourceData = cached
            data = cached.selecting(savedModelIDs: requestedModelIDs)
            loadedRevision = revision
            return
        }

        if loadedRevision?.metric != revision.metric {
            sourceData = nil
            data = nil
        }

        let worker = Task.detached(priority: .userInitiated) {
            TrendSeriesBuilder.prepare(
                benchmarks: input.benchmarks,
                costHistory: input.costHistory,
                rankedModelIDs: input.rankedModelIDs,
                metric: input.metric,
                days: input.days,
                now: input.now,
                calendar: input.calendar
            )
        }
        let prepared = await worker.value
        guard !Task.isCancelled else { return }

        cache = cache.filter { $0.key.metric != revision.metric }
        cache[revision] = prepared
        sourceData = prepared
        data = prepared.selecting(savedModelIDs: requestedModelIDs)
        loadedRevision = revision
    }
}

struct TrendChartView: View {
    @Bindable var appModel: AppModel
    @Binding var isExpanded: Bool
    let namespace: Namespace.ID

    @StateObject private var state = TrendChartState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let availableMetrics: [RankingMetric] = [.iq, .cost, .duration]
    private let seriesColors: [Color] = [.blue, .green, .orange, .purple, .pink]
    private let seriesColorNames = ["蓝色", "绿色", "橙色", "紫色", "粉色"]
    private let curveColumns = [
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5),
        GridItem(.flexible(), spacing: 5)
    ]

    var body: some View {
        let revision = trendSourceRevision
        let savedModelIDs = appModel.settings.modelTrendSelection(for: state.metric)
        let currentData = state.loadedRevision?.metric == revision.metric ? state.data : nil

        VStack(alignment: .leading, spacing: 10) {
            trendEntry

            if isExpanded {
                expandedContent(data: currentData)
                    .transition(ToolboxMotion.dashboardContentTransition(reduceMotion: reduceMotion))
            }
        }
        .padding(12)
        .adaptiveGlassCard(
            tint: .indigo,
            id: "model-trend",
            namespace: namespace,
            isInteractive: false
        )
        .task(id: savedModelIDs) {
            state.select(modelIDs: savedModelIDs)
        }
        .task(id: revision) {
            await state.load(input: trendLoadInput, revision: revision)
        }
    }

    private var trendEntry: some View {
        Button(action: toggleExpansion) {
            HStack(spacing: 8) {
                Label("变化趋势", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 12, weight: .bold))

                Spacer()

                if !isExpanded {
                    Text(collapsedSelectionSummary)
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

    @ViewBuilder
    private func expandedContent(data: TrendSeriesData?) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 8) {
                Picker("趋势指标", selection: $state.metric) {
                    ForEach(availableMetrics) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 210)

                Spacer(minLength: 8)

                if let data {
                    Text("\(data.selectedModelIDs.count)/\(ModelTrendSeriesConfiguration.maximumCount) 条曲线")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在准备模型趋势")
                }
            }

            if let data {
                if data.hasDrawableSeries {
                    TrendPlotView(
                        data: data,
                        metric: state.metric,
                        seriesColors: seriesColors
                    )
                        .frame(height: 185)
                        .padding(.top, 32)
                } else {
                    emptyState
                }

                if !data.selectableGroups.isEmpty {
                    curveEditor(data: data)
                }
            } else {
                loadingState
            }
        }
    }

    private func curveEditor(data: TrendSeriesData) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            LazyVGrid(columns: curveColumns, alignment: .leading, spacing: 5) {
                ForEach(Array(data.selectedModelIDs.enumerated()), id: \.offset) { index, modelID in
                    curveSlot(index: index, modelID: modelID, data: data)
                }
            }

            HStack(spacing: 8) {
                addCurveMenu(data: data)

                Spacer()

                Button("恢复默认 Top 3") {
                    withAnimation(ToolboxMotion.dashboard(reduceMotion: reduceMotion)) {
                        state.select(modelIDs: [])
                        appModel.settings.resetModelTrendSelection(for: state.metric)
                    }
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .disabled(!data.hasCustomSelection)
            }
        }
        .padding(.top, 1)
    }

    private func curveSlot(
        index: Int,
        modelID: String,
        data: TrendSeriesData
    ) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(seriesColor(at: index))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Menu {
                modelPickerMenu(selectedModelID: modelID, slotIndex: index, data: data)
            } label: {
                HStack(spacing: 4) {
                    Text(compactModelName(for: modelID, data: data))
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                    Spacer(minLength: 1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .font(.caption2)
            .layoutPriority(1)
            .help(fullModelName(for: modelID, data: data))
            .accessibilityLabel(
                "\(seriesColorName(at: index))曲线模型，当前\(fullModelName(for: modelID, data: data))"
            )

            Button {
                removeCurve(at: index, data: data)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .semibold))
                    .frame(width: 10, height: 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .disabled(data.selectedModelIDs.count <= 1)
            .help(data.selectedModelIDs.count <= 1 ? "至少保留一条曲线" : "删除这条曲线")
            .accessibilityLabel("删除\(seriesColorName(at: index))曲线")
        }
        .padding(.leading, 5)
        .padding(.trailing, 4)
        .frame(height: 24)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func modelPickerMenu(
        selectedModelID: String,
        slotIndex: Int,
        data: TrendSeriesData
    ) -> some View {
        ForEach(data.selectableGroups) { group in
            Menu(group.title) {
                ForEach(group.models) { model in
                    let occupiedSlotIndex = data.selectedModelIDs.firstIndex(of: model.id)
                    let isCurrent = model.id == selectedModelID && occupiedSlotIndex == slotIndex
                    let isUsedByOtherCurve = occupiedSlotIndex != nil && !isCurrent

                    Button {
                        replaceCurve(at: slotIndex, with: model.id, data: data)
                    } label: {
                        Text(
                            curveMenuTitle(
                                for: model,
                                currentSlotIndex: slotIndex,
                                occupiedSlotIndex: occupiedSlotIndex
                            )
                        )
                    }
                    .disabled(isCurrent || isUsedByOtherCurve)
                    .accessibilityLabel(
                        curveMenuAccessibilityLabel(
                            for: model,
                            currentSlotIndex: slotIndex,
                            occupiedSlotIndex: occupiedSlotIndex
                        )
                    )
                }
            }
        }
    }

    private func addCurveMenu(data: TrendSeriesData) -> some View {
        Menu {
            ForEach(data.selectableGroups) { group in
                Menu(group.title) {
                    ForEach(group.models) { model in
                        let occupiedSlotIndex = data.selectedModelIDs.firstIndex(of: model.id)
                        Button {
                            addCurve(modelID: model.id, data: data)
                        } label: {
                            Text(
                                addCurveMenuTitle(
                                    for: model,
                                    occupiedSlotIndex: occupiedSlotIndex
                                )
                            )
                        }
                        .disabled(occupiedSlotIndex != nil)
                        .accessibilityLabel(
                            occupiedSlotIndex.map {
                                "\(model.catalogEntry.displayLabel)，已用于\(seriesColorName(at: $0))曲线"
                            } ?? model.catalogEntry.displayLabel
                        )
                    }
                }
            }
        } label: {
            Label("添加曲线", systemImage: "plus")
                .font(.caption2)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(
            data.selectedModelIDs.count >= ModelTrendSeriesConfiguration.maximumCount
                || !hasUnselectedModel(in: data)
        )
        .accessibilityLabel("添加 \(state.metric.displayName) 趋势曲线")
    }

    private var trendSourceRevision: TrendChartSourceRevision {
        let snapshot = appModel.snapshot
        let benchmarks = snapshot?.benchmarks ?? []
        let costHistory = appModel.costHistory
        let calendar = Calendar.current
        return TrendChartSourceRevision(
            metric: state.metric,
            rangeDays: appModel.settings.modelTrendRange.rawValue,
            snapshotFetchedAt: snapshot?.fetchedAt,
            sourceMonitoredAt: snapshot?.sourceMonitoredAt,
            benchmarkCount: benchmarks.count,
            costHistoryCount: costHistory.count,
            timeZoneIdentifier: calendar.timeZone.identifier
        )
    }

    private var trendLoadInput: TrendChartLoadInput {
        TrendChartLoadInput(
            benchmarks: appModel.snapshot?.benchmarks ?? [],
            costHistory: appModel.costHistory,
            rankedModelIDs: appModel.rankings(for: state.metric).map(\.id),
            metric: state.metric,
            days: appModel.settings.modelTrendRange.rawValue,
            now: Date(),
            calendar: .current
        )
    }

    private var loadingState: some View {
        VStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
            Text("正在准备趋势数据…")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 275)
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

    private var collapsedSelectionSummary: String {
        guard let data = state.data, data.metric == state.metric, data.hasCustomSelection else {
            return "默认当前指标 Top 3"
        }
        return "已选 \(data.selectedModelIDs.count) 条曲线"
    }

    private func toggleExpansion() {
        withAnimation(ToolboxMotion.dashboard(reduceMotion: reduceMotion)) {
            isExpanded.toggle()
        }
    }

    private func replaceCurve(at index: Int, with modelID: String, data: TrendSeriesData) {
        guard data.selectedModelIDs.indices.contains(index),
              !data.selectedModelIDs.contains(modelID) else { return }
        var nextIDs = data.selectedModelIDs
        nextIDs[index] = modelID
        saveSelection(nextIDs, data: data)
    }

    private func addCurve(modelID: String, data: TrendSeriesData) {
        guard data.selectedModelIDs.count < ModelTrendSeriesConfiguration.maximumCount,
              !data.selectedModelIDs.contains(modelID) else { return }
        saveSelection(data.selectedModelIDs + [modelID], data: data)
    }

    private func removeCurve(at index: Int, data: TrendSeriesData) {
        guard data.selectedModelIDs.count > 1,
              data.selectedModelIDs.indices.contains(index) else { return }
        var nextIDs = data.selectedModelIDs
        nextIDs.remove(at: index)
        saveSelection(nextIDs, data: data)
    }

    private func saveSelection(_ modelIDs: [String], data: TrendSeriesData) {
        withAnimation(ToolboxMotion.dashboard(reduceMotion: reduceMotion)) {
            if modelIDs == data.automaticModelIDs {
                state.select(modelIDs: [])
                appModel.settings.resetModelTrendSelection(for: state.metric)
            } else {
                state.select(modelIDs: modelIDs)
                appModel.settings.setModelTrendSelection(modelIDs, for: state.metric)
            }
        }
    }

    private func compactModelName(for modelID: String, data: TrendSeriesData) -> String {
        guard let model = model(for: modelID, data: data) else { return modelID }
        return model.catalogEntry.compactLabel
    }

    private func fullModelName(for modelID: String, data: TrendSeriesData) -> String {
        guard let model = model(for: modelID, data: data) else { return modelID }
        return model.catalogEntry.displayLabel
    }

    private func model(for modelID: String, data: TrendSeriesData) -> ModelBenchmark? {
        for group in data.selectableGroups {
            if let model = group.models.first(where: { $0.id == modelID }) {
                return model
            }
        }
        return nil
    }

    private func hasUnselectedModel(in data: TrendSeriesData) -> Bool {
        data.selectableGroups.contains { group in
            group.models.contains { !data.selectedModelIDs.contains($0.id) }
        }
    }

    private func curveMenuTitle(
        for model: ModelBenchmark,
        currentSlotIndex: Int,
        occupiedSlotIndex: Int?
    ) -> String {
        if occupiedSlotIndex == currentSlotIndex {
            return "✓ \(model.catalogEntry.rowTitle) · 当前\(seriesColorName(at: currentSlotIndex))"
        }
        if let occupiedSlotIndex {
            return "\(model.catalogEntry.rowTitle) · 已用于\(seriesColorName(at: occupiedSlotIndex))"
        }
        return model.catalogEntry.rowTitle
    }

    private func curveMenuAccessibilityLabel(
        for model: ModelBenchmark,
        currentSlotIndex: Int,
        occupiedSlotIndex: Int?
    ) -> String {
        if occupiedSlotIndex == currentSlotIndex {
            return "\(model.catalogEntry.displayLabel)，当前\(seriesColorName(at: currentSlotIndex))曲线"
        }
        if let occupiedSlotIndex {
            return "\(model.catalogEntry.displayLabel)，已用于\(seriesColorName(at: occupiedSlotIndex))曲线"
        }
        return model.catalogEntry.displayLabel
    }

    private func addCurveMenuTitle(
        for model: ModelBenchmark,
        occupiedSlotIndex: Int?
    ) -> String {
        guard let occupiedSlotIndex else { return model.catalogEntry.rowTitle }
        return "\(model.catalogEntry.rowTitle) · 已用于\(seriesColorName(at: occupiedSlotIndex))"
    }

    private func seriesColor(at index: Int) -> Color {
        seriesColors[index % seriesColors.count]
    }

    private func seriesColorName(at index: Int) -> String {
        seriesColorNames[index % seriesColorNames.count]
    }

}

private struct TrendPlotView: View {
    let data: TrendSeriesData
    let metric: RankingMetric
    let seriesColors: [Color]

    @State private var hoveredDay: Date?

    var body: some View {
        Chart {
            ForEach(data.chartPoints) { point in
                if let day = point.day {
                    LineMark(
                        x: .value("日期", day),
                        y: .value(metric.displayName, point.value),
                        series: .value("模型", point.modelID)
                    )
                    .foregroundStyle(by: .value("模型", point.modelID))
                    .interpolationMethod(.catmullRom)

                    PointMark(
                        x: .value("日期", day),
                        y: .value(metric.displayName, point.value)
                    )
                    .foregroundStyle(by: .value("模型", point.modelID))
                    .symbolSize(20)
                }
            }

            if let hoveredDay {
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
                            .allowsHitTesting(false)
                    }
            }
        }
        .chartForegroundStyleScale(
            domain: data.selectedModelIDs,
            range: data.selectedModelIDs.indices.map { seriesColor(at: $0) }
        )
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: data.axisDays) { value in
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
                        Text(MetricFormatter.menuBarValue(number, metric: metric))
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
                        updateHover(phase, proxy: proxy, geometry: geometry)
                    }
            }
        }
        .onChange(of: metric) { _, _ in
            hoveredDay = nil
        }
        .onChange(of: data.selectedModelIDs) { _, _ in
            hoveredDay = nil
        }
        .accessibilityLabel("\(metric.displayName) 模型变化趋势")
        .accessibilityHint("将鼠标停留在数据点附近可查看该日详情")
    }

    private func updateHover(
        _ phase: HoverPhase,
        proxy: ChartProxy,
        geometry: GeometryProxy
    ) {
        switch phase {
        case let .active(location):
            guard let plotFrame = proxy.plotFrame else { return }
            let frame = geometry[plotFrame]
            guard frame.contains(location) else {
                if hoveredDay != nil {
                    hoveredDay = nil
                }
                return
            }
            let x = location.x - frame.origin.x
            let closestDay = proxy.value(atX: x, as: Date.self).flatMap {
                TrendPointBuilder.nearestDay(to: $0, inSortedDays: data.chartDays)
            }
            if hoveredDay != closestDay {
                hoveredDay = closestDay
            }
        case .ended:
            if hoveredDay != nil {
                hoveredDay = nil
            }
        }
    }

    private func seriesColor(at index: Int) -> Color {
        seriesColors[index % seriesColors.count]
    }

    @ViewBuilder
    private func hoverCard(for day: Date) -> some View {
        let values = data.pointsByDay[day] ?? []
        let latest = values.max { lhs, rhs in
            (lhs.recordedAt ?? .distantPast) < (rhs.recordedAt ?? .distantPast)
        }
        let usesTwoColumns = values.count >= 4
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: usesTwoColumns ? 2 : 1
        )
        let cardWidth: CGFloat = usesTwoColumns ? 280 : 195

        VStack(alignment: .leading, spacing: 3) {
            Text(
                latest.map { MetricFormatter.benchmarkDateLabel($0.dateKey, includesDetailedTime: true) }
                    ?? day.formatted(.dateTime.month(.twoDigits).day(.twoDigits))
            )
            .font(.caption2.bold())

            LazyVGrid(columns: columns, alignment: .leading, spacing: 3) {
                ForEach(values) { point in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(seriesColor(at: data.selectedModelIDs.firstIndex(of: point.modelID) ?? 0))
                            .frame(width: 7, height: 7)
                        Text(point.modelLabel)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(MetricFormatter.detailValue(point.value, metric: metric))
                            .monospacedDigit()
                    }
                    .font(.system(size: 9.5))
                }
            }
        }
        .frame(width: cardWidth, alignment: .leading)
        .padding(7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}
