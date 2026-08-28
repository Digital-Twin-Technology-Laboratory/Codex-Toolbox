import CodexToolboxCore
import SwiftUI

struct GeneralDashboardSettingsView: View {
    @Bindable var appModel: AppModel
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    var body: some View {
        Form {
            if appModel.settings.experimentalDashboardThemesEnabled {
                Section("外观") {
                    Picker("看板主题", selection: dashboardThemeBinding) {
                        ForEach(DashboardTheme.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(.segmented)

                    DashboardThemePreview(theme: appModel.settings.dashboardTheme)

                    Text("主题仅影响菜单栏弹出的看板；设置窗口与菜单栏内容继续使用 macOS 原生外观。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

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
            case .retryingCheck:
                ProgressView().controlSize(.small)
                Text("网络暂不可用，正在重试检查…")
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
        case .checking, .retryingCheck, .downloading, .preparing, .installing:
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

    private var dashboardThemeBinding: Binding<DashboardTheme> {
        Binding(
            get: { appModel.settings.dashboardTheme },
            set: { appModel.settings.dashboardTheme = $0 }
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

private struct DashboardThemePreview: View {
    let theme: DashboardTheme

    var body: some View {
        DashboardThemePreviewContent()
            .environment(\.dashboardTheme, theme)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(theme.displayName)看板主题预览")
    }
}

private struct DashboardThemePreviewContent: View {
    @Namespace private var namespace
    @Environment(\.dashboardTheme) private var theme

    var body: some View {
        HStack(spacing: 8) {
            previewCard(title: "智商", systemImage: "brain.head.profile", metric: .iq)
            previewCard(title: "费用", systemImage: "dollarsign.circle", metric: .cost)
            previewCard(title: "综合", systemImage: "trophy", metric: .overall)
        }
        .padding(9)
        .frame(maxWidth: .infinity, minHeight: 82)
        .background { DashboardRootBackground() }
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(theme.palette.separator.opacity(0.65), lineWidth: 0.75)
        }
    }

    private func previewCard(
        title: String,
        systemImage: String,
        metric: RankingMetric
    ) -> some View {
        let tint = theme.palette.accent(for: metric)
        return VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(tint)
                .lineLimit(1)

            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.primary.opacity(0.72))
                .frame(width: 42, height: 4)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.secondary.opacity(0.42))
                .frame(width: 54, height: 3)
        }
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .padding(8)
        .adaptiveGlassCard(
            tint: tint,
            id: "theme-preview-\(metric.rawValue)",
            namespace: namespace
        )
    }
}
