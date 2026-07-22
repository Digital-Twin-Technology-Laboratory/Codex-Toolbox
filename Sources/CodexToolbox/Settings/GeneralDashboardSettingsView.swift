import CodexToolboxCore
import SwiftUI

struct GeneralDashboardSettingsView: View {
    @Bindable var appModel: AppModel
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some View {
        Form {
            Section("通用") {
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

            Section("软件更新") {
                Toggle("自动检查并在后台下载", isOn: automaticUpdateBinding)

                Picker("检查频率", selection: updateFrequencyBinding) {
                    ForEach(UpdateCheckFrequency.allCases) { frequency in
                        Text(frequency.displayName).tag(frequency)
                    }
                }
                .disabled(!appModel.updateManager.automaticallyChecksForUpdates)

                updateStatus
            }

            Section("看板顺序") {
                Text("拖动模块或使用上下按钮调整顺序。显示与折叠状态会立即同步到菜单栏看板。")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(appModel.settings.dashboardModuleOrder) { module in
                    moduleRow(module)
                        .draggable(module.rawValue)
                        .dropDestination(for: String.self) { values, _ in
                            guard let rawValue = values.first,
                                  let source = ToolboxModule(rawValue: rawValue),
                                  let destination = appModel.settings.dashboardModuleOrder.firstIndex(of: module) else {
                                return false
                            }
                            appModel.settings.moveDashboardModule(source, to: destination)
                            return true
                        }
                }

                Button("恢复默认布局") {
                    appModel.settings.resetDashboardConfiguration()
                }
            }

            Section("隐私边界") {
                Label("本机 Token 审计不调用模型、不上传任务内容", systemImage: "externaldrive.badge.checkmark")
                Label("重置卡仅保存发放时间、过期时间与可用状态", systemImage: "person.badge.shield.checkmark")
                Label("更新只从 GitHub 下载，并使用 Ed25519 与代码签名双重校验", systemImage: "arrow.triangle.2.circlepath")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    @ViewBuilder
    private var updateStatus: some View {
        HStack(spacing: 8) {
            switch appModel.updateManager.state {
            case .idle:
                Text("将在后台自动检查更新")
                    .foregroundStyle(.secondary)
            case .checking:
                ProgressView().controlSize(.small)
                Text("正在检查更新…")
                    .foregroundStyle(.secondary)
            case .upToDate:
                Label("已是最新正式版", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case let .downloading(version):
                ProgressView().controlSize(.small)
                Text("正在后台下载 \(version)…")
                    .foregroundStyle(.secondary)
            case let .preparing(version):
                ProgressView().controlSize(.small)
                Text("正在准备 \(version)…")
                    .foregroundStyle(.secondary)
            case let .readyToInstall(version):
                Label("\(version) 已下载，可立即更新", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.blue)
            case let .installing(version):
                ProgressView().controlSize(.small)
                Text("正在安装 \(version)，应用将自动重启…")
                    .foregroundStyle(.secondary)
            case let .failed(message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            Spacer()

            if case .readyToInstall = appModel.updateManager.state {
                Button("立即更新") {
                    appModel.updateManager.installReadyUpdate()
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("立即检查") {
                    appModel.updateManager.checkForUpdates()
                }
                .disabled(isUpdateActionDisabled)
            }
        }
        .font(.caption)
    }

    private var isUpdateActionDisabled: Bool {
        switch appModel.updateManager.state {
        case .checking, .downloading, .preparing, .installing:
            true
        case .idle, .upToDate, .readyToInstall, .failed:
            false
        }
    }

    private func moduleRow(_ module: ToolboxModule) -> some View {
        HStack(spacing: 9) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
            Label(module.displayName, systemImage: module.systemImage)
            Spacer()

            Toggle("显示", isOn: Binding(
                get: { !appModel.settings.hiddenDashboardModules.contains(module) },
                set: { appModel.settings.setDashboardModule(module, isVisible: $0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .help("在看板中显示\(module.displayName)")

            Button {
                appModel.settings.moveDashboardModuleUp(module)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(module == appModel.settings.dashboardModuleOrder.first)
            .help("上移\(module.displayName)")

            Button {
                appModel.settings.moveDashboardModuleDown(module)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(module == appModel.settings.dashboardModuleOrder.last)
            .help("下移\(module.displayName)")
        }
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

    private var automaticUpdateBinding: Binding<Bool> {
        Binding(
            get: { appModel.updateManager.automaticallyChecksForUpdates },
            set: { appModel.updateManager.setAutomaticallyChecksForUpdates($0) }
        )
    }

    private var updateFrequencyBinding: Binding<UpdateCheckFrequency> {
        Binding(
            get: { appModel.updateManager.checkFrequency },
            set: { appModel.updateManager.setCheckFrequency($0) }
        )
    }
}
