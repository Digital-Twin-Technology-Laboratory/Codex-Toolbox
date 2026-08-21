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
                    Text("Codex 雷达数据日期")
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
                        Text("暂无数据日期")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .adaptiveDashboardInsetSurface(tint: .blue)
    }

    private var tint: Color {
        dashboardTheme.palette.decorativeAccent(.blue)
    }
}
