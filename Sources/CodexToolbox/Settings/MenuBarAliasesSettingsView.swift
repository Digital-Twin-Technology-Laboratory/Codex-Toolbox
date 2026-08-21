import CodexToolboxCore
import SwiftUI

struct MenuBarAliasesSettingsView: View {
    @Bindable var appModel: AppModel
    let onBack: () -> Void

    @State private var scope: AliasScope = .visible
    @State private var searchText = ""
    @State private var drafts: [String: String] = [:]
    @FocusState private var focusedFamilyID: String?

    var body: some View {
        VStack(spacing: 0) {
            settingsSubpageHeader(title: "模型名称简称", onBack: commitAndBack)
            Divider()

            if appModel.availableModels.isEmpty {
                ContentUnavailableView {
                    Label("暂无模型数据", systemImage: "textformat")
                } description: {
                    Text("获取模型数据后，可在这里设置所有紧凑布局共用的简称。")
                }
            } else {
                Form {
                    Section {
                        Picker("显示范围", selection: $scope) {
                            ForEach(AliasScope.allCases) { scope in
                                Text(scope.title).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("每个基础模型只需设置一次，系统会自动追加 low、high 等推理档位。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(filteredProviders) { provider in
                        Section(provider.title) {
                            ForEach(provider.families) { family in
                                aliasRow(family)
                            }
                        }
                    }

                    if filteredProviders.isEmpty {
                        Section {
                            ContentUnavailableView.search(text: searchText)
                        }
                    }

                    Section {
                        Text("简称用于菜单栏、四卡常规与折叠状态、趋势和推荐；展开详情仍显示官方全名。最多 16 个字符，保存时只移除首尾空白，内部空格会保留。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .formStyle(.grouped)
                .searchable(text: $searchText, placement: .toolbar, prompt: "搜索模型")
                .padding(8)
            }
        }
        .onAppear(perform: loadDrafts)
        .onChange(of: focusedFamilyID) { oldValue, _ in
            if let oldValue { commit(oldValue) }
        }
        .onDisappear(perform: commitAll)
    }

    private var filteredProviders: [FilteredProvider] {
        ModelCatalog.groupedByProvider(appModel.availableModels).compactMap { provider in
            let families = provider.families.filter { family in
                let inScope = scope == .all
                    || family.models.contains(where: appModel.settings.isModelVisible)
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                return inScope && (query.isEmpty
                    || family.title.localizedCaseInsensitiveContains(query)
                    || family.compactTitle.localizedCaseInsensitiveContains(query))
            }
            guard !families.isEmpty else { return nil }
            return FilteredProvider(id: provider.id, title: provider.title, families: families)
        }
    }

    private func aliasRow(_ family: ModelCatalogFamilyGroup) -> some View {
        let draft = drafts[family.id] ?? ""
        let isTooLong = draft.trimmingCharacters(in: .whitespacesAndNewlines).count > 16
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(family.title)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(preview(for: family, draft: draft))
                    .font(.caption)
                    .foregroundStyle(isTooLong ? .red : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField(
                text: Binding(
                    get: { drafts[family.id] ?? "" },
                    set: { drafts[family.id] = $0 }
                ),
                prompt: Text("未设置")
            ) {
                Text("简称")
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.leading)
            .frame(width: 170, alignment: .leading)
            .focused($focusedFamilyID, equals: family.id)
            .onSubmit { commit(family.id) }
            .accessibilityLabel("\(family.title)简称")

            Button {
                drafts[family.id] = ""
                commit(family.id)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tertiary)
            .disabled(draft.isEmpty)
            .help("清除简称")
        }
        .padding(.vertical, 2)
    }

    private func preview(for family: ModelCatalogFamilyGroup, draft: String) -> String {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 16 { return "已输入 \(trimmed.count) / 16 个字符，暂未保存" }
        let base = trimmed.isEmpty ? family.compactTitle : trimmed
        let effort = family.models.first?.reasoningEffort ?? "low"
        return "预览：\(base) \(ModelCatalog.compactEffortLabel(effort))"
    }

    private func loadDrafts() {
        for family in ModelCatalog.grouped(appModel.availableModels) {
            drafts[family.id] = appModel.settings.modelFamilyAlias(for: family.id)
        }
    }

    private func commit(_ familyID: String) {
        guard appModel.settings.setModelFamilyAlias(
            drafts[familyID] ?? "",
            for: familyID
        ) else { return }
        drafts[familyID] = appModel.settings.modelFamilyAlias(for: familyID)
    }

    private func commitAll() {
        for familyID in drafts.keys { commit(familyID) }
    }

    private func commitAndBack() {
        focusedFamilyID = nil
        commitAll()
        onBack()
    }
}

private enum AliasScope: String, CaseIterable, Identifiable {
    case visible
    case all

    var id: String { rawValue }
    var title: String { self == .visible ? "已显示模型" : "全部模型" }
}

private struct FilteredProvider: Identifiable {
    let id: String
    let title: String
    let families: [ModelCatalogFamilyGroup]
}
