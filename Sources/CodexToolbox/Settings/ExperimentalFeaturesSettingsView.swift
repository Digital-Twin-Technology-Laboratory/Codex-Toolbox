import SwiftUI

struct ExperimentalFeaturesSettingsView: View {
    @Bindable var appModel: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: dashboardThemesEnabledBinding) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("多种主题")
                        Text("启用后，可在“通用与看板”中选择看板主题。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            } header: {
                Label("实验性功能", systemImage: "flask")
            } footer: {
                Text("实验性功能默认关闭，可能在后续版本中调整或移除。")
            }
            Section {
                Toggle("本机成本换算", isOn: Binding(
                    get: { appModel.settings.experimentalLocalCostEstimatesEnabled },
                    set: {
                        appModel.settings.experimentalLocalCostEstimatesEnabled = $0
                        appModel.settingsDidChange()
                    }
                ))
                Text("启用 API 等值成本、本机 Credits 换算及相关设置。缺少模型价格时无法换算；金额并非订阅账单。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if appModel.settings.experimentalLocalCostEstimatesEnabled {
                CostEstimationSettingsSections(appModel: appModel)
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var dashboardThemesEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.experimentalDashboardThemesEnabled },
            set: { appModel.settings.experimentalDashboardThemesEnabled = $0 }
        )
    }
}
