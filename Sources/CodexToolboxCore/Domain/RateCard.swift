import Foundation

public struct UsageTokenBreakdown: Codable, Hashable, Sendable {
    public let inputTokens: Int64
    public let cachedInputTokens: Int64
    public let cacheWriteInputTokens: Int64?
    public let outputTokens: Int64
    public let reasoningOutputTokens: Int64
    public let totalTokens: Int64

    public init(
        inputTokens: Int64,
        cachedInputTokens: Int64,
        cacheWriteInputTokens: Int64?,
        outputTokens: Int64,
        reasoningOutputTokens: Int64,
        totalTokens: Int64
    ) {
        self.inputTokens = max(0, inputTokens)
        self.cachedInputTokens = max(0, cachedInputTokens)
        self.cacheWriteInputTokens = cacheWriteInputTokens.map { max(0, $0) }
        self.outputTokens = max(0, outputTokens)
        self.reasoningOutputTokens = max(0, reasoningOutputTokens)
        self.totalTokens = max(0, totalTokens)
    }

    public var hasConsistentComponents: Bool {
        cachedInputTokens <= inputTokens
            && reasoningOutputTokens <= outputTokens
            && (cacheWriteInputTokens.map { cachedInputTokens + $0 <= inputTokens } ?? true)
    }
}

public struct UsageExecutionContext: Codable, Hashable, Sendable {
    public let modelID: String?
    public let reasoningEffort: String?
    public let serviceTier: String?
    public let modelProviderID: String?
    public let planType: String?
    public let hasAccountRateLimits: Bool
    public let rateCardMode: RateCardMode?
    public let rateCardVersion: String?

    public init(
        modelID: String?,
        reasoningEffort: String?,
        serviceTier: String?,
        modelProviderID: String? = nil,
        planType: String? = nil,
        hasAccountRateLimits: Bool = false,
        rateCardMode: RateCardMode? = nil,
        rateCardVersion: String? = nil
    ) {
        self.modelID = Self.normalized(modelID)
        self.reasoningEffort = Self.normalized(reasoningEffort)
        self.serviceTier = Self.normalized(serviceTier)
        self.modelProviderID = Self.normalized(modelProviderID)
        self.planType = Self.normalized(planType)
        self.hasAccountRateLimits = hasAccountRateLimits
        self.rateCardMode = rateCardMode
        self.rateCardVersion = Self.normalized(rateCardVersion)
    }

    public var isFast: Bool? {
        guard let serviceTier else { return nil }
        if ["priority", "fast"].contains(serviceTier) { return true }
        if ["default", "standard", "auto"].contains(serviceTier) { return false }
        return nil
    }

    public var isConfirmedChatGPTCreditUsage: Bool {
        guard modelProviderID?.contains("api") != true else { return false }
        return hasAccountRateLimits || planType != nil
    }

    private static func normalized(_ value: String?) -> String? {
        let value = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return value.isEmpty ? nil : value
    }
}

public enum CreditEstimatePrecision: String, Codable, Hashable, Sendable {
    case exact
    case approximate
    case upperBound
    case lowerBound
}

public struct TokenCreditEstimate: Codable, Hashable, Sendable {
    public let credits: Double
    public let precision: CreditEstimatePrecision
    public let rateCardVersion: String
    public let modelRateID: String

    public init(
        credits: Double,
        precision: CreditEstimatePrecision,
        rateCardVersion: String,
        modelRateID: String
    ) {
        self.credits = max(0, credits)
        self.precision = precision
        self.rateCardVersion = rateCardVersion
        self.modelRateID = modelRateID
    }
}

public struct RateCardManifest: Codable, Hashable, Sendable {
    public let schema: Int
    public let currentVersion: String
    public let generatedAt: String
    public let sources: [String]
    public let versions: [RateCardVersion]

    private enum CodingKeys: String, CodingKey {
        case schema
        case currentVersion = "current_version"
        case generatedAt = "generated_at"
        case sources
        case versions
    }

    public init(
        schema: Int,
        currentVersion: String,
        generatedAt: String,
        sources: [String],
        versions: [RateCardVersion]
    ) {
        self.schema = schema
        self.currentVersion = currentVersion
        self.generatedAt = generatedAt
        self.sources = sources
        self.versions = versions
    }

    public var activeVersion: RateCardVersion? {
        versions.first { $0.id == currentVersion }
    }

    public var latestEffectiveAt: Date? {
        activeVersion.flatMap { try? Date($0.effectiveAt, strategy: .iso8601) }
    }

