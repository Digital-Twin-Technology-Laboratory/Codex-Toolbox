import Foundation

/// A single, source-driven catalog for presenting models throughout the app.
///
/// Stable model identifiers remain the responsibility of the decoder. The catalog
/// only derives grouping, ordering, and display metadata from the source model and
/// reasoning-effort fields, so saved aliases never depend on presentation text.
public struct ModelCatalogEntry: Hashable, Sendable {
    public let familyID: String
    public let familyTitle: String
    public let displayLabel: String
    public let compactLabel: String
    public let rowTitle: String

    fileprivate let familySortOrder: Int
    fileprivate let variantSortOrder: Int
    fileprivate let effortSortOrder: Int
    fileprivate let modelSortKey: String

    fileprivate init(
        familyID: String,
        familyTitle: String,
        displayLabel: String,
        compactLabel: String,
        rowTitle: String,
        familySortOrder: Int,
        variantSortOrder: Int,
        effortSortOrder: Int,
        modelSortKey: String
    ) {
        self.familyID = familyID
        self.familyTitle = familyTitle
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
    public let models: [ModelBenchmark]

    fileprivate let sortOrder: Int

    fileprivate init(id: String, title: String, models: [ModelBenchmark], sortOrder: Int) {
        self.id = id
        self.title = title
        self.models = models
        self.sortOrder = sortOrder
    }
}

public enum ModelCatalog {
    /// Returns the presentation metadata for a model supplied by Codex Radar.
    public static func entry(model: String, reasoningEffort: String) -> ModelCatalogEntry {
        let sourceModel = trimmed(model, fallback: "未知模型")
        let normalizedModel = sourceModel.lowercased()
        let effort = trimmed(reasoningEffort, fallback: "unknown").lowercased()
        let effortOrder = effortSortOrder(for: effort)

        if let openAI = openAIModel(for: normalizedModel) {
            return ModelCatalogEntry(
                familyID: openAI.id,
                familyTitle: openAI.title,
                displayLabel: "\(openAI.title) \(effort)",
                compactLabel: "\(openAI.compactTitle) \(compactEffort(effort))",
                rowTitle: effort,
                familySortOrder: openAI.sortOrder,
                variantSortOrder: 0,
                effortSortOrder: effortOrder,
                modelSortKey: normalizedModel
            )
        }

        if let deepSeek = deepSeekModel(for: normalizedModel) {
            let versionLabel = deepSeek.isPreview ? "Preview" : "正式版"
            let displayVariant = deepSeek.isPreview ? " Preview" : ""
            let compactVariant = deepSeek.isPreview ? " P" : ""
            return ModelCatalogEntry(
                familyID: deepSeek.id,
                familyTitle: deepSeek.title,
                displayLabel: "\(deepSeek.title)\(displayVariant) \(effort)",
                compactLabel: "\(deepSeek.compactTitle)\(compactVariant) \(compactEffort(effort))",
                rowTitle: "\(versionLabel) · \(effort)",
                familySortOrder: deepSeek.sortOrder,
                variantSortOrder: deepSeek.isPreview ? 1 : 0,
                effortSortOrder: effortOrder,
                modelSortKey: normalizedModel
            )
        }

        return ModelCatalogEntry(
            familyID: "other-models",
            familyTitle: "其他模型",
            displayLabel: "\(sourceModel) \(effort)",
            compactLabel: MetricFormatter.compactModelName("\(sourceModel) \(effort)"),
            rowTitle: effort,
            familySortOrder: 100,
            variantSortOrder: 0,
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
            if left.familyID == "other-models", right.familyID == "other-models",
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

    private static func openAIModel(
        for model: String
    ) -> (id: String, title: String, compactTitle: String, sortOrder: Int)? {
        switch model {
        case "gpt-5.5": ("openai-gpt-5.5", "5.5", "5.5", 0)
        case "gpt-5.6-sol": ("openai-gpt-5.6-sol", "GPT-5.6 Sol", "Sol", 1)
        case "gpt-5.6-terra": ("openai-gpt-5.6-terra", "GPT-5.6 Terra", "Terra", 2)
        case "gpt-5.6-luna": ("openai-gpt-5.6-luna", "GPT-5.6 Luna", "Luna", 3)
        default: nil
        }
    }

    private static func deepSeekModel(
        for model: String
    ) -> (id: String, title: String, compactTitle: String, sortOrder: Int, isPreview: Bool)? {
        switch model {
        case "deepseek-v4-flash":
            ("deepseek-v4-flash", "DeepSeek V4 Flash", "V4 Flash", 4, false)
        case "deepseek-v4-flash-preview":
            ("deepseek-v4-flash", "DeepSeek V4 Flash", "V4 Flash", 4, true)
        case "deepseek-v4-pro":
            ("deepseek-v4-pro", "DeepSeek V4 Pro", "V4 Pro", 5, false)
        case "deepseek-v4-pro-preview":
            ("deepseek-v4-pro", "DeepSeek V4 Pro", "V4 Pro", 5, true)
        default:
            nil
        }
    }
}

public extension ModelBenchmark {
    var catalogEntry: ModelCatalogEntry {
        ModelCatalog.entry(model: model, reasoningEffort: reasoningEffort)
    }
}
