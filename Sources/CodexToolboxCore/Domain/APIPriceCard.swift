import Foundation

public enum APIPriceSourceKind: String, Codable, Hashable, Sendable {
    case openAIOfficial = "openai_official"
    case modelsDev = "models_dev"
}

public enum CostEstimatePrecision: String, Codable, Hashable, Sendable {
    case exact
    case approximate
    case lowerBound
}

public struct APITokenPrice: Codable, Hashable, Sendable {
    public let inputUSDPerMillion: Decimal
    public let cachedInputUSDPerMillion: Decimal?
    public let cacheWriteUSDPerMillion: Decimal?
    public let outputUSDPerMillion: Decimal

    private enum CodingKeys: String, CodingKey {
        case inputUSDPerMillion = "input_usd_per_million"
        case cachedInputUSDPerMillion = "cached_input_usd_per_million"
        case cacheWriteUSDPerMillion = "cache_write_usd_per_million"
        case outputUSDPerMillion = "output_usd_per_million"
    }

    public init(
        inputUSDPerMillion: Decimal,
        cachedInputUSDPerMillion: Decimal?,
        cacheWriteUSDPerMillion: Decimal?,
        outputUSDPerMillion: Decimal
    ) {
        self.inputUSDPerMillion = inputUSDPerMillion
        self.cachedInputUSDPerMillion = cachedInputUSDPerMillion
        self.cacheWriteUSDPerMillion = cacheWriteUSDPerMillion
        self.outputUSDPerMillion = outputUSDPerMillion
    }

    fileprivate var isValid: Bool {
        inputUSDPerMillion.isFiniteAndNonnegative
            && (cachedInputUSDPerMillion?.isFiniteAndNonnegative ?? true)
            && (cacheWriteUSDPerMillion?.isFiniteAndNonnegative ?? true)
            && outputUSDPerMillion.isFiniteAndNonnegative
    }
}

public struct APIContextPriceTier: Codable, Hashable, Sendable {
    public let minimumInputTokens: Int64
    public let price: APITokenPrice
    public let priorityPrice: APITokenPrice?

    private enum CodingKeys: String, CodingKey {
        case minimumInputTokens = "minimum_input_tokens"
        case price
        case priorityPrice = "priority_price"
    }

    public init(
        minimumInputTokens: Int64,
        price: APITokenPrice,
        priorityPrice: APITokenPrice? = nil
    ) {
        self.minimumInputTokens = minimumInputTokens
        self.price = price
        self.priorityPrice = priorityPrice
    }
}

public struct APIModelPrice: Codable, Hashable, Sendable {
    public let id: String
    public let providerID: String
    public let aliases: [String]
    public let source: APIPriceSourceKind
    public let sourceUpdatedAt: String?
    public let firstCapturedAt: String?
    public let standard: APITokenPrice
    public let priority: APITokenPrice?
    public let contextTiers: [APIContextPriceTier]

    private enum CodingKeys: String, CodingKey {
        case id
        case providerID = "provider_id"
        case aliases
        case source
        case sourceUpdatedAt = "source_updated_at"
        case firstCapturedAt = "first_captured_at"
        case standard
        case priority
        case contextTiers = "context_tiers"
    }

    public init(
        id: String,
        providerID: String,
        aliases: [String],
        source: APIPriceSourceKind,
        sourceUpdatedAt: String?,
        firstCapturedAt: String? = nil,
        standard: APITokenPrice,
        priority: APITokenPrice?,
        contextTiers: [APIContextPriceTier]
    ) {
        self.id = id
        self.providerID = providerID
        self.aliases = aliases
        self.source = source
        self.sourceUpdatedAt = sourceUpdatedAt
        self.firstCapturedAt = firstCapturedAt
        self.standard = standard
        self.priority = priority
        self.contextTiers = contextTiers
    }

    fileprivate func matches(modelID: String) -> Bool {
        let model = Self.normalizedModel(modelID)
        return aliases.contains { Self.normalizedModel($0) == model }
    }

    fileprivate func price(inputTokens: Int64, priority: Bool) -> APITokenPrice? {
        let contextTier = contextTiers
            .filter { inputTokens > $0.minimumInputTokens }
            .max { $0.minimumInputTokens < $1.minimumInputTokens }
        if priority {
            return contextTier == nil ? self.priority : contextTier?.priorityPrice
        }
        return contextTier?.price ?? standard
    }

    fileprivate var isValid: Bool {
        !id.isEmpty
            && !providerID.isEmpty
            && !aliases.isEmpty
            && Set(aliases.map(Self.normalizedModel)).count == aliases.count
            && standard.isValid
            && (priority?.isValid ?? true)
            && (sourceUpdatedAt.flatMap(Self.iso8601Date) != nil || sourceUpdatedAt == nil)
            && (firstCapturedAt.flatMap(Self.iso8601Date) != nil || firstCapturedAt == nil)
            && contextTiers.allSatisfy {
                $0.minimumInputTokens > 0
                    && $0.price.isValid
                    && ($0.priorityPrice?.isValid ?? true)
            }
    }

