import ShowCodexIQCore
import SwiftUI

struct RankRow: View {
    let ranked: RankedModel
    let presentation: RankingSectionPresentation

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
        .accessibilityLabel(
            "第 \(ranked.position) 名，\(ranked.benchmark.label)，\(MetricFormatter.detailValue(ranked.value, metric: ranked.metric))"
        )
    }

    private var regularBody: some View {
        HStack(spacing: 7) {
            medal
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(ranked.benchmark.label)
                    .font(.system(size: presentation == .expanded ? 12 : 11, weight: .semibold))
                    .lineLimit(presentation == .expanded ? 2 : 1)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(ranked.benchmark.label)
                Text(statusText)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            valueText
        }
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
        Text(MetricFormatter.detailValue(ranked.value, metric: ranked.metric))
            .font(.system(size: presentation == .compact ? 10 : 11, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(ranked.metric.tint)
            .lineLimit(1)
    }

    private var medalColor: Color {
        switch ranked.position {
        case 1: .yellow
        case 2: .gray
        case 3: .orange
        default: .secondary
        }
    }

    private var statusText: String {
        if ranked.metric == .overall {
            return "加权百分位"
        }
        guard let latest = ranked.benchmark.latest else { return "暂无详细数据" }
        if let passed = latest.passed, let tasks = latest.tasks {
            return "\(passed)/\(tasks) 项通过"
        }
        return ranked.benchmark.reasoningEffort
    }
}