    public func isHistoryPreservingSuccessor(of previous: RateCardManifest) -> Bool {
        let byID = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0) })
        return previous.versions.allSatisfy { byID[$0.id] == $0 }
            && (latestEffectiveAt ?? .distantPast) >= (previous.latestEffectiveAt ?? .distantPast)
    }

    public func version(at timestamp: Date) -> RateCardVersion? {
        return versions
            .filter { version in
                guard let effectiveAt = try? Date(version.effectiveAt, strategy: .iso8601) else {
                    return false
                }
                return effectiveAt <= timestamp
            }
            .max { lhs, rhs in lhs.effectiveAt < rhs.effectiveAt }
    }

    public func validated() throws -> RateCardManifest {
        guard schema == 1 else { throw RateCardValidationError.unsupportedSchema(schema) }
        guard !currentVersion.isEmpty, !generatedAt.isEmpty else {
            throw RateCardValidationError.missingMetadata
        }
        guard Set(versions.map(\.id)).count == versions.count,
              let activeVersion else {
            throw RateCardValidationError.invalidVersions
        }
        for version in versions { try version.validate() }
        let effectiveDates = try versions.map { version -> Date in
            guard let date = try? Date(version.effectiveAt, strategy: .iso8601) else {
                throw RateCardValidationError.invalidVersions
            }
            return date
        }
        guard zip(effectiveDates, effectiveDates.dropFirst()).allSatisfy({ pair in
            pair.0 < pair.1
        }),
              versions.last?.id == activeVersion.id else {
            throw RateCardValidationError.invalidVersions
        }
        guard !activeVersion.models.isEmpty else { throw RateCardValidationError.invalidVersions }
        return self
    }

    public func credits(
        for breakdown: UsageTokenBreakdown,
        context: UsageExecutionContext,
        mode: RateCardMode,
        at timestamp: Date
    ) -> TokenCreditEstimate? {
        guard breakdown.hasConsistentComponents,
              let modelID = context.modelID,
              let version = version(at: timestamp) else { return nil }
        guard context.modelProviderID?.contains("api") != true else { return nil }

        let resolvedMode: RateCardMode
        switch mode {
        case .automatic:
            guard context.isConfirmedChatGPTCreditUsage,
                  let planType = context.planType else { return nil }
            resolvedMode = planType.contains("legacy") ? .legacy : .tokenBased
        case .tokenBased, .legacy:
            resolvedMode = mode
        }
        if resolvedMode == .legacy {
            guard let legacy = version.bestLegacyRate(for: modelID) else { return nil }
            return TokenCreditEstimate(
                credits: legacy.creditsPerMessage,
                precision: .approximate,
                rateCardVersion: version.id,
                modelRateID: legacy.id
            )
        }

        guard let rate = version.bestModelRate(for: modelID) else { return nil }
        let cached = min(breakdown.inputTokens, breakdown.cachedInputTokens)
        let cacheWrite: Int64
        let precision: CreditEstimatePrecision
        if let recordedWrite = breakdown.cacheWriteInputTokens {
            cacheWrite = min(max(0, breakdown.inputTokens - cached), recordedWrite)
            precision = context.isFast == nil ? .lowerBound : .exact
        } else {
            cacheWrite = 0
            precision = context.isFast == nil ? .approximate : .upperBound
        }
        let fresh = max(0, breakdown.inputTokens - cached - cacheWrite)
        var credits = (
            Double(fresh) * rate.inputCreditsPerMillion
                + Double(cached) * rate.cachedInputCreditsPerMillion
                + Double(breakdown.outputTokens) * rate.outputCreditsPerMillion
        ) / 1_000_000
        if context.isFast == true {
            guard let multiplier = version.fastMultiplier(for: modelID) else { return nil }
            credits *= multiplier
        }
        return TokenCreditEstimate(
            credits: credits,
            precision: precision,
            rateCardVersion: version.id,
            modelRateID: rate.id
        )
    }
}

public struct RateCardVersion: Codable, Hashable, Sendable {
    public let id: String
    public let effectiveAt: String
    public let models: [ModelTokenRate]
    public let fastMultipliers: [FastRateMultiplier]
    public let legacyModels: [LegacyMessageRate]

    private enum CodingKeys: String, CodingKey {
        case id
        case effectiveAt = "effective_at"
        case models
        case fastMultipliers = "fast_multipliers"
        case legacyModels = "legacy_models"
    }

    public init(
        id: String,
        effectiveAt: String,
        models: [ModelTokenRate],
        fastMultipliers: [FastRateMultiplier],
        legacyModels: [LegacyMessageRate]
    ) {
        self.id = id
        self.effectiveAt = effectiveAt
        self.models = models
        self.fastMultipliers = fastMultipliers
        self.legacyModels = legacyModels
    }