    fileprivate static func normalizedModel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            .split(separator: "/").last.map(String.init) ?? ""
    }

    private static func iso8601Date(_ value: String) -> Date? {
        if let date = try? Date(value, strategy: .iso8601) { return date }
        guard value.count == 10 else { return nil }
        return try? Date("\(value)T00:00:00Z", strategy: .iso8601)
    }
}

public struct APIPriceVersion: Codable, Hashable, Sendable {
    public let id: String
    public let effectiveAt: String
    public let models: [APIModelPrice]

    private enum CodingKeys: String, CodingKey {
        case id
        case effectiveAt = "effective_at"
        case models
    }

    public init(id: String, effectiveAt: String, models: [APIModelPrice]) {
        self.id = id
        self.effectiveAt = effectiveAt
        self.models = models
    }
}

public struct APICostBreakdown: Codable, Hashable, Sendable {
    public let freshInputUSD: Decimal
    public let cachedInputUSD: Decimal
    public let cacheWriteUSD: Decimal
    public let outputUSD: Decimal

    public var totalUSD: Decimal {
        freshInputUSD + cachedInputUSD + cacheWriteUSD + outputUSD
    }

    public init(
        freshInputUSD: Decimal,
        cachedInputUSD: Decimal,
        cacheWriteUSD: Decimal,
        outputUSD: Decimal
    ) {
        self.freshInputUSD = max(0, freshInputUSD)
        self.cachedInputUSD = max(0, cachedInputUSD)
        self.cacheWriteUSD = max(0, cacheWriteUSD)
        self.outputUSD = max(0, outputUSD)
    }
}

public struct TokenCostEstimate: Codable, Hashable, Sendable {
    public let amountUSD: Decimal
    public let breakdown: APICostBreakdown
    public let precision: CostEstimatePrecision
    public let priceVersion: String
    public let modelPriceID: String
    public let source: APIPriceSourceKind
    public let pricedTokens: Int64

    public init(
        amountUSD: Decimal,
        breakdown: APICostBreakdown,
        precision: CostEstimatePrecision,
        priceVersion: String,
        modelPriceID: String,
        source: APIPriceSourceKind,
        pricedTokens: Int64
    ) {
        self.amountUSD = max(0, amountUSD)
        self.breakdown = breakdown
        self.precision = precision
        self.priceVersion = priceVersion
        self.modelPriceID = modelPriceID
        self.source = source
        self.pricedTokens = max(0, pricedTokens)
    }
}

