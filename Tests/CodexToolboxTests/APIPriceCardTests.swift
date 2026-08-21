import Foundation
import XCTest
@testable import CodexToolboxCore

final class APIPriceCardTests: XCTestCase {
    func testOnlinePriceErrorsIdentifyFallbackInsteadOfGenericDataServer() {
        XCTAssertEqual(
            APIPriceCardClientError.httpStatus(404).localizedDescription,
            "在线 API 价格清单检查失败（HTTP 404）；继续使用本地价格。"
        )
        XCTAssertEqual(
            APIPriceCardClientError.transport("网络离线").localizedDescription,
            "在线 API 价格清单连接失败：网络离线；继续使用本地价格。"
        )
        XCTAssertFalse(
            APIPriceCardClientError.invalidPayload("bad json")
                .localizedDescription.contains("CodexRadar")
        )
    }

    func testComponentCostSubtractsCacheReadsAndWritesAndDoesNotDoubleReasoning() throws {
        let manifest = try manifest(models: [
            model(
                id: "openai-gpt-5.6-terra",
                provider: "openai",
                aliases: ["gpt-5.6-terra"],
                standard: price(input: 10, cached: 2, write: 3, output: 20)
            )
        ]).validated()
        let estimate = try XCTUnwrap(
            manifest.cost(
                for: breakdown(),
                context: context(model: "gpt-5.6-terra", provider: "openai"),
                at: date("2026-08-20T12:00:00Z")
            )
        )

        XCTAssertEqual(estimate.breakdown.freshInputUSD, Decimal(string: "7"))
        XCTAssertEqual(estimate.breakdown.cachedInputUSD, Decimal(string: "0.4"))
        XCTAssertEqual(estimate.breakdown.cacheWriteUSD, Decimal(string: "0.3"))
        XCTAssertEqual(estimate.breakdown.outputUSD, Decimal(string: "6"))
        XCTAssertEqual(estimate.amountUSD, Decimal(string: "13.7"))
        XCTAssertEqual(estimate.pricedTokens, 1_300_000)
        XCTAssertEqual(estimate.precision, .exact)
    }

    func testMissingCacheWritePriceProducesPartialLowerBoundButExplicitZeroIsExact() throws {
        let missing = try manifest(models: [
            model(
                id: "openai-gpt-5.6-terra",
                provider: "openai",
                aliases: ["gpt-5.6-terra"],
                standard: price(input: 10, cached: 2, write: nil, output: 20)
            )
        ]).validated()
        let partial = try XCTUnwrap(
            missing.cost(
                for: breakdown(),
                context: context(model: "gpt-5.6-terra", provider: "openai"),
                at: date("2026-08-20T12:00:00Z")
            )
        )
        XCTAssertEqual(partial.amountUSD, Decimal(string: "13.4"))
        XCTAssertEqual(partial.pricedTokens, 1_200_000)
        XCTAssertEqual(partial.precision, .lowerBound)

        let freeWrite = try manifest(models: [
            model(
                id: "openai-gpt-5.6-terra",
                provider: "openai",
                aliases: ["gpt-5.6-terra"],
                standard: price(input: 10, cached: 2, write: 0, output: 20)
            )
        ]).validated()
        let exact = try XCTUnwrap(
            freeWrite.cost(
                for: breakdown(),
                context: context(model: "gpt-5.6-terra", provider: "openai"),
                at: date("2026-08-20T12:00:00Z")
            )
        )
        XCTAssertEqual(exact.amountUSD, Decimal(string: "13.4"))
        XCTAssertEqual(exact.pricedTokens, 1_300_000)
        XCTAssertEqual(exact.precision, .exact)
    }

