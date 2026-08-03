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
}

struct RankingSection: View {
    let metric: RankingMetric
    let rankings: [RankedModel]
    let presentation: RankingSectionPresentation
    let showsExpandedMetrics: Bool
    let namespace: Namespace.ID
    let onExpand: () -> Void
    let onCollapse: () -> Void

    @StateObject private var interaction = RankingSectionInteractionState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                VStack(spacing: contentSpacing) {
                    if showsMetricTable {
                        metricTableHeader
                        Divider()
                    }

                    ForEach(visibleRankings) { ranked in
                        RankRow(
                            ranked: ranked,
                            presentation: presentation,
                            showsExpandedMetrics: showsExpandedMetrics
                        )
                        if ranked.id != visibleRankings.last?.id {
                            Divider()
                        }
                    }
                    if rankings.isEmpty {
                        Text("暂无可用数据")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: presentation.minimumContentHeight)
                    }
                }
                .frame(minHeight: presentation.minimumContentHeight, alignment: .top)
            } label: {
                header
            }
            .groupBoxStyle(
                RankingGroupBoxStyle(
                    tint: metric.tint,
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
        .help(presentation == .expanded ? "点击收起“\(metric.rankingTitle)”榜单" : "点击展开“\(metric.rankingTitle)”榜单")
        .accessibilityLabel("\(metric.rankingTitle)，\(presentation == .expanded ? "已展开" : "点击展开")")
        .accessibilityHint(presentation == .expanded ? "按下可恢复四宫格" : "按下可查看前五名")
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

            Text(metric.displayName)
                .foregroundStyle(metric.tint.opacity(0.82))
                .frame(width: RankingTableLayout.primaryValueWidth, alignment: .trailing)
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Label(metric.rankingTitle, systemImage: metric.systemImage)
                .font(.system(size: presentation == .compact ? 10 : 12, weight: .bold))
                .foregroundStyle(metric.tint)
                .lineLimit(1)

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
        .adaptiveGlassCard(tint: tint, id: id, namespace: namespace)
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(isHovered ? 0.42 : 0.12), lineWidth: isHovered ? 1.25 : 0.75)
        }
        .shadow(color: tint.opacity(isHovered ? 0.11 : 0.04), radius: isHovered ? 10 : 5, y: 3)
    }
}
