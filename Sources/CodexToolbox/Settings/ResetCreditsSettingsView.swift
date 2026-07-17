import CodexToolboxCore
import SwiftUI

struct ResetCreditsSettingsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        Form {
            Section("刷新") {
                Picker("刷新间隔", selection: refreshIntervalBinding) {
                    ForEach(ResetCreditsRefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
            }

            Section("显示") {
                Picker("临期提醒", selection: expiryWarningBinding) {
                    ForEach(ResetExpiryWarning.allCases) { warning in
                        Text(warning.displayName).tag(warning)
                    }
                }
                Toggle("显示重置卡说明文字", isOn: descriptionsBinding)
            }

            Section("只读边界") {
                Label("仅请求 account/rateLimits/read", systemImage: "lock.shield")
                Text("Codex Toolbox 不会兑换、删除或自动使用重置卡，也不会保存服务返回的 opaque credit ID。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var refreshIntervalBinding: Binding<ResetCreditsRefreshInterval> {
        Binding(
            get: { appModel.settings.resetCreditsRefreshInterval },
            set: {
                appModel.settings.resetCreditsRefreshInterval = $0
                appModel.settingsDidChange()
            }
        )
    }

    private var expiryWarningBinding: Binding<ResetExpiryWarning> {
        Binding(
            get: { appModel.settings.resetExpiryWarning },
            set: { appModel.settings.resetExpiryWarning = $0 }
        )
    }

    private var descriptionsBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.showsResetCreditDescriptions },
            set: { appModel.settings.showsResetCreditDescriptions = $0 }
        )
    }
}