    func testFastLongContextUsesCombinedTier() throws {
        let standard = price(input: 1, cached: 0.1, write: 1.25, output: 2)
        let row = model(
            id: "openai-gpt-5.6-terra",
            provider: "openai",
            aliases: ["gpt-5.6-terra"],
            standard: standard,
            priority: price(input: 2, cached: 0.2, write: 2.5, output: 4),
            tiers: [
                APIContextPriceTier(
                    minimumInputTokens: 272_000,
                    price: price(input: 3, cached: 0.3, write: 3.75, output: 6),
                    priorityPrice: price(input: 6, cached: 0.6, write: 7.5, output: 12)
                )
            ]
        )
        let estimate = try XCTUnwrap(
            try manifest(models: [row]).validated().cost(
                for: UsageTokenBreakdown(
                    inputTokens: 300_000,
                    cachedInputTokens: 0,
                    cacheWriteInputTokens: 0,
                    outputTokens: 100_000,
                    reasoningOutputTokens: 80_000,
                    totalTokens: 400_000
                ),
                context: context(
                    model: "gpt-5.6-terra",
                    provider: "openai",
                    tier: "fast"
                ),
                at: date("2026-08-20T12:00:00Z")
            )
        )

        XCTAssertEqual(estimate.amountUSD, Decimal(string: "3"))
        XCTAssertEqual(estimate.precision, .exact)
    }

    func testProviderUnknownRequiresUniqueAlias() throws {
        let duplicatedAlias = [
            model(
                id: "xai-shared",
                provider: "xai",
                aliases: ["shared-model"],
                source: .modelsDev,
                standard: price(input: 1, cached: 0.1, write: nil, output: 2)
            ),
            model(
                id: "moonshot-shared",
                provider: "moonshot",
                aliases: ["shared-model"],
                source: .modelsDev,
                standard: price(input: 3, cached: 0.3, write: nil, output: 6)
            ),
            requiredTerra()
        ]
        let card = try manifest(models: duplicatedAlias).validated()

        XCTAssertNil(
            card.cost(
                for: breakdown(cacheWrite: 0),
                context: context(model: "shared-model", provider: nil),
                at: date("2026-08-20T12:00:00Z")
            )
        )
        XCTAssertNotNil(
            card.cost(
                for: breakdown(cacheWrite: 0),
                context: context(model: "shared-model", provider: "xai"),
                at: date("2026-08-20T12:00:00Z")
            )
        )
    }

    func testHistoricalOpenAIVersionAndPreCaptureModelsDevFallback() throws {
        let oldVersion = APIPriceVersion(
            id: "old",
            effectiveAt: "2026-07-01T00:00:00Z",
            models: [
                model(
                    id: "openai-gpt-5.6-terra",
                    provider: "openai",
                    aliases: ["gpt-5.6-terra"],
                    standard: price(input: 1, cached: 0.1, write: 0, output: 2)
                )
            ]
        )
        let currentVersion = APIPriceVersion(
            id: "current",
            effectiveAt: "2026-08-01T00:00:00Z",
            models: [
                model(
                    id: "openai-gpt-5.6-terra",
                    provider: "openai",
                    aliases: ["gpt-5.6-terra"],
                    standard: price(input: 2, cached: 0.2, write: 0, output: 4)
                ),
                model(
                    id: "modelsdev-xai-grok",
                    provider: "xai",
                    aliases: ["grok-current"],
                    source: .modelsDev,
                    firstCapturedAt: "2026-08-10T00:00:00Z",
                    standard: price(input: 3, cached: 0.3, write: 0, output: 6)
                )
            ]
        )
        let card = try APIPriceManifest(
            schema: 1,
            currentVersion: "current",
            generatedAt: "2026-08-20T00:00:00Z",
            sources: ["fixture"],
            versions: [oldVersion, currentVersion]
        ).validated()

        let historical = try XCTUnwrap(
            card.cost(
                for: breakdown(cacheWrite: 0),
                context: context(model: "gpt-5.6-terra", provider: "openai"),
                at: date("2026-07-20T00:00:00Z")
            )
        )
        let current = try XCTUnwrap(
            card.cost(
                for: breakdown(cacheWrite: 0),
                context: context(model: "gpt-5.6-terra", provider: "openai"),
                at: date("2026-08-20T00:00:00Z")
            )
        )
        let preCapture = try XCTUnwrap(
            card.cost(
                for: breakdown(cacheWrite: 0),
                context: context(model: "grok-current", provider: "xai"),
                at: date("2026-07-20T00:00:00Z")
            )
        )
        XCTAssertEqual(historical.modelPriceID, "openai-gpt-5.6-terra")
        XCTAssertEqual(historical.amountUSD * 2, current.amountUSD)
        XCTAssertEqual(historical.precision, .exact)
        XCTAssertEqual(preCapture.priceVersion, "current")
        XCTAssertEqual(preCapture.precision, .approximate)
    }

