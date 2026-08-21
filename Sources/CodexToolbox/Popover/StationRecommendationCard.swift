import CodexToolboxCore
import SwiftUI

struct StationRecommendationCard: View {
    @Bindable var appModel: AppModel
    let namespace: Namespace.ID

    @State private var isExpanded = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dashboardTheme) private var dashboardTheme

    var body: some View {
        Button {
            withAnimation(ToolboxMotion.dashboard(reduceMotion: reduceMotion)) {
                isExpanded.toggle()
            }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                header
                recommendationContent
            }
            .padding(11)
            .adaptiveGlassCard(
                tint: tint,
                id: "station-recommendations",
                namespace: namespace,
                isInteractive: true
            )
            .adaptiveInteractiveCardFeedback(tint: tint, isHovered: isHovered)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .accessibilityElement(children: .contain)
        }
        .buttonStyle(ToolboxPressButtonStyle())
        .onHover { hovering in
            withAnimation(reduceMotion ? .easeOut(duration: 0.20) : .easeOut(duration: 0.16)) {
                isHovered = hovering
            }
        }
        .help(isExpanded ? "点击折叠站长推荐详情" : "点击展开站长推荐详情")
        .accessibilityValue(isExpanded ? "已展开" : "已折叠")
        .accessibilityHint(isExpanded ? "按下可隐藏 IQ、费用和耗时" : "按下可显示 IQ、费用和耗时")
    }

    private var header: some View {
        HStack(spacing: 7) {
            Label("站长推荐", systemImage: "scope")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)

            Spacer(minLength: 4)

            if appModel.stationRecommendationState.isStale {
                Text("已过期")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("当前显示上次成功的过期数据")
            } else if appModel.isRefreshing || appModel.isRefreshingStationRecommendations {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityLabel("正在刷新站长推荐")
            }

            if isExpanded, let date = dataDate {
                Text(date)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var recommendationContent: some View {
        if isExpanded {
            expandedScenarioList
                .transition(
                    ToolboxMotion.dashboardContentTransition(
                        reduceMotion: reduceMotion
                    )
                )
        } else {
            compactScenarioGrid
                .transition(
                    ToolboxMotion.dashboardContentTransition(
                        reduceMotion: reduceMotion
                    )
                )
        }
    }

    private var compactScenarioGrid: some View {
        HStack(alignment: .top, spacing: 6) {
            ForEach(Array(StationRecommendationScenarioKey.allCases.enumerated()), id: \.element) { index, key in
                if index > 0 {
                    Divider()
                }
                compactScenarioColumn(key)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
    }

    private func compactScenarioColumn(_ key: StationRecommendationScenarioKey) -> some View {
        let items = visibleItems(for: key)
        let emptyLabel = emptyRecommendationLabel(for: key)
        return VStack(alignment: .leading, spacing: 5) {
            Text(key.shortTitle)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(key.fallbackTitle)

            ForEach(0..<2, id: \.self) { index in
                compactRecommendation(items[safe: index], emptyLabel: emptyLabel)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(key.fallbackTitle)
    }

    private func compactRecommendation(
        _ item: StationRecommendationItem?,
        emptyLabel: String
    ) -> some View {
        let fullLabel = item.map(displayLabel) ?? emptyLabel
        let compactLabel = item.map(compactDisplayLabel)
            ?? (emptyLabel == "当前筛选下无推荐" ? "已筛空" : "--")
        return Text(compactLabel)
            .font(.system(size: 9, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.68)
            .allowsTightening(true)
            .help(fullLabel)
            .frame(maxWidth: .infinity, minHeight: 12, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(fullLabel)
    }

    private var expandedScenarioList: some View {
        VStack(spacing: 0) {
            expandedMetricHeader
            Divider()

            ForEach(Array(StationRecommendationScenarioKey.allCases.enumerated()), id: \.element) { index, key in
                expandedScenarioRow(key)
                if index < StationRecommendationScenarioKey.allCases.count - 1 {
                    Divider()
                }
            }
        }
    }

    private var expandedMetricHeader: some View {
        HStack(spacing: StationRecommendationLayout.metricSpacing) {
            Color.clear
                .frame(width: StationRecommendationLayout.rankWidth, height: 1)

            Spacer(minLength: 0)

            Text("费用")
                .frame(width: StationRecommendationLayout.costWidth, alignment: .trailing)
            Text("耗时")
                .frame(width: StationRecommendationLayout.durationWidth, alignment: .trailing)
            Text("智商")
                .foregroundStyle(tint.opacity(0.82))
                .frame(width: StationRecommendationLayout.iqWidth, alignment: .trailing)
        }
        .font(.system(size: 8, weight: .semibold))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private func expandedScenarioRow(_ key: StationRecommendationScenarioKey) -> some View {
        let items = visibleItems(for: key)
        let emptyLabel = emptyRecommendationLabel(for: key)
        return VStack(alignment: .leading, spacing: 3) {
            Text(key.fallbackTitle)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)

            ForEach(0..<2, id: \.self) { index in
                expandedRecommendation(
                    items[safe: index],
                    position: index + 1,
                    emptyLabel: emptyLabel
                )
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(key.fallbackTitle)
    }

    private func expandedRecommendation(
        _ item: StationRecommendationItem?,
        position: Int,
        emptyLabel: String
    ) -> some View {
        HStack(spacing: StationRecommendationLayout.metricSpacing) {
            recommendationRank(position)

            Text(item.map(displayLabel) ?? emptyLabel)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .allowsTightening(true)
                .layoutPriority(1)
                .help(item.map(displayLabel) ?? emptyLabel)

            Spacer(minLength: 0)

            metricValue(
                item?.averageCostUSD.map { String(format: "$%.2f", $0) },
                width: StationRecommendationLayout.costWidth
            )
            metricValue(
                item?.averageDurationMinutes.map { String(format: "%.0f 分", $0) },
                width: StationRecommendationLayout.durationWidth
            )
            metricValue(
                item?.iq.map { String(format: "%.1f", $0) },
                width: StationRecommendationLayout.iqWidth,
                color: tint
            )
        }
        .frame(minHeight: StationRecommendationLayout.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.map(accessibilityDescription) ?? emptyLabel)
    }

    private func recommendationRank(_ position: Int) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.12))
            Text("\(position)")
                .font(.system(size: 8, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(
            width: StationRecommendationLayout.rankWidth,
            height: StationRecommendationLayout.rankWidth
        )
        .accessibilityHidden(true)
    }

    private func metricValue(
        _ value: String?,
        width: CGFloat,
        color: Color = .secondary
    ) -> some View {
        Text(value ?? "—")
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(value == nil ? color.opacity(0.55) : color)
            .monospacedDigit()
            .lineLimit(1)
            .frame(width: width, alignment: .trailing)
    }

    private func displayLabel(_ item: StationRecommendationItem) -> String {
        ModelCatalog.entry(model: item.model, reasoningEffort: item.effort).displayLabel
    }

    private func compactDisplayLabel(_ item: StationRecommendationItem) -> String {
        let benchmarkID = appModel.availableModels.first(where: {
            normalized($0.model) == normalized(item.model)
                && normalized($0.reasoningEffort) == normalized(item.effort)
        })?.id
        return appModel.settings.compactModelName(
            model: item.model,
            reasoningEffort: item.effort,
            legacyModelID: benchmarkID
        )
    }

    private func visibleItems(
        for key: StationRecommendationScenarioKey
    ) -> [StationRecommendationItem] {
        guard let scenario = appModel.stationRecommendations?.scenario(for: key) else { return [] }
        return scenario.items.filter {
            appModel.isModelVisible(model: $0.model, reasoningEffort: $0.effort)
        }
    }

    private func emptyRecommendationLabel(for key: StationRecommendationScenarioKey) -> String {
        guard let scenario = appModel.stationRecommendations?.scenario(for: key) else {
            return "暂无推荐"
        }
        return scenario.items.isEmpty ? "暂无推荐" : "当前筛选下无推荐"
    }

    private func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func accessibilityDescription(_ item: StationRecommendationItem) -> String {
        let iq = item.iq.map { String(format: "%.1f", $0) } ?? "不可用"
        let cost = item.averageCostUSD.map { String(format: "%.2f 美元", $0) } ?? "不可用"
        let duration = item.averageDurationMinutes.map { String(format: "%.0f 分钟", $0) } ?? "不可用"
        return "\(displayLabel(item))，IQ \(iq)，费用 \(cost)，耗时 \(duration)"
    }

    private var dataDate: String? {
        let raw = appModel.stationRecommendations?.sourceUpdatedAt
            ?? appModel.stationRecommendations?.generatedAt
        guard let raw, raw.count >= 10 else { return raw }
        return String(raw.prefix(10))
    }

    private var tint: Color {
        dashboardTheme.palette.decorativeAccent(.teal)
    }
}

private enum StationRecommendationLayout {
    static let rankWidth: CGFloat = 18
    static let costWidth: CGFloat = 54
    static let durationWidth: CGFloat = 54
    static let iqWidth: CGFloat = 44
    static let metricSpacing: CGFloat = 6
    static let rowHeight: CGFloat = 22
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