public struct APIPriceManifest: Codable, Hashable, Sendable {
    public let schema: Int
    public let currentVersion: String
    public let generatedAt: String
    public let sources: [String]
    public let versions: [APIPriceVersion]

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
        versions: [APIPriceVersion]
    ) {
        self.schema = schema
        self.currentVersion = currentVersion
        self.generatedAt = generatedAt
        self.sources = sources
        self.versions = versions
    }

    public var activeVersion: APIPriceVersion? {
        versions.first { $0.id == currentVersion }
    }

    public func validated() throws -> APIPriceManifest {
        guard schema == 1,
              !currentVersion.isEmpty,
              !generatedAt.isEmpty,
              !sources.isEmpty,
              Set(versions.map(\.id)).count == versions.count,
              activeVersion != nil else {
            throw APIPriceValidationError.invalidManifest
        }
        var previousDate = Date.distantPast
        for version in versions {
            guard !version.id.isEmpty,
                  let date = try? Date(version.effectiveAt, strategy: .iso8601),
                  date > previousDate,
                  !version.models.isEmpty,
                  Set(version.models.map(\.id)).count == version.models.count,
                  version.models.allSatisfy(\.isValid) else {
                throw APIPriceValidationError.invalidManifest
            }
            let aliases = version.models.flatMap { model in
                model.aliases.map { "\(model.providerID)|\(APIModelPrice.normalizedModel($0))" }
            }
            guard Set(aliases).count == aliases.count else {
                throw APIPriceValidationError.duplicateAlias
            }
            previousDate = date
        }
        guard versions.last?.id == currentVersion,
              activeVersion?.models.contains(where: {
                  $0.providerID == "openai" && $0.aliases.contains("gpt-5.6-terra")
              }) == true else {
            throw APIPriceValidationError.missingOpenAIPrice
        }
        return self
    }

    public func isHistoryPreservingSuccessor(of previous: APIPriceManifest) -> Bool {
        let byID = Dictionary(uniqueKeysWithValues: versions.map { ($0.id, $0) })
        return previous.versions.allSatisfy { byID[$0.id] == $0 }
            && versions.last?.id == currentVersion
    }

    public func cost(
        for breakdown: UsageTokenBreakdown,
        context: UsageExecutionContext,
        at timestamp: Date
    ) -> TokenCostEstimate? {
        guard breakdown.hasConsistentComponents,
              let modelID = context.modelID else { return nil }
        let versionSelection = selectedVersion(at: timestamp)
        guard var version = versionSelection.version else { return nil }
        var usedHistoricalFallback = versionSelection.usedHistoricalFallback
        var model = matchedModel(
            modelID: modelID,
            providerID: context.modelProviderID,
            models: version.models
        )
        if model == nil,
           let activeVersion,
           let currentModel = matchedModel(
               modelID: modelID,
               providerID: context.modelProviderID,
               models: activeVersion.models
           ),
           currentModel.source == .modelsDev {
            version = activeVersion
            model = currentModel
            usedHistoricalFallback = true
        }
        guard let model else { return nil }

        let usesPriority = context.isFast == true
        guard let price = model.price(
            inputTokens: breakdown.inputTokens,
            priority: usesPriority
        ) else { return nil }
        let cached = min(breakdown.inputTokens, breakdown.cachedInputTokens)
        let cacheWrite: Int64
        let predatesModelsDevCapture = model.source == .modelsDev
            && model.firstCapturedAt.flatMap { try? Date($0, strategy: .iso8601) }
                .map { timestamp < $0 } == true
        var isApproximate = usedHistoricalFallback
            || predatesModelsDevCapture
            || context.isFast == nil
        if let recorded = breakdown.cacheWriteInputTokens {
            cacheWrite = min(max(0, breakdown.inputTokens - cached), recorded)
        } else {
            cacheWrite = 0
            isApproximate = true
        }
        let fresh = max(0, breakdown.inputTokens - cached - cacheWrite)
        let cachedRate = price.cachedInputUSDPerMillion
        let cacheWriteRate = price.cacheWriteUSDPerMillion
        let calculated = APICostBreakdown(
            freshInputUSD: Self.componentCost(tokens: fresh, rate: price.inputUSDPerMillion),
            cachedInputUSD: cachedRate.map {
                Self.componentCost(tokens: cached, rate: $0)
            } ?? 0,
            cacheWriteUSD: cacheWriteRate.map {
                Self.componentCost(tokens: cacheWrite, rate: $0)
            } ?? 0,
            outputUSD: Self.componentCost(
                tokens: breakdown.outputTokens,
                rate: price.outputUSDPerMillion
            )
        )
        let pricedTokens = fresh
            + (cachedRate == nil ? 0 : cached)
            + (cacheWriteRate == nil ? 0 : cacheWrite)
            + breakdown.outputTokens
        let isPartiallyPriced = pricedTokens < breakdown.totalTokens
        return TokenCostEstimate(
            amountUSD: calculated.totalUSD,
            breakdown: calculated,
            precision: isPartiallyPriced
                ? .lowerBound
                : isApproximate ? .approximate : .exact,
            priceVersion: version.id,
            modelPriceID: model.id,
            source: model.source,
            pricedTokens: pricedTokens
        )
    }

    private func selectedVersion(at timestamp: Date) -> (
        version: APIPriceVersion?,
        usedHistoricalFallback: Bool
    ) {
        let eligible = versions.filter {
            guard let date = try? Date($0.effectiveAt, strategy: .iso8601) else { return false }
            return date <= timestamp
        }
        if let version = eligible.last { return (version, false) }
        return (versions.first, true)
    }

    private func matchedModel(
        modelID: String,
        providerID: String?,
        models: [APIModelPrice]
    ) -> APIModelPrice? {
        let matches = models.filter { $0.matches(modelID: modelID) }
        let provider = Self.canonicalProvider(providerID)
        if let provider {
            return matches.first { $0.providerID == provider }
        }
        if APIModelPrice.normalizedModel(modelID).hasPrefix("gpt-") {
            return matches.first { $0.providerID == "openai" }
        }
        let providers = Set(matches.map(\.providerID))
        return providers.count == 1 ? matches.first : nil
    }

    private static func canonicalProvider(_ value: String?) -> String? {
        guard let value = value?.lowercased() else { return nil }
        if value.contains("openai") { return "openai" }
        if value.contains("xai") { return "xai" }
        if value.contains("moonshot") || value.contains("kimi") { return "moonshot" }
        if value.contains("dsh") { return "dsh" }
        if value.contains("deepseek") { return "deepseek" }
        if value.contains("zhipu") || value.contains("zai") || value.contains("glm") { return "zai" }
        return nil
    }

    private static func componentCost(tokens: Int64, rate: Decimal) -> Decimal {
        Decimal(max(0, tokens)) * rate / Decimal(1_000_000)
    }
}

public enum APIPriceValidationError: Error, LocalizedError, Equatable, Sendable {
    case invalidManifest
    case duplicateAlias
    case missingOpenAIPrice

    public var errorDescription: String? {
        switch self {
        case .invalidManifest: "API 价格清单结构无效。"
        case .duplicateAlias: "API 价格清单包含重复模型别名。"
        case .missingOpenAIPrice: "API 价格清单缺少必需的 OpenAI 模型价格。"
        }
    }
}

private extension Decimal {
    var isFiniteAndNonnegative: Bool {
        self >= 0 && !isNaN
    }
}
