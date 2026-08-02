import Foundation

public struct RadarResponse: Decodable, Sendable {
    public let schemaVersion: String
    public let monitoredAt: String?
    public let modelIQ: ModelIQPayload

    public var benchmarks: [ModelBenchmark] {
        modelIQ.comparisons
            .map { id, comparison in comparison.benchmark(id: id) }
            .sorted { $0.id < $1.id }
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case monitoredAt = "monitored_at"
        case modelIQ = "model_iq"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(String.self, forKey: .schemaVersion) ?? "unknown"
        monitoredAt = try container.decodeIfPresent(String.self, forKey: .monitoredAt)
        modelIQ = try container.decodeIfPresent(ModelIQPayload.self, forKey: .modelIQ) ?? ModelIQPayload()
    }
}

public struct ModelIQPayload: Decodable, Sendable {
    public let comparisons: [String: ModelComparison]

    private enum CodingKeys: String, CodingKey {
        case comparisons
    }

    public init(comparisons: [String: ModelComparison] = [:]) {
        self.comparisons = comparisons
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        comparisons = try container.decodeIfPresent([String: ModelComparison].self, forKey: .comparisons) ?? [:]
    }
}

public struct ModelComparison: Decodable, Sendable {
    public let label: String?
    public let model: String?
    public let reasoningEffort: String?
    public let latest: BenchmarkRecord?
    public let recentDays: [BenchmarkRecord]

    private enum CodingKeys: String, CodingKey {
        case label
        case model
        case reasoningEffort = "reasoning_effort"
        case latest
        case recentDays = "recent_days"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        label = try container.decodeIfPresent(String.self, forKey: .label)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        reasoningEffort = try container.decodeIfPresent(String.self, forKey: .reasoningEffort)
        latest = try container.decodeIfPresent(BenchmarkRecord.self, forKey: .latest)
        recentDays = try container.decodeIfPresent([BenchmarkRecord].self, forKey: .recentDays) ?? []
    }

    fileprivate func benchmark(id: String) -> ModelBenchmark {
        ModelBenchmark(
            id: id,
            label: label ?? id,
            model: model ?? id,
            reasoningEffort: reasoningEffort ?? "unknown",
            latest: latest,
            recentDays: recentDays
        )
    }
}

struct IntelligenceEfficiencyResponse: Decodable, Sendable {
    let schema: Int
    let sourceUpdatedAt: String?
    let points: [IntelligenceEfficiencyPoint]
    let history: [IntelligenceEfficiencyHistorySnapshot]

    private enum CodingKeys: String, CodingKey {
        case schema
        case sourceUpdatedAt = "source_updated_at"
        case points
        case history
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(Int.self, forKey: .schema)
        sourceUpdatedAt = try container.decodeIfPresent(String.self, forKey: .sourceUpdatedAt)
        points = try container.decodeIfPresent(
            LossyDecodableArray<IntelligenceEfficiencyPoint>.self,
            forKey: .points
        )?.elements ?? []
        history = try container.decodeIfPresent(
            LossyDecodableArray<IntelligenceEfficiencyHistorySnapshot>.self,
            forKey: .history
        )?.elements ?? []
    }

    var benchmarks: [ModelBenchmark] {
        var historyByID: [String: [BenchmarkRecord]] = [:]
        for snapshot in history {
            guard let date = snapshot.normalizedDate else { continue }
            for point in snapshot.points {
                guard
                    let identity = point.identity,
                    let record = point.benchmarkRecord(date: date)
                else { continue }
                historyByID[identity.id, default: []].append(record)
            }
        }

        guard let currentDate = normalizedSourceUpdatedAt else { return [] }
        var benchmarksByID: [String: ModelBenchmark] = [:]
        for point in points {
            guard
                let identity = point.identity,
                let latest = point.benchmarkRecord(date: currentDate)
            else { continue }
            benchmarksByID[identity.id] = ModelBenchmark(
                id: identity.id,
                label: identity.label,
                model: identity.model,
                reasoningEffort: identity.effort,
                latest: latest,
                recentDays: (historyByID[identity.id] ?? []).sorted {
                    $0.date < $1.date
                }
            )
        }
        return benchmarksByID.values.sorted { $0.id < $1.id }
    }

