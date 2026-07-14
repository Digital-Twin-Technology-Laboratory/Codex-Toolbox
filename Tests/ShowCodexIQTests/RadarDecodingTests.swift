import Foundation
import XCTest
@testable import ShowCodexIQCore

final class RadarDecodingTests: XCTestCase {
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
