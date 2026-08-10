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

            Section("官方费率与 Credits") {
                Toggle("自动更新官方费率", isOn: automaticRateUpdatesBinding)
                Picker("费率制度", selection: rateCardModeBinding) {
                    ForEach(RateCardMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("当前版本 \(appModel.rateCardState.manifest.currentVersion)")
                        Text(rateCardStatus)
                            .foregroundStyle(appModel.isRateCardStale ? .orange : .secondary)
                    }
                    .font(.caption)
                    Spacer()
                    Button("立即检查") {
                        Task { await appModel.refreshRateCard() }
                    }
                    .disabled(appModel.isRefreshingRateCard)
                }

                Text("自动模式仅在可确认 ChatGPT 计划时计算 Credits；API Key 用量不套用 ChatGPT Credits。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let errorMessage = appModel.rateCardState.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.orange)
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

    private var automaticRateUpdatesBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.automaticRateCardUpdatesEnabled },
            set: {
                appModel.settings.automaticRateCardUpdatesEnabled = $0
                appModel.settingsDidChange()
            }
        )
    }

    private var rateCardModeBinding: Binding<RateCardMode> {
        Binding(
            get: { appModel.settings.rateCardMode },
            set: {
                appModel.settings.rateCardMode = $0
                appModel.settingsDidChange()
            }
        )
    }

    private var rateCardStatus: String {
        if appModel.isRateCardStale { return "费率可能过期" }
        switch appModel.rateCardState.source {
        case .bundled: return "内置回退数据"
        case .cached: return "上次有效缓存"
        case .remote: return "已从项目托管清单校验"
        }
    }

}
