import ShowCodexIQCore
import SwiftUI

struct MenuBarLabel: View {
    @Bindable var appModel: AppModel

    var body: some View {
        if appModel.menuBarRanking.count == 2 {
            HStack(spacing: 3) {
                Image(systemName: appModel.settings.menuBarMetric.systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .symbolRenderingMode(.monochrome)
                    .frame(width: 16, height: 18)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(appModel.menuBarRanking) { ranked in
                        HStack(spacing: 4) {
                            Text(rowTitle(for: ranked))
                                .lineLimit(1)
                                .minimumScaleFactor(0.78)
                                .layoutPriority(1)

                            if appModel.settings.showsMenuBarDetails {
                                Spacer(minLength: 0)
                                Text(MetricFormatter.menuBarValue(ranked.value, metric: ranked.metric))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .fixedSize()
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 1)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(nsColor: .labelColor))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilitySummary)
        } else if appModel.isInitialLoading || appModel.isRefreshing {
            Label("正在刷新", systemImage: "brain.head.profile")
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("正在刷新 Codex 模型数据")
        } else {
            Label("数据不可用", systemImage: "exclamationmark.triangle")
                .font(.system(size: 10, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Codex 模型数据不可用")
        }
    }

    private func rowTitle(for ranked: RankedModel) -> String {
        appModel.settings.menuBarRankStyle.prefix(for: ranked.position)
            + MetricFormatter.compactModelName(ranked.benchmark.label)
    }

    private var accessibilitySummary: String {
        appModel.menuBarRanking.map { ranked in
            "第 \(ranked.position) 名 \(ranked.benchmark.label) \(MetricFormatter.detailValue(ranked.value, metric: ranked.metric))"
        }
        .joined(separator: "，")
    }
}
