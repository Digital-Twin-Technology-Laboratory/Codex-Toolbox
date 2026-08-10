import CodexToolboxCore
import SwiftUI

struct StationRecommendationCard: View {
    @Bindable var appModel: AppModel
    let namespace: Namespace.ID

    private var selectedScenario: StationRecommendationScenario? {
        appModel.stationRecommendations?.scenario(
            for: appModel.settings.selectedStationRecommendationScenario
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Picker("站长推荐场景", selection: scenarioBinding) {
                ForEach(StationRecommendationScenarioKey.allCases) { key in
                    Text(key.shortTitle)
                        .tag(key)
                        .accessibilityLabel(key.fallbackTitle)
                }
            }
            .pickerStyle(.segmented)

            if let scenario = selectedScenario {
                VStack(alignment: .leading, spacing: 3) {
                    Text(scenario.title)
                        .font(.caption.weight(.semibold))
                    if let rule = scenario.rule {
                        Text(rule)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(alignment: .top, spacing: 8) {
                    ForEach(Array(scenario.items.enumerated()), id: \.offset) { _, item in
                        recommendation(item)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            } else if appModel.isRefreshing || appModel.isRefreshingStationRecommendations {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在加载站长推荐…")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, minHeight: 48)
            } else {
                Text(appModel.stationRecommendationState.errorMessage ?? "暂无可用的站长推荐数据")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
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
            Text("按场景给出两项实用选择")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            if appModel.stationRecommendationState.isStale {
                Text("已过期")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel("当前显示上次成功的过期数据")
            }
            if let date = dataDate {
                Text(date)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Button {
                Task { await appModel.refreshStationRecommendations() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(appModel.isRefreshing || appModel.isRefreshingStationRecommendations)
            .help("刷新站长推荐")
        }
    }

    private func recommendation(_ item: StationRecommendationItem) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text(item.model)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(item.effort)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.teal)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(.teal.opacity(0.10), in: Capsule())
            }
            HStack(spacing: 8) {
                metric("IQ", item.iq.map { String(format: "%.1f", $0) })
                metric("费用", item.averageCostUSD.map { String(format: "$%.2f", $0) })
                metric("耗时", item.averageDurationMinutes.map { String(format: "%.0f分", $0) })
            }
            if let rule = item.rule {
                Text(rule)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription(item))
    }

    private func metric(_ title: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).foregroundStyle(.tertiary)
            Text(value ?? "不可用")
                .foregroundStyle(value == nil ? .secondary : .primary)
                .monospacedDigit()
        }
        .font(.system(size: 9))
    }

    private func accessibilityDescription(_ item: StationRecommendationItem) -> String {
        let iq = item.iq.map { String(format: "%.1f", $0) } ?? "不可用"
        let cost = item.averageCostUSD.map { String(format: "%.2f 美元", $0) } ?? "不可用"
        let duration = item.averageDurationMinutes.map { String(format: "%.0f 分钟", $0) } ?? "不可用"
        return "\(item.model)，推理强度 \(item.effort)，IQ \(iq)，费用 \(cost)，耗时 \(duration)"
    }

    private var scenarioBinding: Binding<StationRecommendationScenarioKey> {
        Binding(
            get: { appModel.settings.selectedStationRecommendationScenario },
            set: { appModel.settings.selectedStationRecommendationScenario = $0 }
        )
    }

    private var dataDate: String? {
        let raw = appModel.stationRecommendations?.sourceUpdatedAt
            ?? appModel.stationRecommendations?.generatedAt
        guard let raw, raw.count >= 10 else { return raw }
        return String(raw.prefix(10))
    }
}
