import CodexToolboxCore
import SwiftUI

enum RankingTableLayout {
    static let medalWidth: CGFloat = 22
    static let primaryValueWidth: CGFloat = 48
    static let rowSpacing: CGFloat = 6
    static let metricSpacing: CGFloat = 4

    static func auxiliaryMetrics(for metric: RankingMetric) -> [RankingMetric] {
        switch metric {
        case .iq:
            [.cost, .duration]
        case .cost:
            [.iq, .duration]
        case .duration:
            [.iq, .cost]
        case .overall:
            [.iq, .cost, .duration]
        }
    }

    static func auxiliaryColumnWidth(metricCount: Int) -> CGFloat {
        metricCount == 3 ? 42 : 54
    }
}

struct RankRow: View {
    let ranked: RankedModel
    let presentation: RankingSectionPresentation
    let showsExpandedMetrics: Bool
    let overallMode: OverallRankingMode

    var body: some View {
        Group {
            if presentation == .compact {
                compactBody
            } else {
                regularBody
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
    }

    private var regularBody: some View {
        HStack(spacing: RankingTableLayout.rowSpacing) {
            medal
                .frame(width: RankingTableLayout.medalWidth, height: RankingTableLayout.medalWidth)

            VStack(alignment: .leading, spacing: 1) {
                Text(ranked.benchmark.label)
                    .font(.system(size: presentation == .expanded ? 12 : 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(presentation == .standard ? 0.82 : 1)
                    .allowsTightening(presentation == .standard)
                    .truncationMode(.middle)
                    .layoutPriority(2)
                    .help(ranked.benchmark.label)
                if let statusText {
                    Text(statusText)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            if shouldShowExpandedMetrics {
                HStack(spacing: RankingTableLayout.metricSpacing) {
                    ForEach(expandedMetrics, id: \.self) { metric in
                        expandedMetricCell(metric)
                            .frame(width: expandedMetricColumnWidth, alignment: .trailing)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }

            valueText
                .frame(width: RankingTableLayout.primaryValueWidth, alignment: .trailing)
        }
        .frame(height: presentation == .expanded ? 27 : 25)
    }

    private var compactBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                medal
                    .frame(width: 18, height: 18)
                Text(MetricFormatter.compactModelName(ranked.benchmark.label))
                    .font(.system(size: 9, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(ranked.benchmark.label)
            }
            valueText
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var medal: some View {
        ZStack {
            Circle()
                .fill(medalColor.opacity(0.16))
            Text("\(ranked.position)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(medalColor)
        }
    }

    private var valueText: some View {
        Text(
            MetricFormatter.detailValue(
                ranked.value,
                metric: ranked.metric,
                overallMode: effectiveOverallMode
            )
        )
            .font(.system(size: presentation == .compact ? 10 : 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(ranked.metric.tint)
            .lineLimit(1)
            .minimumScaleFactor(0.68)
    }

    private var medalColor: Color {
        switch ranked.position {
        case 1: .yellow
        case 2: .gray
        case 3: .orange
        default: .secondary
        }
    }

    private var statusText: String? {
        guard ranked.metric != .overall,
              let latest = ranked.benchmark.latest,
              let passed = latest.passed,
              let tasks = latest.tasks else {
            return nil
        }
        return "\(passed)/\(tasks) 项通过"
    }

    private var shouldShowExpandedMetrics: Bool {
        presentation == .expanded
            && showsExpandedMetrics
    }

    private var expandedMetricColumnWidth: CGFloat {
        RankingTableLayout.auxiliaryColumnWidth(metricCount: expandedMetrics.count)
    }

    @ViewBuilder
    private func expandedMetricCell(_ metric: RankingMetric) -> some View {
        Group {
            if let value = ranked.benchmark.value(for: metric) {
                Text(MetricFormatter.detailValue(value, metric: metric))
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.68)
            } else {
                Text("—")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityLabel(metric.displayName)
        .accessibilityValue(
            ranked.benchmark.value(for: metric).map {
                MetricFormatter.detailValue($0, metric: metric)
            } ?? "暂无"
        )
    }

    private var expandedMetricSummary: String {
        expandedMetrics.compactMap { metric in
            ranked.benchmark.value(for: metric).map {
                "\(metric.displayName) \(MetricFormatter.detailValue($0, metric: metric))"
            }
        }
        .joined(separator: "  ·  ")
    }

    private var expandedMetrics: [RankingMetric] {
        RankingTableLayout.auxiliaryMetrics(for: ranked.metric)
    }

    private var accessibilityDescription: String {
        let primary = "第 \(ranked.position) 名，\(ranked.benchmark.label)，\(ranked.metric.displayName(overallMode: effectiveOverallMode)) \(MetricFormatter.detailValue(ranked.value, metric: ranked.metric, overallMode: effectiveOverallMode))"
        let status = statusText.map { "，\($0)" } ?? ""
        guard shouldShowExpandedMetrics else { return primary + status }
        return "\(primary)\(status)，其他指标：\(expandedMetricSummary)"
    }

    private var effectiveOverallMode: OverallRankingMode {
        ranked.overallMode ?? overallMode
    }
}
