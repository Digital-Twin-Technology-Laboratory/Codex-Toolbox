import Foundation
import XCTest
@testable import CodexToolboxCore

final class RadarDecodingTests: XCTestCase {
    func testDecodesPublishedEfficiencySnapshotAndMapsWebsiteMetrics() throws {
        let data = try Data(contentsOf: try fixtureURL("intelligence-efficiency-v2.json"))
        let response = try JSONDecoder().decode(IntelligenceEfficiencyResponse.self, from: data)

        XCTAssertEqual(response.schema, 2)
        XCTAssertEqual(response.normalizedSourceUpdatedAt, "2026-08-02T13:23:26+08:00")
        XCTAssertEqual(response.benchmarks.count, 21)

        let solUltra = try XCTUnwrap(response.benchmarks.first { $0.id == "gpt_56_sol_ultra" })
        XCTAssertEqual(solUltra.label, "GPT-5.6 Sol ultra")
        XCTAssertEqual(solUltra.latest?.score, 107.1429)
        XCTAssertEqual(solUltra.latest?.costUSD, 19.392999)
        XCTAssertEqual(
            try XCTUnwrap(solUltra.latest?.wallSeconds),
            51.9899 * 60,
            accuracy: 0.000_001
        )
        XCTAssertEqual(solUltra.latest?.passed, 80)
        XCTAssertEqual(solUltra.latest?.tasks, 112)
        XCTAssertEqual(solUltra.recentDays.count, 2)
        XCTAssertEqual(solUltra.recentDays.first?.costUSD, 18.5)

        XCTAssertNotNil(response.benchmarks.first { $0.id == "gpt_56_sol_xhigh" })
        XCTAssertNotNil(response.benchmarks.first { $0.id == "gpt_56_terra_xhigh_distributed" })
        XCTAssertNotNil(response.benchmarks.first { $0.id == "gpt_55_xhigh_distributed" })
        XCTAssertNotNil(response.benchmarks.first { $0.id == "deepseek_v4_flash_max" })
    }

    func testPublishedSnapshotProducesExpectedTopRankings() throws {
        let data = try Data(contentsOf: try fixtureURL("intelligence-efficiency-v2.json"))
        let response = try JSONDecoder().decode(IntelligenceEfficiencyResponse.self, from: data)

        XCTAssertEqual(
            RankingEngine.rank(response.benchmarks, by: .iq).prefix(5).map(\.benchmark.label),
            [
                "GPT-5.6 Sol ultra",
                "GPT-5.6 Sol max",
                "GPT-5.6 Terra ultra",
                "GPT-5.6 Sol xhigh",
                "5.5 xhigh"
            ]
        )
        XCTAssertEqual(RankingEngine.rank(response.benchmarks, by: .cost).first?.benchmark.id, "gpt_56_luna_low")
        XCTAssertEqual(RankingEngine.rank(response.benchmarks, by: .cost).first?.value, 0.033288)
        XCTAssertEqual(RankingEngine.rank(response.benchmarks, by: .duration).first?.benchmark.id, "gpt_56_luna_low")
        XCTAssertEqual(
            try XCTUnwrap(RankingEngine.rank(response.benchmarks, by: .duration).first?.value),
            5.2178 * 60,
            accuracy: 0.000_001
        )
    }

    func testEfficiencySnapshotSkipsInvalidPointsAndKeepsPartialMetrics() throws {
        let json = #"{"schema":2,"source_updated_at":"2026-08-02T13:23:26+08:00","points":[{"model":"future-model","effort":"ultra","iq":120},{"model":"broken","effort":"high","iq":"not-a-number"},{"model":"","effort":"low","iq":10}]}"#
        let response = try JSONDecoder().decode(
            IntelligenceEfficiencyResponse.self,
            from: Data(json.utf8)
        )

        XCTAssertEqual(response.benchmarks.count, 1)
        XCTAssertEqual(response.benchmarks[0].id, "future_model_ultra")
        XCTAssertEqual(response.benchmarks[0].label, "future-model ultra")
        XCTAssertEqual(RankingEngine.rank(response.benchmarks, by: .iq).count, 1)
        XCTAssertTrue(RankingEngine.rank(response.benchmarks, by: .cost).isEmpty)
        XCTAssertTrue(RankingEngine.rank(response.benchmarks, by: .duration).isEmpty)
        XCTAssertTrue(RankingEngine.rank(response.benchmarks, by: .overall).isEmpty)
    }

    func testEfficiencyHistoryIsChronologicalEvenWhenSourceOrderIsNot() throws {
        let json = #"{"schema":2,"source_updated_at":"2026-08-02T13:23:26+08:00","points":[{"model":"gpt-5.6-sol","effort":"ultra","iq":107}],"history":[{"at":"2026-08-02T12:00:00+08:00","points":[{"model":"gpt-5.6-sol","effort":"ultra","iq":106}]},{"at":"2026-08-01T12:00:00+08:00","points":[{"model":"gpt-5.6-sol","effort":"ultra","iq":105}]}]}"#
        let response = try JSONDecoder().decode(
            IntelligenceEfficiencyResponse.self,
            from: Data(json.utf8)
        )

        let benchmark = try XCTUnwrap(response.benchmarks.first)
        XCTAssertEqual(
            benchmark.recentDays.map(\.date),
            ["2026-08-01T12:00:00+08:00", "2026-08-02T12:00:00+08:00"]
        )
    }

    func testDecodesCurrentSchemaAndIgnoresUnknownFields() throws {
        let data = try Data(contentsOf: try fixtureURL("current-v2.json"))
        let response = try JSONDecoder().decode(RadarResponse.self, from: data)

        XCTAssertEqual(response.schemaVersion, "2.0")
        XCTAssertEqual(response.benchmarks.map(\.id), [
            "gpt_56_luna_medium",
            "gpt_56_sol_low",
            "gpt_56_sol_xhigh"
        ])
        XCTAssertEqual(response.benchmarks.last?.latest?.score, 105)
        XCTAssertEqual(response.benchmarks.last?.latest?.costUSD, 33.626661)
        XCTAssertNil(response.benchmarks.last?.recentDays.first?.costUSD)
    }

    func testMissingComparisonsDecodesAsEmpty() throws {
        let data = Data(#"{"schema_version":"3.0","model_iq":{}}"#.utf8)
        let response = try JSONDecoder().decode(RadarResponse.self, from: data)

        XCTAssertEqual(response.schemaVersion, "3.0")
        XCTAssertTrue(response.benchmarks.isEmpty)
    }

    func testMissingMetricDoesNotDropBenchmark() throws {
        let json = #"{"schema_version":"2.0","model_iq":{"comparisons":{"future":{"label":"Future","model":"future","reasoning_effort":"high","latest":{"date":"2026-07-13","score":null,"wall_seconds":42}}}}}"#
        let response = try JSONDecoder().decode(RadarResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.benchmarks.count, 1)
        XCTAssertNil(response.benchmarks[0].latest?.score)
        XCTAssertEqual(response.benchmarks[0].latest?.wallSeconds, 42)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "Fixtures"
        )
        #else
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: nil)
        #endif
        guard let url else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}
