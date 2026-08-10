import Foundation
@testable import CodexToolboxCore
import XCTest

final class RateCardTests: XCTestCase {
    func testTokenCreditsExcludeCacheWritesAndDoNotDoubleReasoningOutput() throws {
        let estimate = try XCTUnwrap(
            manifest().credits(
                for: UsageTokenBreakdown(
                    inputTokens: 1_000,
                    cachedInputTokens: 400,
                    cacheWriteInputTokens: 100,
                    outputTokens: 200,
                    reasoningOutputTokens: 150,
                    totalTokens: 1_200
                ),
                context: UsageExecutionContext(
                    modelID: "gpt-5.6-sol",
                    reasoningEffort: "ultra",
                    serviceTier: "default",
                    planType: "pro",
                    hasAccountRateLimits: true
                ),
                mode: .automatic,
                at: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        XCTAssertEqual(estimate.credits, 0.2175, accuracy: 0.000_000_1)
        XCTAssertEqual(estimate.precision, .exact)
        XCTAssertEqual(estimate.rateCardVersion, "current")
    }

    func testFastUsesPublishedMultiplierAndMissingCacheWriteIsUpperBound() throws {
        let estimate = try XCTUnwrap(
            manifest().credits(
                for: UsageTokenBreakdown(
                    inputTokens: 1_000,
                    cachedInputTokens: 400,
                    cacheWriteInputTokens: nil,
                    outputTokens: 200,
                    reasoningOutputTokens: 0,
                    totalTokens: 1_200
                ),
                context: UsageExecutionContext(
                    modelID: "gpt-5.6-sol",
                    reasoningEffort: "high",
                    serviceTier: "priority",
                    planType: "pro",
                    hasAccountRateLimits: true
                ),
                mode: .automatic,
                at: Date(timeIntervalSince1970: 1_800_000_000)
            )
        )

        XCTAssertEqual(estimate.credits, 0.575, accuracy: 0.000_000_1)
        XCTAssertEqual(estimate.precision, .upperBound)
    }

    func testAutomaticRejectsAPIKeyAndUsesLegacyOnlyWhenPlanConfirmsIt() throws {
        let usage = UsageTokenBreakdown(
            inputTokens: 100,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 10,
            reasoningOutputTokens: 0,
            totalTokens: 110
        )
        let api = UsageExecutionContext(
            modelID: "gpt-5.6-sol",
            reasoningEffort: "high",
            serviceTier: "default",
            modelProviderID: "openai_api",
            planType: nil,
            hasAccountRateLimits: false
        )
        XCTAssertNil(manifest().credits(for: usage, context: api, mode: .automatic, at: Date()))
        XCTAssertNil(manifest().credits(for: usage, context: api, mode: .tokenBased, at: Date()))

        let unknownPlan = UsageExecutionContext(
            modelID: "gpt-5.6-sol",
            reasoningEffort: "high",
            serviceTier: "default",
            planType: nil,
            hasAccountRateLimits: true
        )
        XCTAssertNil(
            manifest().credits(
                for: usage,
                context: unknownPlan,
                mode: .automatic,
                at: Date()
            )
        )

        let legacy = UsageExecutionContext(
            modelID: "gpt-5.6-sol",
            reasoningEffort: "high",
            serviceTier: "default",
            planType: "legacy-pro",
            hasAccountRateLimits: true
        )
        let estimate = try XCTUnwrap(
            manifest().credits(for: usage, context: legacy, mode: .automatic, at: Date())
        )
        XCTAssertEqual(estimate.credits, 1.0)
        XCTAssertEqual(estimate.precision, .approximate)
    }

    func testEventTimeSelectsHistoricalRateAndUnknownModelsStayUnavailable() throws {
        let usage = UsageTokenBreakdown(
            inputTokens: 1_000_000,
            cachedInputTokens: 0,
            cacheWriteInputTokens: 0,
            outputTokens: 0,
            reasoningOutputTokens: 0,
            totalTokens: 1_000_000
        )
        let context = UsageExecutionContext(
            modelID: "gpt-5.6-sol",
            reasoningEffort: "high",
            serviceTier: "default",
            planType: "pro",
            hasAccountRateLimits: true
        )
        let old = try XCTUnwrap(
            manifest().credits(
                for: usage,
                context: context,
                mode: .tokenBased,
                at: try Date("2025-06-01T00:00:00Z", strategy: .iso8601)
            )
        )
        XCTAssertEqual(old.credits, 100)
        XCTAssertNil(
            manifest().credits(
                for: usage,
                context: UsageExecutionContext(
                    modelID: "future-model",
                    reasoningEffort: nil,
                    serviceTier: "default"
                ),
                mode: .tokenBased,
                at: Date()
            )
        )
    }

    func testParserTracksMidThreadModelEffortAndFastSwitches() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RateCardParser-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let rollout = directory.appendingPathComponent("switches.jsonl")
        let lines = [
            json([
                "timestamp": "2026-08-11T00:00:00Z",
                "type": "turn_context",
                "payload": ["model": "gpt-5.6-sol", "reasoning_effort": "high"]
            ]),
            tokenLine(timestamp: "2026-08-11T00:00:01Z", cumulative: 120, increment: 120),
            json([
                "timestamp": "2026-08-11T00:01:00Z",
                "type": "event_msg",
                "payload": [
                    "type": "thread_settings_applied",
                    "thread_settings": [
                        "model": "gpt-5.6-luna",
                        "reasoning_effort": "xhigh",
                        "service_tier": "priority"
                    ]
                ]
            ]),
            tokenLine(timestamp: "2026-08-11T00:01:01Z", cumulative: 240, increment: 120)
        ].joined(separator: "\n") + "\n"
        try Data(lines.utf8).write(to: rollout)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let parsed = try RolloutTokenParser.parse(
            fileURL: rollout,
            previous: nil,
            calendar: calendar,
            rateCard: manifest(),
            rateCardMode: .automatic
        )

        XCTAssertEqual(parsed.quotaObservations.count, 2)
        XCTAssertEqual(parsed.quotaObservations[0].executionContext?.modelID, "gpt-5.6-sol")
        XCTAssertEqual(parsed.quotaObservations[0].executionContext?.reasoningEffort, "high")
        XCTAssertEqual(parsed.quotaObservations[0].executionContext?.isFast, nil)
        XCTAssertEqual(parsed.quotaObservations[1].executionContext?.modelID, "gpt-5.6-luna")
        XCTAssertEqual(parsed.quotaObservations[1].executionContext?.reasoningEffort, "xhigh")
        XCTAssertEqual(parsed.quotaObservations[1].executionContext?.isFast, true)
        XCTAssertEqual(parsed.quotaObservations[1].executionContext?.rateCardMode, .automatic)
        XCTAssertEqual(parsed.quotaObservations[1].executionContext?.rateCardVersion, "current")
        XCTAssertNotNil(parsed.quotaObservations[1].creditEstimate)
    }

    private func manifest() -> RateCardManifest {
        RateCardManifest(
            schema: 1,
            currentVersion: "current",
            generatedAt: "2026-08-05T00:00:00Z",
            sources: ["https://help.openai.com/"],
            versions: [
                RateCardVersion(
                    id: "old",
                    effectiveAt: "2025-01-01T00:00:00Z",
                    models: [
                        ModelTokenRate(
                            id: "sol-old",
                            aliases: ["gpt-5.6-sol"],
                            inputCreditsPerMillion: 100,
                            cachedInputCreditsPerMillion: 10,
                            outputCreditsPerMillion: 600
                        )
                    ],
                    fastMultipliers: [],
                    legacyModels: []
                ),
                RateCardVersion(
                    id: "current",
                    effectiveAt: "2026-08-05T00:00:00Z",
                    models: [
                        ModelTokenRate(
                            id: "sol",
                            aliases: ["gpt-5.6-sol"],
                            inputCreditsPerMillion: 125,
                            cachedInputCreditsPerMillion: 12.5,
                            outputCreditsPerMillion: 750
                        ),
                        ModelTokenRate(
                            id: "luna",
                            aliases: ["gpt-5.6-luna"],
                            inputCreditsPerMillion: 5,
                            cachedInputCreditsPerMillion: 0.5,
                            outputCreditsPerMillion: 30
                        )
                    ],
                    fastMultipliers: [FastRateMultiplier(modelPrefix: "gpt-5.6", multiplier: 2.5)],
                    legacyModels: [
                        LegacyMessageRate(
                            id: "sol-legacy",
                            aliases: ["gpt-5.6-sol"],
                            creditsPerMessage: 1
                        )
                    ]
                )
            ]
        )
    }

    private func tokenLine(timestamp: String, cumulative: Int64, increment: Int64) -> String {
        json([
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": ["total_tokens": cumulative],
                    "last_token_usage": [
                        "input_tokens": increment,
                        "cached_input_tokens": increment / 2,
                        "cache_write_input_tokens": 0,
                        "output_tokens": increment / 3,
                        "reasoning_output_tokens": increment / 4,
                        "total_tokens": increment
                    ]
                ],
                "rate_limits": [
                    "plan_type": "pro",
                    "primary": [
                        "used_percent": 1,
                        "window_minutes": 300,
                        "resets_at": 1_800_000_000
                    ]
                ]
            ]
        ])
    }

    private func json(_ object: [String: Any]) -> String {
        String(
            decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            as: UTF8.self
        )
    }
}
