import AppKit
import CodexToolboxCore
import SwiftUI

struct DashboardView: View {
    @Bindable var appModel: AppModel
    @Bindable var layoutState: DashboardLayoutState
    @StateObject private var interaction = DashboardInteractionState()
    @State private var measuredContentHeight: CGFloat = 0
    @State private var measuredFooterHeight: CGFloat = 0
    @Namespace private var rankingNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    let onPreferredHeightChange: (CGFloat) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(
        appModel: AppModel,
        layoutState: DashboardLayoutState = DashboardLayoutState(),
        initiallyExpandedMetric: RankingMetric? = nil,
        onPreferredHeightChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.appModel = appModel
        self.layoutState = layoutState
        self.onPreferredHeightChange = onPreferredHeightChange
        _interaction = StateObject(
            wrappedValue: DashboardInteractionState(expandedMetric: initiallyExpandedMetric)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                dashboardContent
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: DashboardContentHeightPreferenceKey.self,
                                value: geometry.size.height
                            )
                        }
                    }
            }
            .scrollIndicators(isContentClipped ? .automatic : .hidden)

            Divider()
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    GeometryReader { geometry in
                        Color.clear.preference(
                            key: DashboardFooterHeightPreferenceKey.self,
                            value: geometry.size.height
                        )
                    }
                }
        }
        .frame(width: DashboardLayout.width, height: resolvedHeight)
        .background {
            ZStack {
                if reduceTransparency {
                    Color(nsColor: .windowBackgroundColor)
                } else {
                    Rectangle().fill(.ultraThinMaterial)
                    LinearGradient(
                        colors: [.blue.opacity(0.045), .purple.opacity(0.035), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            }
        }
        .task { await appModel.start() }
        .onAppear {
            Task { await appModel.refreshIfNeeded() }
        }
        .onPreferenceChange(DashboardContentHeightPreferenceKey.self) { height in
            measuredContentHeight = height
        }
        .onPreferenceChange(DashboardFooterHeightPreferenceKey.self) { height in
            measuredFooterHeight = height
        }
        .onChange(of: resolvedHeight, initial: true) { _, height in
            onPreferredHeightChange(height)
        }
    }

    @ViewBuilder
    private var dashboardContent: some View {
        VStack(spacing: 15) {
            dashboardBrand

            if appModel.settings.dashboardConfiguration.visibleModules.isEmpty {
                ContentUnavailableView {
                    Label("看板模块已全部隐藏", systemImage: "rectangle.3.group.slash")
                } description: {
                    Text("可在设置的“看板”页面重新启用模块。")
                }
                .frame(minHeight: DashboardLayout.emptyContentHeight)
            } else {
                ForEach(appModel.settings.dashboardConfiguration.visibleModules) { module in
                    moduleSection(module)
                    if module != appModel.settings.dashboardConfiguration.visibleModules.last {
                        Divider().padding(.horizontal, 2)
                    }
                }
            }
        }
        .padding(14)
    }

    private var dashboardBrand: some View {
        HStack(spacing: 9) {
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 7) {
                    Text("Codex Toolbox")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    if appModel.isDemoMode {
                        Text("演示数据")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.orange.opacity(0.12), in: Capsule())
                            .accessibilityLabel("当前为演示数据，不是账户真实查询")
                    }
                }
                Text("Codex 实用工具，一处查看")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func moduleSection(_ module: ToolboxModule) -> some View {
        let collapsed = appModel.settings.collapsedDashboardModules.contains(module)
        return VStack(spacing: 10) {
            DashboardModuleHeader(
                module: module,
                subtitle: moduleSubtitle(module),
                collapsedSummary: moduleSummary(module),
                isCollapsed: collapsed,
                isRefreshing: isRefreshing(module),
                refresh: { refresh(module) },
                toggleCollapsed: {
                    withAnimation(ToolboxMotion.dashboard(reduceMotion: reduceMotion)) {
                        appModel.settings.setDashboardModule(module, isCollapsed: !collapsed)
                    }
                }
            )

            if !collapsed {
                moduleContent(module)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
            }
        }
    }

    @ViewBuilder
    private func moduleContent(_ module: ToolboxModule) -> some View {
        switch module {
        case .modelRadar:
            modelRadarContent
        case .tokenUsage:
            TokenUsageModuleView(appModel: appModel)
        case .resetCredits:
            ResetCreditsModuleView(appModel: appModel)
        }
    }

    @ViewBuilder
    private var modelRadarContent: some View {
        if appModel.snapshot == nil, !appModel.isInitialLoading {
            RadarEmptyStateView(appModel: appModel)
                .frame(maxWidth: .infinity, minHeight: 150)
        } else {
            VStack(spacing: 10) {
                StatusHeaderView(appModel: appModel)
                if let error = appModel.errorMessage {
                    InlineModuleNotice(
                        text: error,
                        systemImage: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
                rankingCards
                if appModel.settings.showsTrendChart {
                    TrendChartView(appModel: appModel)
                }
            }
        }
    }

    private var idealHeight: CGFloat {
        measuredContentHeight + measuredFooterHeight + 1
    }

    private var resolvedHeight: CGFloat {
        min(
            layoutState.maximumHeight,
            max(DashboardLayout.minimumHeight, idealHeight)
        )
    }

    private var isContentClipped: Bool {
        idealHeight > layoutState.maximumHeight + 0.5
    }

    @ViewBuilder
    private var rankingCards: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                rankingLayout
            }
        } else {
            rankingLayout
        }
    }

    @ViewBuilder
    private var rankingLayout: some View {
        if let expandedMetric = interaction.expandedMetric {
            VStack(spacing: 10) {
                rankingSection(for: expandedMetric, presentation: .expanded)

                HStack(alignment: .top, spacing: 8) {
                    ForEach(RankingMetric.allCases.filter { $0 != expandedMetric }) { metric in
                        rankingSection(for: metric, presentation: .compact)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        } else {
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(RankingMetric.allCases) { metric in
                    rankingSection(for: metric, presentation: .standard)
                }
            }
        }
    }

    private func rankingSection(
        for metric: RankingMetric,
        presentation: RankingSectionPresentation
    ) -> some View {
        RankingSection(
            metric: metric,
            rankings: appModel.rankings(for: metric),
            presentation: presentation,
            namespace: rankingNamespace,
            onExpand: {
                withAnimation(ToolboxMotion.dashboard(reduceMotion: reduceMotion)) {
                    interaction.expandedMetric = metric
                }
            },
            onCollapse: {
                withAnimation(ToolboxMotion.dashboard(reduceMotion: reduceMotion)) {
                    interaction.expandedMetric = nil
                }
            }
        )
        .toolboxMatchedGeometryEffect(
            id: metric.rawValue,
            in: rankingNamespace,
            enabled: !reduceMotion
        )
    }

    private func moduleSubtitle(_ module: ToolboxModule) -> String {
        switch module {
        case .modelRadar: "Codex Radar 模型榜单"
        case .tokenUsage: "当前 Mac 的本机原始 Token"
        case .resetCredits: "账户只读查询，不会自动使用"
        }
    }

    private func moduleSummary(_ module: ToolboxModule) -> String? {
        switch module {
        case .modelRadar:
            return nil
        case .tokenUsage:
            if appModel.isUsageInitialLoading { return "正在读取…" }
            guard let summary = appModel.usageHistory?.summary(for: dayKey(Date())) else {
                return "今日 0"
            }
            let suffix = summary.isComplete ? "" : " · 不完整"
            return "今日 \(summary.totalTokens.formatted(.number.grouping(.automatic)))\(suffix)"
        case .resetCredits:
            if appModel.isResetCreditsInitialLoading { return "正在读取…" }
            guard let snapshot = appModel.resetCreditsSnapshot else { return "暂无数据" }
            return "可用 \(snapshot.availableCount) 张"
        }
    }

    private func dayKey(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func isRefreshing(_ module: ToolboxModule) -> Bool {
        switch module {
        case .modelRadar: appModel.isRefreshing
        case .tokenUsage: appModel.isRefreshingUsage
        case .resetCredits: appModel.isRefreshingResetCredits
        }
    }

    private func refresh(_ module: ToolboxModule) {
        Task {
            switch module {
            case .modelRadar: await appModel.refresh()
            case .tokenUsage: await appModel.refreshUsage()
            case .resetCredits: await appModel.refreshResetCredits()
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Link(destination: AppMetadata.radarURL) {
                Label("数据来自 Codex 雷达 codexradar.com", systemImage: "link")
            }
            .font(.caption)
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .overlay(alignment: .topTrailing) {
                        if appModel.updateManager.showsUpdateBadge {
                            Circle()
                                .fill(.red)
                                .frame(width: 7, height: 7)
                                .offset(x: 4, y: -4)
                                .accessibilityHidden(true)
                        }
                    }
            }
            .adaptiveGlassIconStyle()
            .controlSize(.small)
            .help(appModel.updateManager.showsUpdateBadge ? "设置（更新已下载）" : "设置")
            .accessibilityLabel(appModel.updateManager.showsUpdateBadge ? "设置，有更新可安装" : "设置")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .adaptiveGlassIconStyle()
            .controlSize(.small)
            .help("退出 Codex Toolbox")
        }
    }
}

private struct DashboardContentHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct DashboardFooterHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
private final class DashboardInteractionState: ObservableObject {
    @Published var expandedMetric: RankingMetric?

    init(expandedMetric: RankingMetric? = nil) {
        self.expandedMetric = expandedMetric
    }
}
