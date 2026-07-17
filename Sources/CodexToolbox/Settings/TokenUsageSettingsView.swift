import CodexToolboxCore
import SwiftUI

struct TokenUsageSettingsView: View {
    @Bindable var appModel: AppModel
    @State private var confirmsClearHistory = false

    var body: some View {
        Form {
            Section("刷新与趋势") {
                Picker("刷新间隔", selection: refreshIntervalBinding) {
                    ForEach(UsageRefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                Picker("趋势范围", selection: trendRangeBinding) {
                    ForEach(UsageTrendRange.allCases) { range in
                        Text(range.displayName).tag(range)
                    }
                }
            }

            Section("隐私") {
                Toggle("隐藏任务标题", isOn: anonymizesTitlesBinding)
                Text("开启后，看板只显示“任务 1、任务 2…”。标题仍只保存在本机账本中。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    private var anonymizesTitlesBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.anonymizesTaskTitles },
            set: { appModel.settings.anonymizesTaskTitles = $0 }
        )
    }
}
