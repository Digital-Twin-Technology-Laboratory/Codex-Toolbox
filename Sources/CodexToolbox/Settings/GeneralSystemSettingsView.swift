import SwiftUI

struct GeneralSystemSettingsView: View {
    @Bindable var appModel: AppModel
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some View {
        Form {
            Section("系统") {
                Toggle("登录时自动启动", isOn: launchAtLoginBinding)
                if let message = launchAtLogin.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !launchAtLogin.isInstalledInApplications {
                    Text("将 Codex Toolbox 安装到“应用程序”后才能启用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { enabled in
                launchAtLogin.setEnabled(enabled)
                appModel.settings.launchAtLoginEnabled = launchAtLogin.isEnabled
            }
        )
    }
}
