import CodexToolboxCore
import SwiftUI

struct TokenUsageSettingsView: View {
    @Bindable var appModel: AppModel
    @State private var confirmsClearHistory = false

    var body: some View {
        Form {
            Section("刷新") {
                Picker("刷新间隔", selection: refreshIntervalBinding) {
                    ForEach(UsageRefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
            }

            Section("任务榜单") {
                Picker("榜单展开后", selection: expandedTaskLimitBinding) {
                    ForEach(UsageExpandedTaskLimit.allCases) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
                Text("默认显示 Top 3；点击任务卡后按此设置展开。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("每日趋势") {
                Picker("趋势范围", selection: trendRangeBinding) {
                    ForEach(UsageTrendRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
            }

            Section("本机历史") {
                Button("清除 Token 历史…", role: .destructive) {
                    confirmsClearHistory = true
                }
                Text("清除后会立即从仍可读取的 rollout 文件重新回填；已删除文件对应的历史无法恢复。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .confirmationDialog("清除本机 Token 历史？", isPresented: $confirmsClearHistory) {
            Button("清除并重新扫描", role: .destructive) {
                Task { await appModel.clearUsageHistory() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("此操作只删除 Codex Toolbox 的本机账本，不会修改 Codex 任务或账户数据。")
        }
    }

    private var refreshIntervalBinding: Binding<UsageRefreshInterval> {
        Binding(
            get: { appModel.settings.usageRefreshInterval },
            set: {
                appModel.settings.usageRefreshInterval = $0
                appModel.settingsDidChange()
            }
        )
    }

    private var trendRangeBinding: Binding<UsageTrendRange> {
        Binding(
            get: { appModel.settings.usageTrendRange },
            set: { appModel.settings.usageTrendRange = $0 }
        )
    }

    private var expandedTaskLimitBinding: Binding<UsageExpandedTaskLimit> {
        Binding(
            get: { appModel.settings.usageExpandedTaskLimit },
            set: { appModel.settings.usageExpandedTaskLimit = $0 }
        )
    }

}
