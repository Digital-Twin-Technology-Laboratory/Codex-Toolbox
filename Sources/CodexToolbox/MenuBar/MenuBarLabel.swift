import CodexToolboxCore
import SwiftUI

@MainActor
struct MenuBarLabel: View {
    @Bindable var appModel: AppModel
    let itemID: UUID?
    let isPreview: Bool
    let onPreferredWidthChange: (CGFloat) -> Void

    init(
        appModel: AppModel,
        itemID: UUID? = nil,
        isPreview: Bool = false,
        onPreferredWidthChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.isPreview = isPreview
        self.itemID = itemID
        self.appModel = appModel
        self.onPreferredWidthChange = onPreferredWidthChange
    }

    var body: some View {
        content
            .foregroundStyle(isPreview ? Color.white : Color(nsColor: .labelColor))
            .fixedSize(horizontal: true, vertical: false)
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: MenuBarContentWidthPreferenceKey.self,
                        value: ceil(geometry.size.width)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .onPreferenceChange(MenuBarContentWidthPreferenceKey.self) { width in
                onPreferredWidthChange(max(1, width))
            }
    }

    private var selectedContent: MenuBarContent {
        (appModel.settings.menuBarConfiguration.items.first(where: { $0.id == itemID })?.content
            ?? MenuBarContent(rawValue: appModel.settings.menuBarMetric.rawValue) ?? .iq)
            .resolved(localCostEstimatesEnabled: appModel.settings.experimentalLocalCostEstimatesEnabled)
    }
    private var ranking: [RankedModel] {
        selectedContent.rankingMetric.map { Array(appModel.rankings(for: $0).prefix(2)) } ?? []
    }
    @ViewBuilder
    private var content: some View {
        if selectedContent.rankingMetric == nil {
            usageLabel
        } else if !ranking.isEmpty {
            HStack(spacing: appModel.settings.showsMenuBarIcon ? 2 : 0) {
                if appModel.settings.showsMenuBarIcon {
                    Image(systemName: selectedContent.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .frame(width: 14, height: 18)
                }

                Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 0) {
                    ForEach(ranking) { ranked in
                        GridRow {
                            Text(rowTitle(for: ranked))
                                .lineLimit(1)

                            if appModel.settings.showsMenuBarDetails {
                                Text(
                                    MetricFormatter.menuBarValue(
                                        ranked.value,
                                        metric: ranked.metric,
                                        overallMode: ranked.overallMode
                                            ?? appModel.settings.overallRankingMode
                                    )
                                )
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 1)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(isPreview ? Color.white : Color(nsColor: .labelColor))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        } else if appModel.isInitialLoading || appModel.isRefreshing {
            stateLabel("正在刷新", systemImage: "brain.head.profile")
                .accessibilityLabel("正在刷新 Codex 模型数据")
        } else {
            stateLabel("数据不可用", systemImage: "exclamationmark.triangle")
                .accessibilityLabel("Codex 模型数据不可用")
        }
    }

    @ViewBuilder private var usageLabel: some View {
        if selectedContent == .accountQuota {
            let windows = appModel.resetCreditsSnapshot?.quotaWindows.filter { $0.resetsAt > Date() } ?? []
            if windows.isEmpty {
                stateLabel(appModel.isAPIAuthentication ? "API 不适用" : "额度未提供", systemImage: selectedContent.systemImage)
            } else {
                HStack(spacing: 4) {
                    if appModel.settings.quotaDisplayOptions.showsIcon { Image(systemName: selectedContent.systemImage) }
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(windows) { window in
                            HStack(spacing: 3) {
                                Text(window.displayName)
                                QuotaIndicators(remainingPercent: 100 - window.usedPercent, options: appModel.settings.quotaDisplayOptions, compact: true)
                            }
                        }
                    }
                }.font(.system(size: 9, weight: .medium)).padding(.horizontal, 2)
            }
        } else {
            let summary = appModel.todayUsage
            let text = selectedContent == .todayTokens
                ? summary.map { MetricFormatter.menuBarTokens($0.totalTokens, format: appModel.settings.tokenMenuBarOptions.numberFormat) } ?? "未提供"
                : MetricFormatter.menuBarAPICost(summary?.totalCostUSD, precision: summary?.costPrecision, format: appModel.settings.tokenMenuBarOptions.numberFormat)
            stateLabel(text, systemImage: selectedContent.systemImage)
                .help(selectedContent.displayName + " · 当前 Mac" + (summary?.isComplete == false ? " · 不完整" : ""))
        }
    }

    private var showsSelectedIcon: Bool {
        switch selectedContent {
        case .todayTokens, .todayAPICost: appModel.settings.tokenMenuBarOptions.showsIcon
        case .accountQuota: appModel.settings.quotaDisplayOptions.showsIcon
        default: appModel.settings.showsMenuBarIcon
        }
    }

    private func stateLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            if showsSelectedIcon {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .padding(.horizontal, 1)
        .font(.system(size: 10, weight: .medium))
    }

    private func rowTitle(for ranked: RankedModel) -> String {
        appModel.settings.menuBarRankStyle.prefix(for: ranked.position)
            + appModel.settings.compactModelName(for: ranked.benchmark)
    }

    private var accessibilitySummary: String {
        ranking.map { ranked in
            "第 \(ranked.position) 名 \(ranked.benchmark.label) "
                + "\(ranked.metric.displayName(overallMode: ranked.overallMode ?? appModel.settings.overallRankingMode)) "
                + MetricFormatter.detailValue(
                    ranked.value,
                    metric: ranked.metric,
                    overallMode: ranked.overallMode ?? appModel.settings.overallRankingMode
                )
        }
        .joined(separator: "，")
    }
}

private struct MenuBarContentWidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 1

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
