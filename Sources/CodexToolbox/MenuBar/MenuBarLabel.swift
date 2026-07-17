import CodexToolboxCore
import SwiftUI

@MainActor
struct MenuBarLabel: View {
    @Bindable var appModel: AppModel
    let onPreferredWidthChange: (CGFloat) -> Void

    init(
        appModel: AppModel,
        onPreferredWidthChange: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.appModel = appModel
        self.onPreferredWidthChange = onPreferredWidthChange
    }

    var body: some View {
        content
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

    @ViewBuilder
    private var content: some View {
        if appModel.menuBarRanking.count == 2 {
            HStack(spacing: appModel.settings.showsMenuBarIcon ? 2 : 0) {
                if appModel.settings.showsMenuBarIcon {
                    Image(systemName: appModel.settings.menuBarMetric.systemImage)
                        .font(.system(size: 13, weight: .medium))
                        .symbolRenderingMode(.monochrome)
                        .frame(width: 14, height: 18)
                }

                Grid(alignment: .leading, horizontalSpacing: 3, verticalSpacing: 0) {
                    ForEach(appModel.menuBarRanking) { ranked in
                        GridRow {
                            Text(rowTitle(for: ranked))
                                .lineLimit(1)

                            if appModel.settings.showsMenuBarDetails {
                                Text(MetricFormatter.menuBarValue(ranked.value, metric: ranked.metric))
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
            .foregroundStyle(Color(nsColor: .labelColor))
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

    private func stateLabel(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 3) {
            if appModel.settings.showsMenuBarIcon {
                Image(systemName: systemImage)
            }
            Text(title)
        }
        .padding(.horizontal, 1)
        .font(.system(size: 10, weight: .medium))
    }

    private func rowTitle(for ranked: RankedModel) -> String {
        appModel.settings.menuBarRankStyle.prefix(for: ranked.position)
            + appModel.settings.menuBarModelName(
                modelID: ranked.benchmark.id,
                fullName: ranked.benchmark.label
            )
    }

    private var accessibilitySummary: String {
        appModel.menuBarRanking.map { ranked in
            "第 \(ranked.position) 名 \(ranked.benchmark.label) \(MetricFormatter.detailValue(ranked.value, metric: ranked.metric))"
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
