import Foundation

/// A single, source-driven catalog for presenting models throughout the app.
///
/// Stable model identifiers remain the responsibility of the decoder. The catalog
/// only derives grouping, ordering, and display metadata from the source model and
/// reasoning-effort fields, so saved aliases never depend on presentation text.
public struct ModelCatalogEntry: Hashable, Sendable {
    public let providerID: String
    public let providerTitle: String
    public let familyID: String
    public let familyTitle: String
    public let compactFamilyTitle: String
    public let sourceModel: String
    public let reasoningEffort: String
    public let displayLabel: String
    public let compactLabel: String
    public let rowTitle: String

    fileprivate let familySortOrder: Int
    fileprivate let variantSortOrder: Int
    fileprivate let effortSortOrder: Int
    fileprivate let modelSortKey: String

    fileprivate init(
        providerID: String,
        providerTitle: String,
        familyID: String,
        familyTitle: String,
        compactFamilyTitle: String,
        sourceModel: String,
        reasoningEffort: String,
        displayLabel: String,
        compactLabel: String,
        rowTitle: String,
        familySortOrder: Int,
        variantSortOrder: Int,
        effortSortOrder: Int,
        modelSortKey: String
    ) {
        self.providerID = providerID
        self.providerTitle = providerTitle
        self.familyID = familyID
        self.familyTitle = familyTitle
        self.compactFamilyTitle = compactFamilyTitle
        self.sourceModel = sourceModel
        self.reasoningEffort = reasoningEffort
        self.displayLabel = displayLabel
        self.compactLabel = compactLabel
        self.rowTitle = rowTitle
        self.familySortOrder = familySortOrder
        self.variantSortOrder = variantSortOrder
        self.effortSortOrder = effortSortOrder
        self.modelSortKey = modelSortKey
    }
}

public struct ModelCatalogFamilyGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let compactTitle: String
    public let providerID: String
    public let providerTitle: String
    public let models: [ModelBenchmark]

    fileprivate let sortOrder: Int

    fileprivate init(
        id: String,
        title: String,
        compactTitle: String,
        providerID: String,
        providerTitle: String,
        models: [ModelBenchmark],
        sortOrder: Int
    ) {
        self.id = id
        self.title = title
        self.compactTitle = compactTitle
        self.providerID = providerID
        self.providerTitle = providerTitle
        self.models = models
        self.sortOrder = sortOrder
    }
}

public struct ModelCatalogProviderGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let families: [ModelCatalogFamilyGroup]

    fileprivate let sortOrder: Int
}

public enum ModelCatalog {
    /// Returns the presentation metadata for a model supplied by Codex Radar.
    public static func entry(model: String, reasoningEffort: String) -> ModelCatalogEntry {
        let sourceModel = trimmed(model, fallback: "未知模型")
        let normalizedModel = sourceModel.lowercased()
        let effort = trimmed(reasoningEffort, fallback: "unknown").lowercased()
        let effortOrder = effortSortOrder(for: effort)

        let descriptor = descriptor(for: normalizedModel, sourceModel: sourceModel)
        let displayVariant = descriptor.isPreview ? " Preview" : ""
        let compactVariant = descriptor.isPreview ? " P" : ""
        let rowTitle: String
        if descriptor.provider.id == "deepseek" {
            rowTitle = "\(descriptor.isPreview ? "Preview" : "正式版") · \(effort)"
        } else {
            rowTitle = descriptor.isPreview ? "Preview · \(effort)" : effort
        }
        return ModelCatalogEntry(
            providerID: descriptor.provider.id,
            providerTitle: descriptor.provider.title,
            familyID: descriptor.familyID,
            familyTitle: descriptor.title,
            compactFamilyTitle: descriptor.compactTitle,
            sourceModel: normalizedModel,
            reasoningEffort: effort,
            displayLabel: "\(descriptor.title)\(displayVariant) \(effort)",
            compactLabel: "\(descriptor.compactTitle)\(compactVariant) \(compactEffort(effort))",
            rowTitle: rowTitle,
            familySortOrder: descriptor.provider.sortOrder * 100 + descriptor.sortOrder,
            variantSortOrder: descriptor.isPreview ? 1 : 0,
            effortSortOrder: effortOrder,
            modelSortKey: normalizedModel
        )
    }