    var normalizedSourceUpdatedAt: String? {
        let value = sourceUpdatedAt?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

struct IntelligenceEfficiencyHistorySnapshot: Decodable, Sendable {
    let at: String?
    let points: [IntelligenceEfficiencyPoint]

    private enum CodingKeys: String, CodingKey {
        case at
        case points
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        at = try container.decodeIfPresent(String.self, forKey: .at)
        points = try container.decodeIfPresent(
            LossyDecodableArray<IntelligenceEfficiencyPoint>.self,
            forKey: .points
        )?.elements ?? []
    }

    var normalizedDate: String? {
        let value = at?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? nil : value
    }
}

struct IntelligenceEfficiencyPoint: Decodable, Sendable {
    let model: String?
    let effort: String?
    let iq: Double?
    let passed: Int?
    let validTasks: Int?
    let averagePriceUSD: Double?
    let averageMinutes: Double?

    private enum CodingKeys: String, CodingKey {
        case model
        case effort
        case iq
        case passed
        case validTasks = "valid_tasks"
        case averagePriceUSD = "average_price_usd"
        case averageMinutes = "average_minutes"
    }

    var identity: IntelligenceEfficiencyModelIdentity? {
        IntelligenceEfficiencyModelIdentity(model: model, effort: effort)
    }

    func benchmarkRecord(date: String) -> BenchmarkRecord? {
        let score = iq.flatMap(Self.finite)
        let cost: Double? = averagePriceUSD.flatMap { value -> Double? in
            guard let value = Self.finite(value), value >= 0 else { return nil }
            return value
        }
        let wallSeconds: Double? = averageMinutes.flatMap { value -> Double? in
            guard let value = Self.finite(value), value > 0 else { return nil }
            return value * 60
        }
        guard score != nil || cost != nil || wallSeconds != nil else { return nil }

        return BenchmarkRecord(
            date: date,
            score: score,
            status: nil,
            passed: passed.flatMap { $0 >= 0 ? $0 : nil },
            tasks: validTasks.flatMap { $0 >= 0 ? $0 : nil },
            wallSeconds: wallSeconds,
            costUSD: cost
        )
    }

    private static func finite(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }
}

struct IntelligenceEfficiencyModelIdentity: Hashable, Sendable {
    let model: String
    let effort: String
    let id: String
    let label: String

    init?(model: String?, effort: String?) {
        let normalizedModel = model?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let normalizedEffort = effort?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        guard !normalizedModel.isEmpty, !normalizedEffort.isEmpty else { return nil }

        self.model = normalizedModel
        self.effort = normalizedEffort
        let key = "\(normalizedModel)|\(normalizedEffort)"
        if let legacyID = Self.legacyIDs[key] {
            id = legacyID
        } else if let prefix = Self.compatibleIDPrefixes[normalizedModel] {
            id = "\(prefix)_\(Self.sanitizedIDComponent(normalizedEffort))"
        } else {
            id = "\(Self.sanitizedIDComponent(normalizedModel))_\(Self.sanitizedIDComponent(normalizedEffort))"
        }
        let prefix = Self.labelPrefixes[normalizedModel] ?? normalizedModel
        label = "\(prefix) \(normalizedEffort)"
    }

    private static let labelPrefixes: [String: String] = [
        "gpt-5.6-sol": "GPT-5.6 Sol",
        "gpt-5.6-terra": "GPT-5.6 Terra",
        "gpt-5.6-luna": "GPT-5.6 Luna",
        "gpt-5.5": "5.5",
        "deepseek-v4-flash": "DeepSeek V4 Flash"
    ]

    private static let legacyIDs: [String: String] = [
        "gpt-5.6-sol|low": "gpt_56_sol_low",
        "gpt-5.6-sol|medium": "gpt_56_sol_medium",
        "gpt-5.6-sol|high": "gpt_56_sol_high",
        "gpt-5.6-sol|xhigh": "gpt_56_sol_xhigh",
        "gpt-5.6-terra|high": "gpt_56_terra_high",
        "gpt-5.6-terra|max": "gpt_56_terra_max",
        "gpt-5.6-terra|xhigh": "gpt_56_terra_xhigh_distributed",
        "gpt-5.6-luna|high": "gpt_56_luna_high",
        "gpt-5.6-luna|max": "gpt_56_luna_max",
        "gpt-5.5|high": "gpt_55_high_distributed",
        "gpt-5.5|xhigh": "gpt_55_xhigh_distributed"
    ]

    private static let compatibleIDPrefixes: [String: String] = [
        "gpt-5.6-sol": "gpt_56_sol",
        "gpt-5.6-terra": "gpt_56_terra",
        "gpt-5.6-luna": "gpt_56_luna",
        "gpt-5.5": "gpt_55",
        "deepseek-v4-flash": "deepseek_v4_flash"
    ]

    private static func sanitizedIDComponent(_ value: String) -> String {
        var result = ""
        var previousWasSeparator = false
        for scalar in value.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                previousWasSeparator = false
            } else if !previousWasSeparator, !result.isEmpty {
                result.append("_")
                previousWasSeparator = true
            }
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }
}

private struct LossyDecodableArray<Element: Decodable>: Decodable {
    let elements: [Element]

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var elements: [Element] = []
        while !container.isAtEnd {
            do {
                elements.append(try container.decode(Element.self))
            } catch {
                _ = try? container.decode(DiscardedDecodableValue.self)
            }
        }
        self.elements = elements
    }
}

private struct DiscardedDecodableValue: Decodable {
    init(from decoder: Decoder) throws {}
}
