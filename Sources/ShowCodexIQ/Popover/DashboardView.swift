import AppKit
import ShowCodexIQCore
import SwiftUI

struct DashboardView: View {
    @Bindable var appModel: AppModel
    @StateObject private var interaction = DashboardInteractionState()
    @Namespace private var rankingNamespace

    private let columns = [
        GridItem(.flexible(), spacing: 10),
        GridItem(.flexible(), spacing: 10)
    ]

    init(appModel: AppModel, initiallyExpandedMetric: RankingMetric? = nil) {
        self.appModel = appModel
        _interaction = StateObject(
            wrappedValue: DashboardInteractionState(expandedMetric: initiallyExpandedMetric)
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if appModel.snapshot == nil, !appModel.isInitialLoading {
                RadarEmptyStateView(appModel: appModel)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        StatusHeaderView(appModel: appModel)

                        if let error = appModel.errorMessage {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
                        }

                        rankingCards

                        TrendChartView(appModel: appModel)
                    }
                    .padding(14)
                }
            }

            Divider()
            footer
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
        .frame(width: 430, height: 680)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                LinearGradient(
                    colors: [.blue.opacity(0.045), .purple.opacity(0.035), .clear],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .task { await appModel.start() }
        .onAppear {
            Task { await appModel.refreshIfNeeded() }
        }
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
                withAnimation(.snappy(duration: 0.34, extraBounce: 0.04)) {
                    interaction.expandedMetric = metric
                }
            },
            onCollapse: {
                withAnimation(.snappy(duration: 0.30, extraBounce: 0.02)) {
                    interaction.expandedMetric = nil
                }
            }
        )
        .matchedGeometryEffect(id: metric.rawValue, in: rankingNamespace)
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
            }
            .adaptiveGlassIconStyle()
            .controlSize(.small)
            .help("设置")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .adaptiveGlassIconStyle()
            .controlSize(.small)
            .help("退出 Show Codex IQ")
        }
    }
}

@MainActor
private final class DashboardInteractionState: ObservableObject {
    @Published var expandedMetric: RankingMetric?

    init(expandedMetric: RankingMetric? = nil) {
        self.expandedMetric = expandedMetric
    }
}
