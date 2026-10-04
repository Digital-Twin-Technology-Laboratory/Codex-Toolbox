import CodexToolboxCore
import SwiftUI

struct MenuBarSettingsView: View {
    @Bindable var appModel: AppModel
    let onOpenAliases: () -> Void

    var body: some View {
        @Bindable var settings = appModel.settings
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("即时预览").font(.headline)
                HStack(spacing: 16) {
                    ForEach(settings.menuBarConfiguration.items) { item in
                        MenuBarLabel(appModel: appModel, itemID: item.id, isPreview: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 30)
                            .saturation(item.isEnabled ? 1 : 0)
                            .opacity(item.isEnabled ? 1 : 0.35)
                            .accessibilityLabel("\(item.content.resolved(localCostEstimatesEnabled: settings.experimentalLocalCostEstimatesEnabled).displayName)，\(item.isEnabled ? "已开启" : "未开启")")
                    }
                }
                .padding(12)
                .background(Color(white: 0.22), in: RoundedRectangle(cornerRadius: 8))
                .environment(\.colorScheme, .dark)
            }.padding(.horizontal, 24).padding(.vertical, 16)
            Divider()
            Form {
                Section("菜单栏项目") {
                    Text("固定 3 项，可重复选择内容；至少开启一项。按住 Command 拖动菜单栏图标可调整位置。")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(settings.menuBarConfiguration.items.enumerated()), id: \.element.id) { index, item in
                        HStack {
                            Toggle("启用第 \(index + 1) 项", isOn: Binding(
                                get: { settings.menuBarConfiguration.items.first(where: { $0.id == item.id })?.isEnabled ?? false },
                                set: { settings.menuBarConfiguration.update(item.id, isEnabled: $0) }
                            )).labelsHidden()
                                .disabled(item.isEnabled && settings.menuBarConfiguration.enabledItems.count == 1)
                                .help("启用第 \(index + 1) 项")
                            Picker("第 \(index + 1) 项", selection: Binding(
                                get: { settings.menuBarConfiguration.items.first(where: { $0.id == item.id })?.content.resolved(localCostEstimatesEnabled: settings.experimentalLocalCostEstimatesEnabled) ?? .overall },
                                set: { settings.menuBarConfiguration.update(item.id, content: $0) }
                            )) {
                                ForEach(MenuBarContent.availableContents(localCostEstimatesEnabled: settings.experimentalLocalCostEstimatesEnabled)) { Text($0.displayName).tag($0) }
                            }
                        }
                    }
                }
                Section("榜单样式") {
                    Toggle("显示左侧图标", isOn: $settings.showsMenuBarIcon)
                    Toggle("榜单显示附加数值", isOn: $settings.showsMenuBarDetails)
                    Picker("排名序号", selection: $settings.menuBarRankStyle) {
                        ForEach(MenuBarRankStyle.allCases) { Text($0.displayName).tag($0) }
                    }
                    Button("模型名称简称…", action: onOpenAliases)
                }
                Section("Token用量样式") {
                    Toggle("显示左侧图标", isOn: $settings.tokenMenuBarOptions.showsIcon)
                    Picker("数字格式", selection: $settings.tokenMenuBarOptions.numberFormat) {
                        ForEach(MenuBarNumberFormat.allCases) { Text($0.displayName).tag($0) }
                    }
                    Text(settings.experimentalLocalCostEstimatesEnabled ? "应用于今日 Token 和今日 Token 等值成本；仅统计当前 Mac。" : "应用于今日 Token；仅统计当前 Mac。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("额度样式") {
                    Picker("额度指示器", selection: $settings.quotaDisplayOptions.indicator) {
                        ForEach(QuotaIndicatorStyle.allCases) { Text($0.displayName).tag($0) }
                    }
                    Toggle("显示百分比", isOn: $settings.quotaDisplayOptions.percentage)
                    Toggle("显示左侧图标", isOn: $settings.quotaDisplayOptions.showsIcon)
                    Toggle("彩色显示", isOn: $settings.quotaDisplayOptions.usesColor)
                        .disabled(settings.quotaDisplayOptions.indicator == .none)
                    Text("仅影响菜单栏。关闭彩色后，指示器与系统菜单栏图标颜色一致。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.formStyle(.grouped).padding(8)
        }
    }
}
