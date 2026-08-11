import CodexToolboxCore
import SwiftUI

struct StationRecommendationCard: View {
    @Bindable var appModel: AppModel
    let namespace: Namespace.ID

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            HStack(alignment: .top, spacing: 6) {
                ForEach(Array(StationRecommendationScenarioKey.allCases.enumerated()), id: \.element) { index, key in
                    if index > 0 {
                        Divider()
                    }
                    scenarioColumn(key)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(11)
        .adaptiveGlassCard(tint: .teal, id: "station-recommendations", namespace: namespace)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(spacing: 7) {
            Label("站长推荐", systemImage: "scope")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.teal)

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

            if let date = dataDate {
                Text(date)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func scenarioColumn(_ key: StationRecommendationScenarioKey) -> some View {
        let scenario = appModel.stationRecommendations?.scenario(for: key)
        return VStack(alignment: .leading, spacing: 5) {
            Text(key.shortTitle)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.teal)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(key.fallbackTitle)

            ForEach(0..<2, id: \.self) { index in
                recommendation(scenario?.items[safe: index])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(key.fallbackTitle)
    }

    private func recommendation(_ item: StationRecommendationItem?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.map(compactLabel) ?? "--")
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .truncationMode(.middle)

            HStack(spacing: 3) {
                Text(item?.iq.map { String(format: "%.1f", $0) } ?? "--")
                Text(item?.averageCostUSD.map { String(format: "$%.2f", $0) } ?? "--")
                Text(item?.averageDurationMinutes.map { String(format: "%.0f分", $0) } ?? "--")
            }
            .font(.system(size: 7.5, design: .rounded))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.62)
        }
        .frame(maxWidth: .infinity, minHeight: 25, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.map(accessibilityDescription) ?? "暂无推荐")
    }

    private func compactLabel(_ item: StationRecommendationItem) -> String {
        ModelCatalog.entry(model: item.model, reasoningEffort: item.effort).compactLabel
    }

    private func accessibilityDescription(_ item: StationRecommendationItem) -> String {
        let iq = item.iq.map { String(format: "%.1f", $0) } ?? "不可用"
        let cost = item.averageCostUSD.map { String(format: "%.2f 美元", $0) } ?? "不可用"
        let duration = item.averageDurationMinutes.map { String(format: "%.0f 分钟", $0) } ?? "不可用"
        return "\(compactLabel(item))，IQ \(iq)，费用 \(cost)，耗时 \(duration)"
    }

    private var dataDate: String? {
        let raw = appModel.stationRecommendations?.sourceUpdatedAt
            ?? appModel.stationRecommendations?.generatedAt
        guard let raw, raw.count >= 10 else { return raw }
        return String(raw.prefix(10))
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