    func validate() throws {
        guard !id.isEmpty,
              (try? Date(effectiveAt, strategy: .iso8601)) != nil,
              Set(models.map(\.id)).count == models.count,
              Set(fastMultipliers.map(\.modelPrefix)).count == fastMultipliers.count,
              Set(legacyModels.map(\.id)).count == legacyModels.count else {
            throw RateCardValidationError.invalidVersions
        }
        guard models.allSatisfy(\.isValid),
              fastMultipliers.allSatisfy({ $0.multiplier > 1 && $0.multiplier.isFinite }),
              legacyModels.allSatisfy({ $0.creditsPerMessage >= 0 && $0.creditsPerMessage.isFinite }) else {
            throw RateCardValidationError.invalidRate
        }
    }

    func bestModelRate(for modelID: String) -> ModelTokenRate? {
        models
            .filter { $0.matches(modelID) }
            .max { $0.longestMatchingAlias(in: modelID) < $1.longestMatchingAlias(in: modelID) }
    }

    func bestLegacyRate(for modelID: String) -> LegacyMessageRate? {
        legacyModels
            .filter { $0.matches(modelID) }
            .max { $0.longestMatchingAlias(in: modelID) < $1.longestMatchingAlias(in: modelID) }
    }

    func fastMultiplier(for modelID: String) -> Double? {
        fastMultipliers
            .filter { modelID.lowercased().contains($0.modelPrefix.lowercased()) }
            .max { $0.modelPrefix.count < $1.modelPrefix.count }?
            .multiplier
    }
}

public struct ModelTokenRate: Codable, Hashable, Sendable {
    public let id: String
    public let aliases: [String]
    public let inputCreditsPerMillion: Double
    public let cachedInputCreditsPerMillion: Double
    public let outputCreditsPerMillion: Double

    private enum CodingKeys: String, CodingKey {
        case id
        case aliases
        case inputCreditsPerMillion = "input_credits_per_million"
        case cachedInputCreditsPerMillion = "cached_input_credits_per_million"
        case outputCreditsPerMillion = "output_credits_per_million"
    }

    public init(
        id: String,
        aliases: [String],
        inputCreditsPerMillion: Double,
        cachedInputCreditsPerMillion: Double,
        outputCreditsPerMillion: Double
    ) {
        self.id = id
        self.aliases = aliases
        self.inputCreditsPerMillion = inputCreditsPerMillion
        self.cachedInputCreditsPerMillion = cachedInputCreditsPerMillion
        self.outputCreditsPerMillion = outputCreditsPerMillion
    }

    var isValid: Bool {
        !id.isEmpty && !aliases.isEmpty
            && inputCreditsPerMillion >= 0 && inputCreditsPerMillion.isFinite
            && cachedInputCreditsPerMillion >= 0 && cachedInputCreditsPerMillion.isFinite
            && cachedInputCreditsPerMillion <= inputCreditsPerMillion
            && outputCreditsPerMillion >= 0 && outputCreditsPerMillion.isFinite
    }

    func matches(_ modelID: String) -> Bool { longestMatchingAlias(in: modelID) > 0 }

    func longestMatchingAlias(in modelID: String) -> Int {
        let normalized = modelID.lowercased()
        return aliases.map { $0.lowercased() }.filter(normalized.contains).map(\.count).max() ?? 0
    }
}

public struct FastRateMultiplier: Codable, Hashable, Sendable {
    public let modelPrefix: String
    public let multiplier: Double

    private enum CodingKeys: String, CodingKey {
        case modelPrefix = "model_prefix"
        case multiplier
    }

    public init(modelPrefix: String, multiplier: Double) {
        self.modelPrefix = modelPrefix
        self.multiplier = multiplier
    }
}

public struct LegacyMessageRate: Codable, Hashable, Sendable {
    public let id: String
    public let aliases: [String]
    public let creditsPerMessage: Double

    private enum CodingKeys: String, CodingKey {
        case id
        case aliases
        case creditsPerMessage = "credits_per_message"
    }

    public init(id: String, aliases: [String], creditsPerMessage: Double) {
        self.id = id
        self.aliases = aliases
        self.creditsPerMessage = creditsPerMessage
    }

    func matches(_ modelID: String) -> Bool { longestMatchingAlias(in: modelID) > 0 }

    func longestMatchingAlias(in modelID: String) -> Int {
        let normalized = modelID.lowercased()
        return aliases.map { $0.lowercased() }.filter(normalized.contains).map(\.count).max() ?? 0
    }
}

public enum RateCardValidationError: Error, LocalizedError, Sendable, Equatable {
    case unsupportedSchema(Int)
    case missingMetadata
    case invalidVersions
    case invalidRate

    public var errorDescription: String? {
        switch self {
        case let .unsupportedSchema(schema): "不支持的官方费率数据版本：\(schema)"
        case .missingMetadata: "官方费率数据缺少版本信息。"
        case .invalidVersions: "官方费率版本列表无效。"
        case .invalidRate: "官方费率包含无效数值。"
        }
    }
}
