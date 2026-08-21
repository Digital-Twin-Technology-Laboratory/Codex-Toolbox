import CodexToolboxCore
import SwiftUI

enum RankingSectionPresentation {
    case standard
    case expanded
    case compact

    var rowLimit: Int {
        switch self {
        case .standard: 3
        case .expanded: 5
        case .compact: 1
        }
    }

    var minimumContentHeight: CGFloat {
        switch self {
        case .standard: 88
        case .expanded: 146
        case .compact: 38
        }
    }

    var contentIdentity: String {
        switch self {
        case .standard: "standard"
        case .expanded: "expanded"
        case .compact: "compact"
        }
    }
}

struct RankingSection: View {
    let metric: RankingMetric
    let rankings: [RankedModel]
    let presentation: RankingSectionPresentation
    let showsExpandedMetrics: Bool
    let overallMode: OverallRankingMode
    let compactModelName: (ModelBenchmark) -> String
    let namespace: Namespace.ID
    let onExpand: () -> Void
    let onCollapse: () -> Void

    @StateObject private var interaction = RankingSectionInteractionState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dashboardTheme) private var dashboardTheme

    private var visibleRankings: [RankedModel] {
        Array(rankings.prefix(presentation.rowLimit))
    }

    var body: some View {
        Button {
            if presentation == .expanded {
                onCollapse()
            } else {
                onExpand()
            }
        } label: {
            GroupBox {
                rankingContent
                    .id(presentation.contentIdentity)
                    .transition(ToolboxMotion.rankingContentTransition)
            } label: {
                header
            }
            .groupBoxStyle(
                RankingGroupBoxStyle(
                    tint: tint,
                    isHovered: interaction.isHovered,
                    id: metric.rawValue,
                    namespace: namespace
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(ToolboxPressButtonStyle())
        .onHover { hovering in
            withAnimation(reduceMotion ? .easeOut(duration: 0.20) : .easeOut(duration: 0.16)) {
                interaction.isHovered = hovering
            }
        }
        .help(presentation == .expanded ? "点击收起“\(rankingTitle)”榜单" : "点击展开“\(rankingTitle)”榜单")
        .accessibilityLabel(sectionAccessibilityLabel)
        .accessibilityHint(presentation == .expanded ? "按下可恢复四宫格" : "按下可查看前五名")
    }

    private var rankingContent: some View {
        VStack(spacing: contentSpacing) {
            if showsMetricTable {
                metricTableHeader
                Divider()
            }

            ForEach(visibleRankings) { ranked in
                RankRow(
                    ranked: ranked,
                    presentation: presentation,
                    showsExpandedMetrics: showsExpandedMetrics,
                    overallMode: overallMode,
                    compactModelName: compactModelName(ranked.benchmark)
                )
                if ranked.id != visibleRankings.last?.id {
                    Divider()
                }
            }
            if rankings.isEmpty {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: presentation.minimumContentHeight)
            }
        }
        .frame(minHeight: presentation.minimumContentHeight, alignment: .top)
    }

    private var showsMetricTable: Bool {
        presentation == .expanded
            && showsExpandedMetrics
            && !visibleRankings.isEmpty
    }

    private var contentSpacing: CGFloat {
        if presentation == .compact {
            return 4
        }
        // The table header adds two stack children (the header and its
        // divider). Tighten only this presentation so the added semantics do
        // not create artificial overflow in the otherwise unchanged popover.
        return showsMetricTable ? 5 : 7
    }

    private var metricTableHeader: some View {
        let auxiliaryMetrics = RankingTableLayout.auxiliaryMetrics(for: metric)
        let auxiliaryColumnWidth = RankingTableLayout.auxiliaryColumnWidth(
            metricCount: auxiliaryMetrics.count
        )

        return HStack(spacing: RankingTableLayout.rowSpacing) {
            Color.clear
                .frame(width: RankingTableLayout.medalWidth, height: 1)

            Spacer(minLength: 0)

            HStack(spacing: RankingTableLayout.metricSpacing) {
                ForEach(auxiliaryMetrics, id: \.self) { auxiliaryMetric in
                    Text(auxiliaryMetric.displayName)
                        .frame(width: auxiliaryColumnWidth, alignment: .trailing)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Text(metric.displayName(overallMode: overallMode))
                .foregroundStyle(tint.opacity(0.82))
                .frame(width: RankingTableLayout.primaryValueWidth, alignment: .trailing)
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label(rankingTitle, systemImage: metric.systemImage)
                .font(.system(size: presentation == .compact ? 10 : 12, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .layoutPriority(2)

            if let metricExplanation {
                Text(metricExplanation)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }

            Spacer(minLength: 2)

            if presentation == .expanded {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 16, height: 16)
            } else if presentation == .standard, interaction.isHovered {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .transition(ToolboxMotion.hoverTransition(reduceMotion: reduceMotion))
            }
        }
    }

    private var rankingTitle: String {
        metric.rankingTitle(overallMode: overallMode)
    }

    private var tint: Color {
        dashboardTheme.palette.accent(for: metric)
    }

    private var metricExplanation: String? {
        guard presentation == .expanded else { return nil }
        switch metric {
        case .iq:
            return "Radar IQ 分数 · 越高越好"
        case .cost:
            return "平均费用 · 越低越好"
        case .duration:
            return "平均耗时 · 越低越好"
        case .overall:
            switch overallMode {
            case .localWeighted:
                return "本地 IQ / 费用 / 耗时加权 · 越高越好"
            case .radarCostEfficiency:
                return "Radar 费用 + 耗时指数 · 越低越好"
            }
        }
    }

    private var sectionAccessibilityLabel: String {
        [
            rankingTitle,
            metricExplanation,
            presentation == .expanded ? "已展开" : "点击展开"
        ]
        .compactMap { $0 }
        .joined(separator: "，")
    }

    private var emptyStateText: String {
        return metric == .overall && overallMode == .radarCostEfficiency
            ? "Radar 成本效率字段不可用"
            : "暂无可用数据"
    }
}

@MainActor
private final class RankingSectionInteractionState: ObservableObject {
    @Published var isHovered = false
}

private struct RankingGroupBoxStyle: GroupBoxStyle {
    let tint: Color
    let isHovered: Bool
    let id: String
    let namespace: Namespace.ID

    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            configuration.label
            configuration.content
        }
        .padding(11)
        .adaptiveGlassCard(
            tint: tint,
            id: id,
            namespace: namespace,
            isInteractive: true
        )
        .adaptiveInteractiveCardFeedback(tint: tint, isHovered: isHovered)
    }
}
