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
                Text("每张重置卡仅显示发放时间和过期时间，并统一换算为北京时间。")
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

}
