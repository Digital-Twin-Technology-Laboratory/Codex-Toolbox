import CodexToolboxCore
import SwiftUI

struct DashboardSettingsView: View {
    @Bindable var appModel: AppModel
    @State private var selection: ToolboxModule?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("拖动模块调整顺序；隐藏或折叠状态会立即同步到菜单栏看板。")
                .font(.caption)
                .foregroundStyle(.secondary)

            List(selection: $selection) {
                ForEach(appModel.settings.dashboardModuleOrder) { module in
                    moduleRow(module)
                        .tag(module)
                        .draggable(module.rawValue)
                        .dropDestination(for: String.self) { values, _ in
                            guard let raw = values.first,
                                  let source = ToolboxModule(rawValue: raw),
                                  let destination = appModel.settings.dashboardModuleOrder.firstIndex(of: module) else {
                                return false
                            }
                            appModel.settings.moveDashboardModule(source, to: destination)
                            selection = source
                            return true
                        }
                }
            }
            .listStyle(.inset)

            HStack {
                Button("上移", systemImage: "arrow.up") {
                    if let selection { appModel.settings.moveDashboardModuleUp(selection) }
                }
                .disabled(selection == nil || selection == appModel.settings.dashboardModuleOrder.first)
                .keyboardShortcut(.upArrow, modifiers: [.command, .option])

                Button("下移", systemImage: "arrow.down") {
                    if let selection { appModel.settings.moveDashboardModuleDown(selection) }
                }
                .disabled(selection == nil || selection == appModel.settings.dashboardModuleOrder.last)
                .keyboardShortcut(.downArrow, modifiers: [.command, .option])

                Spacer()

                Button("恢复默认布局") {
                    appModel.settings.resetDashboardConfiguration()
                    selection = nil
                }
            }
        }
        .padding(18)
    }

    private func moduleRow(_ module: ToolboxModule) -> some View {
        HStack(spacing: 10) {
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
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
}
