import Charts
import Combine
import CodexToolboxCore
import SwiftUI

@MainActor
private final class TrendChartState: ObservableObject {
    @Published var metric: RankingMetric = .iq
    @Published var hoveredDateKey: String?
}

struct TrendChartView: View {
    @Bindable var appModel: AppModel
    @StateObject private var state = TrendChartState()

    private let availableMetrics: [RankingMetric] = [.iq, .cost, .duration]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("变化趋势", systemImage: "chart.xyaxis.line")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Picker("趋势指标", selection: $state.metric) {
                    ForEach(availableMetrics) { metric in
                        Text(metric.displayName).tag(metric)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 190)
            }

            if TrendPointBuilder.hasDrawableSeries(points) {
                chart
                    .frame(height: 185)
            } else {
                VStack(spacing: 7) {
                    Image(systemName: state.metric == .cost ? "clock.badge.questionmark" : "chart.line.downtrend.xyaxis")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(emptyTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(emptyDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 150)
            }
        }
        .padding(12)
        .background(.background.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.secondary.opacity(0.14), lineWidth: 1)
        }
    }

    private var chart: some View {
        Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("日期", point.dateKey),
                    y: .value(state.metric.displayName, point.value),
                    series: .value("模型", point.modelID)
                )
                .foregroundStyle(by: .value("模型", MetricFormatter.compactModelName(point.modelLabel)))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("日期", point.dateKey),
                    y: .value(state.metric.displayName, point.value)
                )
                .foregroundStyle(by: .value("模型", MetricFormatter.compactModelName(point.modelLabel)))
                .symbolSize(20)
            }

            if let hoveredDateKey = state.hoveredDateKey {
                RuleMark(x: .value("选中日期", hoveredDateKey))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        hoverCard(for: hoveredDateKey)
                    }
            }
        }
        .chartLegend(position: .bottom, alignment: .leading, spacing: 6)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisTick()
                AxisValueLabel(anchor: .center) {
                    if let key = value.as(String.self) {
                        Text(TrendPointBuilder.shortDateLabel(key))
                    }
                }
                .font(.system(size: 8))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.secondary.opacity(0.12))
                AxisValueLabel(anchor: .center) {
                    if let number = value.as(Double.self) {
                        Text(MetricFormatter.menuBarValue(number, metric: state.metric))
                    }
                }
                .font(.system(size: 8))
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
                            let x = location.x - frame.origin.x
                            state.hoveredDateKey = proxy.value(atX: x, as: String.self)
                        case .ended:
                            state.hoveredDateKey = nil
                        }
                    }
            }
        }
    }

    private var selectedModelIDs: [String] {
        appModel.rankings(for: state.metric).prefix(3).map(\.id)
    }

    private var points: [TrendPoint] {
        TrendPointBuilder.points(
            benchmarks: appModel.snapshot?.benchmarks ?? [],
            costHistory: appModel.costHistory,
            metric: state.metric,
            modelIDs: selectedModelIDs
        )
    }

    private var emptyTitle: String {
        state.metric == .cost ? "正在积累费用历史" : "趋势数据不足"
    }

    private var emptyDescription: String {
        if state.metric == .cost {
            return "CodexRadar 未提供历史费用；应用从安装后在本地记录，至少两个测试日期后显示。"
        }
        return "至少需要同一模型的两个有效数据点。"
    }

    @ViewBuilder
    private func hoverCard(for dateKey: String) -> some View {
        let values = points.filter { $0.dateKey == dateKey }
        VStack(alignment: .leading, spacing: 2) {
            Text(TrendPointBuilder.shortDateLabel(dateKey))
                .font(.caption2.bold())
            ForEach(values) { point in
                Text("\(MetricFormatter.compactModelName(point.modelLabel))  \(MetricFormatter.detailValue(point.value, metric: state.metric))")
                    .font(.system(size: 9))
                    .monospacedDigit()
            }
        }
        .padding(6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
    }
}