    func testBundledManifestDecodesAndValidates() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repository = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let url = repository.appendingPathComponent(
            "Sources/CodexToolbox/Resources/api-price-card-v1.json"
        )
        let decoded = try JSONDecoder().decode(
            APIPriceManifest.self,
            from: Data(contentsOf: url)
        )

        XCTAssertNoThrow(try decoded.validated())
        XCTAssertEqual(decoded.activeVersion?.models.count, 8)
    }

    func testLegacyUsageSummaryWithoutCostFieldsStillDecodes() throws {
        let data = Data(
            """
            {
              "dateKey":"2026-08-20",
              "totalTokens":10,
              "tasks":[{
                "dateKey":"2026-08-20",
                "rootTaskID":"task",
                "title":"Legacy",
                "tokens":10,
                "descendantCount":0
              }],
              "isComplete":true
            }
            """.utf8
        )
        let summary = try JSONDecoder().decode(DailyUsageSummary.self, from: data)

        XCTAssertNil(summary.totalCostUSD)
        XCTAssertEqual(summary.pricedTokens, 0)
        XCTAssertEqual(summary.tasks.first?.pricedTokens, 0)
    }

    private func manifest(models: [APIModelPrice]) -> APIPriceManifest {
        APIPriceManifest(
            schema: 1,
            currentVersion: "current",
            generatedAt: "2026-08-20T00:00:00Z",
            sources: ["fixture"],
            versions: [
                APIPriceVersion(
                    id: "current",
                    effectiveAt: "2026-08-01T00:00:00Z",
                    models: models.contains { $0.providerID == "openai" && $0.aliases.contains("gpt-5.6-terra") }
                        ? models
                        : models + [requiredTerra()]
                )
            ]
        )
    }

    private func model(
        id: String,
        provider: String,
        aliases: [String],
        source: APIPriceSourceKind = .openAIOfficial,
        firstCapturedAt: String? = nil,
        standard: APITokenPrice,
        priority: APITokenPrice? = nil,
        tiers: [APIContextPriceTier] = []
    ) -> APIModelPrice {
        APIModelPrice(
            id: id,
            providerID: provider,
            aliases: aliases,
            source: source,
            sourceUpdatedAt: "2026-08-20",
            firstCapturedAt: firstCapturedAt,
            standard: standard,
            priority: priority,
            contextTiers: tiers
        )
    }

    private func requiredTerra() -> APIModelPrice {
        model(
            id: "openai-gpt-5.6-terra",
            provider: "openai",
            aliases: ["gpt-5.6-terra"],
            standard: price(input: 1, cached: 0.1, write: 0, output: 2)
        )
    }

    private func price(
        input: Decimal,
        cached: Decimal?,
        write: Decimal?,
        output: Decimal
    ) -> APITokenPrice {
        APITokenPrice(
            inputUSDPerMillion: input,
            cachedInputUSDPerMillion: cached,
            cacheWriteUSDPerMillion: write,
            outputUSDPerMillion: output
        )
    }

    private func breakdown(cacheWrite: Int64? = 100_000) -> UsageTokenBreakdown {
        UsageTokenBreakdown(
            inputTokens: 1_000_000,
            cachedInputTokens: 200_000,
            cacheWriteInputTokens: cacheWrite,
            outputTokens: 300_000,
            reasoningOutputTokens: 200_000,
            totalTokens: 1_300_000
        )
    }

    private func context(
        model: String,
        provider: String?,
        tier: String = "standard"
    ) -> UsageExecutionContext {
        UsageExecutionContext(
            modelID: model,
            reasoningEffort: "high",
            serviceTier: tier,
            modelProviderID: provider
        )
    }

    private func date(_ value: String) -> Date {
        try! Date(value, strategy: .iso8601)
    }
}
