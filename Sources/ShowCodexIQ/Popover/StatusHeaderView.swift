import ShowCodexIQCore
import SwiftUI

struct StatusHeaderView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Image(systemName: "brain.head.profile")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.blue)
                    Text("Codex 模型雷达")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                }

                HStack(spacing: 7) {
                    Label(statusTitle, systemImage: statusSymbol)
                        .foregroundStyle(statusColor)
                    if let date = appModel.latestBenchmarkDate {
                        Text("测试 \(date)")
                    }
                }
                .font(.caption)

                if let refreshed = appModel.lastSuccessfulRefresh {
                    Text("获取于 \(refreshed.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
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
            .help("立即刷新")
            .accessibilityLabel("立即刷新 CodexRadar 数据")
        }
    }

    private var statusTitle: String {
        if appModel.isRefreshing { return "正在刷新" }
        if appModel.isStale { return "离线缓存" }
        if appModel.snapshot != nil { return "数据已更新" }
        return "等待数据"
    }

    private var statusSymbol: String {
        if appModel.isRefreshing { return "arrow.triangle.2.circlepath" }
        if appModel.isStale { return "wifi.slash" }
        if appModel.snapshot != nil { return "checkmark.circle.fill" }
        return "clock"
    }

    private var statusColor: Color {
        if appModel.isRefreshing { return .blue }
        if appModel.isStale { return .orange }
        if appModel.snapshot != nil { return .green }
        return .secondary
    }
}