    public static func sorted(_ benchmarks: [ModelBenchmark]) -> [ModelBenchmark] {
        benchmarks.sorted { lhs, rhs in
            let left = lhs.catalogEntry
            let right = rhs.catalogEntry

            if left.familySortOrder != right.familySortOrder {
                return left.familySortOrder < right.familySortOrder
            }
            if left.providerID == "other", right.providerID == "other",
               left.modelSortKey != right.modelSortKey {
                return left.modelSortKey.localizedStandardCompare(right.modelSortKey) == .orderedAscending
            }
            if left.variantSortOrder != right.variantSortOrder {
                return left.variantSortOrder < right.variantSortOrder
            }
            if left.effortSortOrder != right.effortSortOrder {
                return left.effortSortOrder < right.effortSortOrder
            }
            if left.modelSortKey != right.modelSortKey {
                return left.modelSortKey.localizedStandardCompare(right.modelSortKey) == .orderedAscending
            }
            return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
        }
    }

    public static func grouped(_ benchmarks: [ModelBenchmark]) -> [ModelCatalogFamilyGroup] {
        let ordered = sorted(benchmarks)
        let groups = Dictionary(grouping: ordered, by: \.catalogEntry.familyID)

        return groups.compactMap { id, models in
            guard let first = models.first else { return nil }
            let entry = first.catalogEntry
            return ModelCatalogFamilyGroup(
                id: id,
                title: entry.familyTitle,
                compactTitle: entry.compactFamilyTitle,
                providerID: entry.providerID,
                providerTitle: entry.providerTitle,
                models: models,
                sortOrder: entry.familySortOrder
            )
        }
        .sorted { lhs, rhs in
            if lhs.sortOrder != rhs.sortOrder {
                return lhs.sortOrder < rhs.sortOrder
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    public static func groupedByProvider(
        _ benchmarks: [ModelBenchmark]
    ) -> [ModelCatalogProviderGroup] {
        let families = grouped(benchmarks)
        return Dictionary(grouping: families, by: \.providerID)
            .compactMap { providerID, families in
                guard let first = families.first else { return nil }
                let provider = providerDescriptor(for: providerID)
                return ModelCatalogProviderGroup(
                    id: providerID,
                    title: first.providerTitle,
                    families: families,
                    sortOrder: provider.sortOrder
                )
            }
            .sorted { lhs, rhs in
                if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    public static func isDefaultGPT(_ entry: ModelCatalogEntry) -> Bool {
        entry.providerID == "openai" && entry.sourceModel.hasPrefix("gpt-")
    }

    public static func compactEffortLabel(_ effort: String) -> String {
        compactEffort(trimmed(effort, fallback: "unknown").lowercased())
    }

    private static func trimmed(_ value: String, fallback: String) -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }

    private static func effortSortOrder(for effort: String) -> Int {
        switch effort {
        case "low": 0
        case "medium": 1
        case "high": 2
        case "xhigh": 3
        case "max": 4
        case "ultra": 5
        default: 100
        }
    }

    private static func compactEffort(_ effort: String) -> String {
        effort == "medium" ? "med" : effort
    }

    private struct ProviderDescriptor {
        let id: String
        let title: String
        let sortOrder: Int
    }

    private struct FamilyDescriptor {
        let provider: ProviderDescriptor
        let familyID: String
        let title: String
        let compactTitle: String
        let sortOrder: Int
        let isPreview: Bool
    }

    private static func providerDescriptor(for id: String) -> ProviderDescriptor {
        switch id {
        case "openai": ProviderDescriptor(id: id, title: "OpenAI", sortOrder: 0)
        case "xai": ProviderDescriptor(id: id, title: "xAI", sortOrder: 1)
        case "moonshot": ProviderDescriptor(id: id, title: "Moonshot AI · Kimi", sortOrder: 2)
        case "deepseek": ProviderDescriptor(id: id, title: "DeepSeek", sortOrder: 3)
        case "dsh": ProviderDescriptor(id: id, title: "DSH", sortOrder: 4)
        case "zai": ProviderDescriptor(id: id, title: "Z.ai · GLM", sortOrder: 5)
        default: ProviderDescriptor(id: "other", title: "其他", sortOrder: 99)
        }
    }

    private static func descriptor(for model: String, sourceModel: String) -> FamilyDescriptor {
        if let openAI = openAIModel(for: model) { return openAI }
        if model.hasPrefix("gpt-") {
            return family(
                provider: "openai",
                id: "openai-\(slug(model))",
                title: sourceModel.uppercasedPrefix("gpt", replacement: "GPT"),
                compactTitle: MetricFormatter.compactModelName(sourceModel),
                order: 20
            )
        }
        if model.hasPrefix("grok-") {
            let title = sourceModel.uppercasedPrefix("grok", replacement: "Grok")
            return family(provider: "xai", id: "xai-\(slug(model))", title: title, compactTitle: title, order: 0)
        }
        if model == "k3" || model.hasPrefix("kimi-") {
            let suffix = model == "k3" ? "K3" : sourceModel.uppercasedPrefix("kimi", replacement: "Kimi")
            return family(provider: "moonshot", id: "moonshot-\(slug(model))", title: "Kimi \(suffix == "K3" ? "K3" : suffix.replacingOccurrences(of: "Kimi ", with: ""))", compactTitle: suffix, order: 0)
        }
        if model.hasPrefix("dsh-") {
            let title = humanizedModel(model.replacingOccurrences(of: "dsh-", with: ""), brand: "DeepSeek")
            return family(provider: "dsh", id: "dsh-\(slug(model))", title: "DSH \(title)", compactTitle: "DSH \(compactDeepSeek(model))", order: 0)
        }
        if let deepSeek = deepSeekModel(for: model) { return deepSeek }
        if model.hasPrefix("glm-") {
            let title = sourceModel.uppercasedPrefix("glm", replacement: "GLM")
            return family(provider: "zai", id: "zai-\(slug(model))", title: title, compactTitle: title, order: 0)
        }
        return family(
            provider: "other",
            id: "other-\(slug(model))",
            title: sourceModel,
            compactTitle: MetricFormatter.compactModelName(sourceModel),
            order: 0
        )
    }

    private static func family(
        provider providerID: String,
        id: String,
        title: String,
        compactTitle: String,
        order: Int,
        isPreview: Bool = false
    ) -> FamilyDescriptor {
        FamilyDescriptor(
            provider: providerDescriptor(for: providerID),
            familyID: id,
            title: title,
            compactTitle: compactTitle,
            sortOrder: order,
            isPreview: isPreview
        )
    }

    private static func openAIModel(for model: String) -> FamilyDescriptor? {
        switch model {
        case "gpt-5.5": family(provider: "openai", id: "openai-gpt-5.5", title: "5.5", compactTitle: "5.5", order: 0)
        case "gpt-5.6-sol": family(provider: "openai", id: "openai-gpt-5.6-sol", title: "GPT-5.6 Sol", compactTitle: "Sol", order: 1)
        case "gpt-5.6-terra": family(provider: "openai", id: "openai-gpt-5.6-terra", title: "GPT-5.6 Terra", compactTitle: "Terra", order: 2)
        case "gpt-5.6-luna": family(provider: "openai", id: "openai-gpt-5.6-luna", title: "GPT-5.6 Luna", compactTitle: "Luna", order: 3)
        default: nil
        }
    }

    private static func deepSeekModel(for model: String) -> FamilyDescriptor? {
        switch model {
        case "deepseek-v4-flash":
            family(provider: "deepseek", id: "deepseek-v4-flash", title: "DeepSeek V4 Flash", compactTitle: "V4 Flash", order: 0)
        case "deepseek-v4-flash-preview":
            family(provider: "deepseek", id: "deepseek-v4-flash", title: "DeepSeek V4 Flash", compactTitle: "V4 Flash", order: 0, isPreview: true)
        case "deepseek-v4-pro":
            family(provider: "deepseek", id: "deepseek-v4-pro", title: "DeepSeek V4 Pro", compactTitle: "V4 Pro", order: 1)
        case "deepseek-v4-pro-preview":
            family(provider: "deepseek", id: "deepseek-v4-pro", title: "DeepSeek V4 Pro", compactTitle: "V4 Pro", order: 1, isPreview: true)
        default:
            nil
        }
    }

    private static func slug(_ value: String) -> String {
        value.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || result.last != "-" { result.append(character) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func humanizedModel(_ model: String, brand: String) -> String {
        model.split(separator: "-").map { part in
            let value = String(part)
            if value.lowercased() == brand.lowercased() { return brand }
            if value.hasPrefix("v"), value.dropFirst().first?.isNumber == true { return value.uppercased() }
            return value.capitalized
        }.joined(separator: " ")
    }

    private static func compactDeepSeek(_ model: String) -> String {
        let stripped = model
            .replacingOccurrences(of: "dsh-", with: "")
            .replacingOccurrences(of: "deepseek-", with: "")
        return humanizedModel(stripped, brand: "DeepSeek")
    }
}

private extension String {
    func uppercasedPrefix(_ prefix: String, replacement: String) -> String {
        guard lowercased().hasPrefix(prefix.lowercased()) else { return self }
        return replacement + dropFirst(prefix.count)
    }
}

public extension ModelBenchmark {
    var catalogEntry: ModelCatalogEntry {
        ModelCatalog.entry(model: model, reasoningEffort: reasoningEffort)
    }
}
