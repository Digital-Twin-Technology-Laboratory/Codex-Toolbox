import CodexToolboxCore
import SwiftUI

struct ModelRadarSettingsView: View {
    @Bindable var appModel: AppModel
    @StateObject private var weights: WeightDraft
    let onOpenMenuBarAliases: () -> Void

    init(
        appModel: AppModel,
        onOpenMenuBarAliases: @escaping () -> Void = {}
    ) {
        self.appModel = appModel
        self.onOpenMenuBarAliases = onOpenMenuBarAliases
        _weights = StateObject(wrappedValue: WeightDraft(weights: appModel.settings.rankingWeights))
    }

    var body: some View {
        Form {
            Section("菜单栏") {
                AdaptiveGlassSegmentedPicker(
                    "默认展示",
                    selection: menuBarMetricBinding,
                    options: RankingMetric.allCases
                ) { metric in
                    Text(metric.displayName(overallMode: appModel.settings.overallRankingMode))
                }

                Picker("排名序号", selection: menuBarRankStyleBinding) {
                    ForEach(MenuBarRankStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                Toggle("显示左侧图标", isOn: showsMenuBarIconBinding)
                Toggle("显示后方详细数值", isOn: showsMenuBarDetailsBinding)

                Button(action: onOpenMenuBarAliases) {
                    HStack {
                        Text("模型名称简称")
                        Spacer()
                        Text(configuredAliasSummary)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("打开模型名称简称设置")
            }

            Section("榜单") {
                Toggle("显示数据详细时间", isOn: showsDetailedBenchmarkTimeBinding)
                    .help("关闭后仅显示 YYYY-MM-DD · AM/PM")
                Toggle("展开榜单显示其他指标", isOn: showsExpandedRankingMetricsBinding)
                    .help("主指标保持突出，并在展开榜单中补充其余原始指标")

                Picker("第四榜单", selection: overallRankingModeBinding) {
                    ForEach(OverallRankingMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text(appModel.settings.overallRankingMode == .localWeighted
                    ? "本地综合按 IQ、费用和耗时加权。"
                    : "Radar 成本效率只使用费用和耗时，指数越低越好。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("站长场景推荐") {
                Toggle("显示站长推荐", isOn: stationRecommendationsBinding)
                Picker("显示位置", selection: stationPlacementBinding) {
                    ForEach(StationRecommendationPlacement.allCases) { placement in
                        Text(placement.displayName).tag(placement)
                    }
                }
                .disabled(!appModel.settings.showsStationRecommendations)
                Text("关闭时不会请求推荐接口；开启后会与模型榜单一起刷新。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("变化趋势") {
                Toggle("显示模型趋势入口", isOn: showsTrendChartBinding)
                Toggle("固定展开", isOn: expandsTrendChartByDefaultBinding)
                    .disabled(!appModel.settings.showsTrendChart)
                    .help("每次打开看板时默认展开变化趋势，仍可在本次查看中手动折叠")
                Picker("趋势范围", selection: modelTrendRangeBinding) {
                    ForEach(ModelTrendRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
                .disabled(!appModel.settings.showsTrendChart)
            }

            Section("数据刷新") {
                Toggle("自动刷新", isOn: automaticRefreshBinding)
                Picker("刷新间隔", selection: refreshIntervalBinding) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .disabled(!appModel.settings.automaticRefreshEnabled)
            }

            if appModel.settings.overallRankingMode == .localWeighted {
                Section {
                    WeightDistributionSummary(weights: weights.weights)

                    WeightDistributionSlider(
                        firstBoundary: weights.firstBoundary,
                        secondBoundary: weights.secondBoundary,
                        onFirstBoundaryChange: { value in
                            weights.updateFirstBoundary(to: value)
                            applyWeights()
                        },
                        onSecondBoundaryChange: { value in
                            weights.updateSecondBoundary(to: value)
                            applyWeights()
                        }
                    )

                    HStack {
                        Button("恢复 50 / 25 / 25") {
                            weights.reset()
                            applyWeights()
                        }
                        Spacer()
                        Text("合计 100%")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("综合排名权重")
                } footer: {
                    Text("拖动两个分隔点调整三项占比；合计始终为 100%，调整后立即重新计算。")
                }
            }

        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var menuBarMetricBinding: Binding<RankingMetric> {
        Binding(
            get: { appModel.settings.menuBarMetric },
            set: { appModel.settings.menuBarMetric = $0 }
        )
    }

    private var automaticRefreshBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.automaticRefreshEnabled },
            set: {
                appModel.settings.automaticRefreshEnabled = $0
                appModel.settingsDidChange()
            }
        )
    }

    private var menuBarRankStyleBinding: Binding<MenuBarRankStyle> {
        Binding(
            get: { appModel.settings.menuBarRankStyle },
            set: { appModel.settings.menuBarRankStyle = $0 }
        )
    }

    private var showsMenuBarDetailsBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.showsMenuBarDetails },
            set: { appModel.settings.showsMenuBarDetails = $0 }
        )
    }

    private var showsMenuBarIconBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.showsMenuBarIcon },
            set: { appModel.settings.showsMenuBarIcon = $0 }
        )
    }

    private var showsTrendChartBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.showsTrendChart },
            set: { appModel.settings.showsTrendChart = $0 }
        )
    }

    private var showsDetailedBenchmarkTimeBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.showsDetailedBenchmarkTime },
            set: { appModel.settings.showsDetailedBenchmarkTime = $0 }
        )
    }

    private var showsExpandedRankingMetricsBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.showsExpandedRankingMetrics },
            set: { appModel.settings.showsExpandedRankingMetrics = $0 }
        )
    }

    private var expandsTrendChartByDefaultBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.expandsTrendChartByDefault },
            set: { appModel.settings.expandsTrendChartByDefault = $0 }
        )
    }

    private var modelTrendRangeBinding: Binding<ModelTrendRange> {
        Binding(
            get: { appModel.settings.modelTrendRange },
            set: { appModel.settings.modelTrendRange = $0 }
        )
    }

    private var refreshIntervalBinding: Binding<RefreshInterval> {
        Binding(
            get: { appModel.settings.refreshInterval },
            set: {
                appModel.settings.refreshInterval = $0
                appModel.settingsDidChange()
            }
        )
    }

    private var overallRankingModeBinding: Binding<OverallRankingMode> {
        Binding(
            get: { appModel.settings.overallRankingMode },
            set: { appModel.settings.overallRankingMode = $0 }
        )
    }

    private var stationRecommendationsBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.showsStationRecommendations },
            set: {
                appModel.settings.showsStationRecommendations = $0
                appModel.settingsDidChange()
            }
        )
    }

    private var stationPlacementBinding: Binding<StationRecommendationPlacement> {
        Binding(
            get: { appModel.settings.stationRecommendationPlacement },
            set: { appModel.settings.stationRecommendationPlacement = $0 }
        )
    }

    private func applyWeights() {
        _ = appModel.settings.apply(weights: weights.weights)
    }

    private var configuredAliasSummary: String {
        let count = appModel.settings.menuBarModelAliases.count
        return count == 0 ? "未设置" : "已设置 \(count) 个"
    }
}

private struct WeightDistributionSummary: View {
    let weights: RankingWeights

    var body: some View {
        HStack(spacing: 10) {
            WeightValueLabel(
                title: "智商",
                systemImage: "brain.head.profile",
                value: weights.iq,
                color: .blue
            )
            WeightValueLabel(
                title: "费用",
                systemImage: "dollarsign.circle",
                value: weights.cost,
                color: .green
            )
            WeightValueLabel(
                title: "耗时",
                systemImage: "clock",
                value: weights.duration,
                color: .orange
            )
        }
    }
}

private struct WeightValueLabel: View {
    let title: String
    let systemImage: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
            Text(title)
            Spacer(minLength: 4)
            Text("\(value)%")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
