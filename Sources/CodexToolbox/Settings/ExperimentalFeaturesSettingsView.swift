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
