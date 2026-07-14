import ShowCodexIQCore
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var appModel: AppModel
    @StateObject private var weights: WeightDraft
    @StateObject private var launchAtLogin = LaunchAtLoginController()

    init(appModel: AppModel) {
        self.appModel = appModel
        _weights = StateObject(wrappedValue: WeightDraft(weights: appModel.settings.rankingWeights))
    }

    var body: some View {
        Form {
            Section("菜单栏") {
                Picker("默认展示", selection: menuBarMetricBinding) {
                    ForEach(RankingMetric.allCases) { metric in
                        Label(metric.displayName, systemImage: metric.systemImage)
                            .tag(metric)
                    }
                }
                .pickerStyle(.segmented)

                Picker("排名序号", selection: menuBarRankStyleBinding) {
                    ForEach(MenuBarRankStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }

                Toggle("显示后方详细数值", isOn: showsMenuBarDetailsBinding)
            }

            Section("数据刷新") {
                Toggle("自动刷新", isOn: automaticRefreshBinding)
                Picker("刷新间隔", selection: refreshIntervalBinding) {
                    ForEach(RefreshInterval.allCases) { interval in
                        Text(interval.displayName).tag(interval)
                    }
                }
                .disabled(!appModel.settings.automaticRefreshEnabled)
            }

            Section {
                WeightInputRow(title: "智商", systemImage: "brain.head.profile", value: $weights.iq)
                WeightInputRow(title: "费用", systemImage: "dollarsign.circle", value: $weights.cost)
                WeightInputRow(title: "耗时", systemImage: "clock", value: $weights.duration)

                HStack {
                    Text("当前合计")
                    Spacer()
                    Text("\(weights.total)%")
                        .monospacedDigit()
                        .foregroundStyle(weights.isValid ? .green : .red)
                }

                HStack {
                    Button("恢复 50 / 25 / 25") {
                        weights.reset()
                        applyWeights()
                    }
                    Spacer()
                    Button("应用权重") {
                        applyWeights()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!weights.isValid)
                }
            } header: {
                Text("综合排名权重")
            } footer: {
                Text("三项必须合计 100%；调整后立即重新计算，不需要刷新数据。")
            }

            Section("系统") {
                Toggle("登录时自动启动", isOn: launchAtLoginBinding)
                if let message = launchAtLogin.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !launchAtLogin.isInstalledInApplications {
                    Text("将应用拖入“应用程序”后才能启用。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var menuBarMetricBinding: Binding<RankingMetric> {
        Binding(
            get: { appModel.settings.menuBarMetric },
            set: { appModel.settings.menuBarMetric = $0 }
        )
    }

    private var automaticRefreshBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.automaticRefreshEnabled },
            set: {
                appModel.settings.automaticRefreshEnabled = $0
                appModel.settingsDidChange()
            }
        )
    }

    private var menuBarRankStyleBinding: Binding<MenuBarRankStyle> {
        Binding(
            get: { appModel.settings.menuBarRankStyle },
            set: { appModel.settings.menuBarRankStyle = $0 }
        )
    }

    private var showsMenuBarDetailsBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.showsMenuBarDetails },
            set: { appModel.settings.showsMenuBarDetails = $0 }
        )
    }

    private var refreshIntervalBinding: Binding<RefreshInterval> {
        Binding(
            get: { appModel.settings.refreshInterval },
            set: {
                appModel.settings.refreshInterval = $0
                appModel.settingsDidChange()
            }
        )
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

    private func applyWeights() {
        _ = appModel.settings.apply(weights: weights.weights)
    }
}

private struct WeightInputRow: View {
    let title: String
    let systemImage: String
    @Binding var value: Int

    var body: some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            TextField("", value: $value, format: .number)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 52)
                .accessibilityLabel("\(title)权重")
            Text("%")
                .foregroundStyle(.secondary)
            Stepper("\(title)权重", value: $value, in: 0...100, step: 1)
                .labelsHidden()
        }
    }
}
