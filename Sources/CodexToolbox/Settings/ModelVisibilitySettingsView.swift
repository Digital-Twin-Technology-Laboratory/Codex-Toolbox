import CodexToolboxCore
import SwiftUI

struct ModelVisibilitySettingsView: View {
    @Bindable var appModel: AppModel
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            settingsSubpageHeader(title: "显示的模型", onBack: onBack)
            Divider()

            if providerGroups.isEmpty {
                ContentUnavailableView {
                    Label("暂无模型数据", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("刷新 Codex Radar 数据后，可按厂商或基础模型控制显示范围。")
                }
            } else {
                Form {
                    Section {
                        LabeledContent("当前显示") {
                            Text("\(visibleFamilyCount) / \(familyCount) 个基础模型")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        HStack {
                            Button("恢复仅 GPT") {
                                appModel.settings.resetModelVisibilityToGPTOnly()
                            }
                            Button("显示全部") {
                                appModel.settings.showAllModels()
                            }
                        }
                        Text("筛选同时作用于榜单、菜单栏、趋势和站长推荐；不会删除原始 Radar 缓存或已保存的趋势选择。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(providerGroups) { provider in
                        Section {
                            Button {
                                setProvider(provider, isVisible: providerState(provider) != .all)
                            } label: {
                                HStack {
                                    Image(systemName: providerState(provider).systemImage)
                                        .foregroundStyle(.tint)
                                        .frame(width: 18)
                                    Text(provider.title)
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text(providerState(provider).title)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(provider.title)，\(providerState(provider).title)")

                            DisclosureGroup("具体模型") {
                                ForEach(provider.families) { family in
                                    Toggle(
                                        family.title,
                                        isOn: Binding(
                                            get: { familyIsVisible(family) },
                                            set: { appModel.settings.setModelFamily(family.id, isVisible: $0) }
                                        )
                                    )
                                    .help("控制 \(family.title) 的所有推理档位")
                                }
                            }
                        }
                    }

                    if visibleFamilyCount == 0 {
                        Section {
                            Label("当前筛选下不会显示任何模型，可随时恢复仅 GPT。", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                        }
                    }
                }
                .formStyle(.grouped)
                .padding(8)
            }
        }
    }

    private var providerGroups: [ModelCatalogProviderGroup] {
        ModelCatalog.groupedByProvider(appModel.availableModels)
    }

    private var familyCount: Int {
        providerGroups.reduce(0) { $0 + $1.families.count }
    }

    private var visibleFamilyCount: Int {
        providerGroups.flatMap(\.families).filter(familyIsVisible).count
    }

    private func familyIsVisible(_ family: ModelCatalogFamilyGroup) -> Bool {
        guard let benchmark = family.models.first else { return false }
        return appModel.settings.isModelVisible(benchmark)
    }

    private func providerState(_ provider: ModelCatalogProviderGroup) -> ProviderVisibilityState {
        let count = provider.families.filter(familyIsVisible).count
        if count == 0 { return .none }
        if count == provider.families.count { return .all }
        return .some
    }

    private func setProvider(_ provider: ModelCatalogProviderGroup, isVisible: Bool) {
        appModel.settings.setModelProvider(
            provider.id,
            isVisible: isVisible,
            knownFamilyIDs: provider.families.map(\.id)
        )
    }
}

private enum ProviderVisibilityState {
    case none
    case some
    case all

    var title: String {
        switch self {
        case .none: "隐藏"
        case .some: "部分显示"
        case .all: "全部显示"
        }
    }

    var systemImage: String {
        switch self {
        case .none: "square"
        case .some: "minus.square.fill"
        case .all: "checkmark.square.fill"
        }
    }
}

@ViewBuilder
func settingsSubpageHeader(title: String, onBack: @escaping () -> Void) -> some View {
    ZStack {
        Text(title)
            .font(.headline)
        HStack {
            Button(action: onBack) {
                Label("返回", systemImage: "chevron.left")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(.cancelAction)
            Spacer()
        }
    }
    .padding(.horizontal, 14)
    .frame(height: 44)
}
