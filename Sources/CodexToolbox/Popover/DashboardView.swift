import AppKit
import CodexToolboxCore
import SwiftUI

struct DashboardView: View {
    @Bindable var appModel: AppModel
    @Bindable var layoutState: DashboardLayoutState
    @StateObject private var interaction = DashboardInteractionState()
    @State private var measuredContentHeight: CGFloat = 0
    @State private var measuredFooterHeight: CGFloat = 0
    @State private var scrollViewportHeight: CGFloat = 0
    @State private var isViewportShrinking = false
    @State private var showsScrollIndicators = false
    @State private var scrollIndicatorDebounceTask: Task<Void, Never>?
    @Namespace private var rankingNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onPreferredHeightChange: (CGFloat) -> Void

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
            wrappedValue: DashboardInteractionState(
                expandedMetric: initiallyExpandedMetric,
                isTrendExpanded: appModel.settings.showsTrendChart
                    && appModel.settings.expandsTrendChartByDefault
            )
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
            // Keep scrollability discoverable while filtering the temporary
            // content/viewport mismatch produced by collapse animations.
            .scrollIndicators(
                showsScrollIndicators ? .visible : .never,
                axes: .vertical
            )
            .background {
                GeometryReader { geometry in
                    Color.clear.preference(
                        key: DashboardScrollViewportHeightPreferenceKey.self,
                        value: geometry.size.height
                    )
                }
            }

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
            DashboardRootBackground()
        }
        .environment(\.dashboardTheme, appModel.settings.effectiveDashboardTheme)
        .task { await appModel.start() }
        .onAppear {
            scheduleScrollIndicatorUpdate()
            Task { await appModel.refreshIfNeeded() }
        }
        .onDisappear {
            scrollIndicatorDebounceTask?.cancel()
            scrollIndicatorDebounceTask = nil
            interaction.collapseTrend()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            interaction.collapseTrend()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.willShowNotification)) { _ in
            interaction.beginTrendSession(
                expandedByDefault: appModel.settings.showsTrendChart
                    && appModel.settings.expandsTrendChartByDefault
            )
        }
        .onChange(of: appModel.settings.showsTrendChart) { _, isVisible in
            if !isVisible {
                interaction.collapseTrend()
            }
        }
        .onPreferenceChange(DashboardContentHeightPreferenceKey.self) { height in
            measuredContentHeight = height
        }
        .onPreferenceChange(DashboardFooterHeightPreferenceKey.self) { height in
            measuredFooterHeight = height
        }
        .onPreferenceChange(DashboardScrollViewportHeightPreferenceKey.self) { height in
            guard height > 0 else { return }
            if scrollViewportHeight > 0,
               height < scrollViewportHeight - DashboardLayout.scrollViewportChangeThreshold {
                isViewportShrinking = true
            }
            scrollViewportHeight = height
            scheduleScrollIndicatorUpdate()
        }
        .onChange(of: measuredContentHeight) { _, _ in
            scheduleScrollIndicatorUpdate()
        }
        .onChange(of: measuredFooterHeight) { _, _ in
            scheduleScrollIndicatorUpdate()
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
                .foregroundStyle(appModel.settings.effectiveDashboardTheme.palette.brandAccent)
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
                    .transition(ToolboxMotion.dashboardContentTransition(reduceMotion: reduceMotion))
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
        } else if appModel.snapshot != nil, appModel.visibleModels.isEmpty {
            VStack(spacing: 9) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("当前筛选下没有可显示的模型")
                    .font(.subheadline.weight(.semibold))
                Text("不会自动重新开启模型；可在“智商显示 → 显示的模型”中调整。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                SettingsLink {
                    Label("打开设置", systemImage: "gearshape")
                }
                .controlSize(.small)
            }
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
                modelRadarCards
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

    private func scheduleScrollIndicatorUpdate() {
        scrollIndicatorDebounceTask?.cancel()
        scrollIndicatorDebounceTask = Task { @MainActor in
            try? await Task.sleep(
                nanoseconds: DashboardLayout.scrollIndicatorRefreshNanoseconds
            )
            guard !Task.isCancelled else { return }
            guard measuredContentHeight > 0, scrollViewportHeight > 0 else { return }
            let overflow = measuredContentHeight - scrollViewportHeight
            let threshold = showsScrollIndicators
                ? DashboardLayout.scrollIndicatorHideThreshold
                : DashboardLayout.scrollIndicatorShowThreshold
            let shouldShowIndicators = overflow > threshold
            if shouldShowIndicators, !showsScrollIndicators, isViewportShrinking {
                // The popover can resize one frame before its animated content.
                // Clear the one-shot suppression and re-check once the layout
                // has had another settling interval, so genuine overflow still
                // becomes visible after a screen or window size reduction.
                isViewportShrinking = false
                scheduleScrollIndicatorUpdate()
                return
            }
            isViewportShrinking = false
            if showsScrollIndicators != shouldShowIndicators {
                showsScrollIndicators = shouldShowIndicators
            }
        }
    }

    @ViewBuilder
    private var modelRadarCards: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 10) {
                modelRadarCardStack
            }
        } else {
            modelRadarCardStack
        }
    }

    private var modelRadarCardStack: some View {
        VStack(spacing: 10) {
            if appModel.settings.showsStationRecommendations,
               appModel.settings.stationRecommendationPlacement == .aboveRankings {
                StationRecommendationCard(appModel: appModel, namespace: rankingNamespace)
            }
            rankingLayout
            if appModel.settings.showsStationRecommendations,
               appModel.settings.stationRecommendationPlacement == .belowRankings {
                StationRecommendationCard(appModel: appModel, namespace: rankingNamespace)
            }
            if appModel.settings.showsTrendChart {
                TrendChartView(
                    appModel: appModel,
                    isExpanded: $interaction.isTrendExpanded,
                    namespace: rankingNamespace
                )
            }
        }
    }

    private var rankingLayout: some View {
        RankingCardsLayout(expandedMetric: interaction.expandedMetric) {
            ForEach(RankingMetric.allCases) { metric in
                rankingSection(
                    for: metric,
                    presentation: rankingPresentation(for: metric)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .accessibilitySortPriority(metric == interaction.expandedMetric ? 1 : 0)
            }
        }
    }

    private func rankingPresentation(
        for metric: RankingMetric
    ) -> RankingSectionPresentation {
        guard let expandedMetric = interaction.expandedMetric else { return .standard }
        return metric == expandedMetric ? .expanded : .compact
    }

    private func rankingSection(
        for metric: RankingMetric,
        presentation: RankingSectionPresentation
    ) -> some View {
        RankingSection(
            metric: metric,
            rankings: appModel.rankings(for: metric),
            presentation: presentation,
            showsExpandedMetrics: appModel.settings.showsExpandedRankingMetrics,
            overallMode: appModel.settings.overallRankingMode,
            compactModelName: { benchmark in
                appModel.settings.compactModelName(for: benchmark)
            },
            namespace: rankingNamespace,
            onExpand: {
                setExpandedMetric(metric)
            },
            onCollapse: {
                setExpandedMetric(nil)
            }
        )
    }

    private func setExpandedMetric(_ metric: RankingMetric?) {
        if reduceMotion {
            interaction.expandedMetric = metric
        } else {
            withAnimation(ToolboxMotion.dashboard(reduceMotion: false)) {
                interaction.expandedMetric = metric
            }
        }
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
            let cost = appModel.settings.showsAPICostEstimatesInMenuBar
                ? summary.totalCostUSD.map {
                    " · \(MetricFormatter.apiCost($0, precision: summary.costPrecision))"
                } ?? ""
                : ""
            return "今日 \(summary.totalTokens.formatted(.number.grouping(.automatic)))\(cost)\(suffix)"
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

/// Keeps all four ranking cards in one stable view hierarchy while their
/// frames move between the two-by-two grid and the expanded presentation.
/// Replacing the complete grid with a different stack makes SwiftUI treat the
/// cards as removals and insertions, so the first card can appear to jump while
/// the remaining cards animate from unrelated positions.
private struct RankingCardsLayout: Layout {
    let expandedMetric: RankingMetric?
    var spacing: CGFloat = 10
    var compactSpacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = resolvedWidth(for: proposal, subviews: subviews)
        let result = layoutResult(width: width, subviews: subviews)
        return CGSize(width: width, height: result.height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let result = layoutResult(width: bounds.width, subviews: subviews)
        for index in subviews.indices {
            let frame = result.frames[index]
            subviews[index].place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func resolvedWidth(
        for proposal: ProposedViewSize,
        subviews: Subviews
    ) -> CGFloat {
        if let proposedWidth = proposal.width, proposedWidth.isFinite {
            return max(0, proposedWidth)
        }

        let widestIdealSubview = subviews
            .map { $0.sizeThatFits(.unspecified).width }
            .max() ?? 0
        return expandedMetric == nil
            ? widestIdealSubview * 2 + spacing
            : widestIdealSubview
    }

    private func layoutResult(
        width: CGFloat,
        subviews: Subviews
    ) -> (frames: [CGRect], height: CGFloat) {
        guard !subviews.isEmpty else { return ([], 0) }
        if let expandedIndex, subviews.indices.contains(expandedIndex) {
            return expandedResult(
                width: width,
                expandedIndex: expandedIndex,
                subviews: subviews
            )
        }
        return gridResult(width: width, subviews: subviews)
    }

    private var expandedIndex: Int? {
        guard let expandedMetric else { return nil }
        return RankingMetric.allCases.firstIndex(of: expandedMetric)
    }

    private func gridResult(
        width: CGFloat,
        subviews: Subviews
    ) -> (frames: [CGRect], height: CGFloat) {
        let columnWidth = max(0, (width - spacing) / 2)
        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        var y: CGFloat = 0

        for rowStart in stride(from: 0, to: subviews.count, by: 2) {
            let rowIndices = rowStart..<min(rowStart + 2, subviews.count)
            let rowHeight = rowIndices.map { index in
                subviews[index].sizeThatFits(
                    ProposedViewSize(width: columnWidth, height: nil)
                ).height
            }.max() ?? 0

            for index in rowIndices {
                let column = index - rowStart
                frames[index] = CGRect(
                    x: CGFloat(column) * (columnWidth + spacing),
                    y: y,
                    width: columnWidth,
                    height: rowHeight
                )
            }

            y += rowHeight
            if rowStart + 2 < subviews.count {
                y += spacing
            }
        }

        return (frames, y)
    }

    private func expandedResult(
        width: CGFloat,
        expandedIndex: Int,
        subviews: Subviews
    ) -> (frames: [CGRect], height: CGFloat) {
        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        let expandedHeight = subviews[expandedIndex].sizeThatFits(
            ProposedViewSize(width: width, height: nil)
        ).height
        frames[expandedIndex] = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: expandedHeight
        )

        let compactIndices = subviews.indices.filter { $0 != expandedIndex }
        guard !compactIndices.isEmpty else { return (frames, expandedHeight) }

        let totalCompactSpacing = compactSpacing * CGFloat(compactIndices.count - 1)
        let compactWidth = max(
            0,
            (width - totalCompactSpacing) / CGFloat(compactIndices.count)
        )
        let compactHeight = compactIndices.map { index in
            subviews[index].sizeThatFits(
                ProposedViewSize(width: compactWidth, height: nil)
            ).height
        }.max() ?? 0
        let compactY = expandedHeight + spacing

        for (column, index) in compactIndices.enumerated() {
            frames[index] = CGRect(
                x: CGFloat(column) * (compactWidth + compactSpacing),
                y: compactY,
                width: compactWidth,
                height: compactHeight
            )
        }

        return (frames, compactY + compactHeight)
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

private struct DashboardScrollViewportHeightPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

@MainActor
private final class DashboardInteractionState: ObservableObject {
    @Published var expandedMetric: RankingMetric?
    @Published var isTrendExpanded: Bool

    init(expandedMetric: RankingMetric? = nil, isTrendExpanded: Bool = false) {
        self.expandedMetric = expandedMetric
        self.isTrendExpanded = isTrendExpanded
    }

    func beginTrendSession(expandedByDefault: Bool) {
        isTrendExpanded = expandedByDefault
    }

    func collapseTrend() {
        isTrendExpanded = false
    }
}
