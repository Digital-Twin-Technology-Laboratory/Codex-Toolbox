import CodexToolboxCore
import SwiftUI

struct StatusHeaderView: View {
    @Bindable var appModel: AppModel
    @Environment(\.dashboardTheme) private var dashboardTheme

    var body: some View {
        HStack(spacing: 9) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)

                VStack(alignment: .leading, spacing: 1) {
                    Text(appModel.snapshot?.managed?.dataset.name ?? "Codex 雷达数据日期")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)

                    if let date = appModel.latestBenchmarkDate {
                        Text(
                            MetricFormatter.benchmarkDateLabel(
                                date,
                                includesDetailedTime: appModel.settings.showsDetailedBenchmarkTime
                            )
                        )
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Text(appModel.snapshot?.benchmarks.isEmpty == false ? "源数据日期未提供" : "暂无数据日期")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                }

                Spacer()

                if appModel.isStale || appModel.snapshot?.managed?.status == "no_data" {
                    Label(appModel.radarStatusLabel, systemImage: "clock.arrow.circlepath")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(appModel.radarStatusLabel)
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .adaptiveDashboardInsetSurface(tint: .blue)
        .help(syncDetails)
    }

    private var syncDetails: String {
        var details = [appModel.radarStatusLabel]
        if let managed = appModel.snapshot?.managed {
            details.append("网站检查：" + MetricFormatter.benchmarkDateLabel(managed.checkedAt, includesDetailedTime: true))
            details.append(contentsOf: managed.sources.map { "来源：" + $0.name })
        }
        if let checked = appModel.repositoryState.checkedAt {
            details.append("客户端检查：" + checked.formatted(date: .numeric, time: .standard))
        }
        return details.joined(separator: "\n")
    }

    private var tint: Color {
        dashboardTheme.palette.decorativeAccent(.blue)
    }
}
