import ShowCodexIQCore
import SwiftUI

struct StatusHeaderView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text("Codex 模型雷达")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }

                Spacer()

                Button {
                    Task { await appModel.refresh() }
                } label: {
                    if appModel.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .adaptiveGlassControlStyle()
                .controlSize(.small)
                .disabled(appModel.isRefreshing)
                .help("从 Codex 雷达重新获取")
                .accessibilityLabel("从 Codex 雷达重新获取数据")
            }

            HStack(spacing: 9) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.blue)

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
            .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(.blue.opacity(0.18), lineWidth: 1)
            }
        }
    }
}
