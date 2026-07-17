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

            Section("隐私") {
                Label("本机 Token 审计不调用模型、不上传任务内容", systemImage: "externaldrive.badge.checkmark")
                Label("重置卡通过本机 Codex app-server 只读查询", systemImage: "person.badge.shield.checkmark")
                Label("模型榜单只访问 Codex Radar 的公开 JSON", systemImage: "network")
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
