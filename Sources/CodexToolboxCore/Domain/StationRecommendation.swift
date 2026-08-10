import Foundation

public enum StationRecommendationScenarioKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case dailyDevelopment = "daily_development"
    case hardProblems = "hard_problems"
    case backgroundAutomation = "background_automation"
    case lobsterTasks = "lobster_tasks"

    public var id: String { rawValue }

    public var shortTitle: String {
        switch self {
        case .dailyDevelopment: "日常"
        case .hardProblems: "困难"
        case .backgroundAutomation: "后台"
        case .lobsterTasks: "龙虾"
        }
    }

    public var fallbackTitle: String {
        switch self {
        case .dailyDevelopment: "日常开发"
        case .hardProblems: "困难任务"
        case .backgroundAutomation: "后台自动化"
        case .lobsterTasks: "龙虾类任务"
        }
    }
}

public struct StationRecommendationItem: Codable, Hashable, Sendable {
    public let model: String
    public let effort: String
    public let iq: Double?
    public let averageCostUSD: Double?
    public let averageDurationMinutes: Double?
    public let rule: String?

    private enum CodingKeys: String, CodingKey {
        case model
        case effort
        case iq
        case averageCostUSD = "average_cost_usd"
        case averageDurationMinutes = "average_duration_minutes"
        case rule
    }

    public init(
        model: String,
        effort: String,
        iq: Double?,
        averageCostUSD: Double?,
        averageDurationMinutes: Double?,
        rule: String?
    ) {
        self.model = model
        self.effort = effort
        self.iq = iq.flatMap(Self.finite)
        self.averageCostUSD = averageCostUSD.flatMap { value in
            guard let value = Self.finite(value), value >= 0 else { return nil }
            return value
        }
        self.averageDurationMinutes = averageDurationMinutes.flatMap { value in
            guard let value = Self.finite(value), value >= 0 else { return nil }
            return value
        }
        let trimmedRule = rule?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rule = trimmedRule?.isEmpty == false ? trimmedRule : nil
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            model: try container.decodeIfPresent(String.self, forKey: .model) ?? "",
            effort: try container.decodeIfPresent(String.self, forKey: .effort) ?? "",
            iq: try container.decodeIfPresent(Double.self, forKey: .iq),
            averageCostUSD: try container.decodeIfPresent(Double.self, forKey: .averageCostUSD),
            averageDurationMinutes: try container.decodeIfPresent(
                Double.self,
                forKey: .averageDurationMinutes
            ),
            rule: try container.decodeIfPresent(String.self, forKey: .rule)
        )
    }

    private static func finite(_ value: Double) -> Double? {
        value.isFinite ? value : nil
    }
}

public struct StationRecommendationScenario: Codable, Hashable, Identifiable, Sendable {
    public let key: StationRecommendationScenarioKey
    public let title: String
    public let rule: String?
    public let items: [StationRecommendationItem]

    public var id: StationRecommendationScenarioKey { key }

    public init(
        key: StationRecommendationScenarioKey,
        title: String,
        rule: String?,
        items: [StationRecommendationItem]
    ) {
        self.key = key
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = trimmedTitle.isEmpty ? key.fallbackTitle : trimmedTitle
        let trimmedRule = rule?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rule = trimmedRule?.isEmpty == false ? trimmedRule : nil
        self.items = Array(items.filter {
            !$0.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.effort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.prefix(2))
    }
}

public struct StationRecommendationSnapshot: Codable, Hashable, Sendable {
    public let schema: Int
    public let mode: String
    public let generatedAt: String?
    public let sourceUpdatedAt: String?
    public let fetchedAt: Date
    public let scenarios: [StationRecommendationScenario]
    public let validators: CacheValidators

    public init(
        schema: Int,
        mode: String,
        generatedAt: String?,
        sourceUpdatedAt: String?,
        fetchedAt: Date,
        scenarios: [StationRecommendationScenario],
        validators: CacheValidators
    ) {
        self.schema = schema
        self.mode = mode
        self.generatedAt = generatedAt
        self.sourceUpdatedAt = sourceUpdatedAt
        self.fetchedAt = fetchedAt
        let byKey = scenarios.reduce(into: [StationRecommendationScenarioKey: StationRecommendationScenario]()) {
            result, scenario in
            if result[scenario.key] == nil { result[scenario.key] = scenario }
        }
        self.scenarios = StationRecommendationScenarioKey.allCases.compactMap { byKey[$0] }
        self.validators = validators
    }

    public func scenario(for key: StationRecommendationScenarioKey) -> StationRecommendationScenario? {
        scenarios.first { $0.key == key }
    }
}

struct StationRecommendationResponse: Decodable, Sendable {
    let schema: Int
    let mode: String
    let generatedAt: String?
    let sourceUpdatedAt: String?
    let recommendations: [Recommendation]

    private enum CodingKeys: String, CodingKey {
        case schema
        case mode
        case generatedAt = "generated_at"
        case sourceUpdatedAt = "source_updated_at"
        case recommendations
    }

    struct Recommendation: Decodable, Sendable {
        let key: String
        let title: String?
        let rule: String?
        let items: [StationRecommendationItem]
    }

    var scenarios: [StationRecommendationScenario] {
        recommendations.compactMap { recommendation in
            guard let key = StationRecommendationScenarioKey(rawValue: recommendation.key) else {
                return nil
            }
            return StationRecommendationScenario(
                key: key,
                title: recommendation.title ?? key.fallbackTitle,
                rule: recommendation.rule,
                items: recommendation.items
            )
        }
    }
}
