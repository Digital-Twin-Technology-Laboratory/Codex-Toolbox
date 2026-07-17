import CodexToolboxCore
import SwiftUI

struct MenuBarAliasesSettingsView: View {
    @Bindable var appModel: AppModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .padding(8)
        }
    }

    @ViewBuilder
    private var content: some View {
        Group {
            if appModel.availableModels.isEmpty {
                ContentUnavailableView {
                    Label("暂无模型数据", systemImage: "textformat")
                } description: {
                    Text("获取模型数据后，可在这里为每个模型设置仅用于菜单栏的简称。")
                }
            } else {
                Form {
                    Section {
                        ForEach(appModel.availableModels) { model in
                            aliasRow(for: model)
                        }
                    } header: {
                        Text("模型简称")
                    } footer: {
                        Text("简称仅在菜单栏中生效；留空时使用自动精简名称，展开面板仍显示原名称。")
                    }
                }
                .formStyle(.grouped)
            }
        }
    }

    private var header: some View {
        ZStack {
            Text("模型名称简称")
                .font(.headline)

            HStack {
                Button(action: onBack) {
                    Label("返回", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("返回设置首页")

                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }

    private func aliasRow(for model: ModelBenchmark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.label)
                .font(.body.weight(.medium))

            HStack(spacing: 10) {
                Text("简称")
                    .foregroundStyle(.secondary)
                TextField(
                    "留空时显示 \(MetricFormatter.compactModelName(model.label))",
                    text: aliasBinding(for: model.id)
                )
                .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.vertical, 3)
    }

    private func aliasBinding(for modelID: String) -> Binding<String> {
        Binding(
            get: { appModel.settings.menuBarModelAlias(for: modelID) },
            set: { appModel.settings.setMenuBarModelAlias($0, for: modelID) }
        )
    }
}
