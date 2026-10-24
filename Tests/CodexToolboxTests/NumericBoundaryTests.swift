import Foundation
import XCTest
@testable import CodexToolboxCore

final class NumericBoundaryTests: XCTestCase, @unchecked Sendable {
    func testUnrepresentableDurationsUseExistingMissingValue() {
        for value in [1e20, Double.infinity, Double.nan, -1] {
            XCTAssertEqual(MetricFormatter.detailValue(value, metric: .duration), "—")
            XCTAssertEqual(MetricFormatter.menuBarValue(value, metric: .duration), "—")
        }
        XCTAssertEqual(MetricFormatter.detailValue(3_661, metric: .duration), "1 小时 1 分")
    }

    func testTokenComponentValidationDoesNotOverflowOrAcceptUnrepresentableTotals() {
        let cachedOverflow = UsageTokenBreakdown(inputTokens: .max, cachedInputTokens: .max,
            cacheWriteInputTokens: 1, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: .max)
        XCTAssertFalse(cachedOverflow.hasConsistentComponents)
        let totalOverflow = UsageTokenBreakdown(inputTokens: .max, cachedInputTokens: 0,
            cacheWriteInputTokens: 0, outputTokens: 1, reasoningOutputTokens: 0, totalTokens: .max)
        XCTAssertFalse(totalOverflow.hasConsistentComponents)
        let largestValid = UsageTokenBreakdown(inputTokens: .max, cachedInputTokens: .max,
            cacheWriteInputTokens: 0, outputTokens: 0, reasoningOutputTokens: 0, totalTokens: .max)
        XCTAssertTrue(largestValid.hasConsistentComponents)
    }

    func testUnrepresentableAccountResponsesAreRejectedBeforeReplacingHistory() async throws {
        let responses = [
            #"{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":1e20}}}"#,
            #"{"rateLimits":{"primary":{"usedPercent":1,"windowDurationMins":1e20,"resetsAt":1800000000}}}"#,
            #"{"rateLimitResetCredits":{"availableCount":1e20}}"#
        ]
        for response in responses {
            let client = ResetCreditsClient(transport: NumericBoundaryTransport(data: Data(response.utf8)))
            do {
                _ = try await client.readResetCredits()
                XCTFail("An unrepresentable response must be rejected")
            } catch let error as ResetCreditsError {
                guard case .protocolIncompatible = error else { return XCTFail("Unexpected error: \(error)") }
            }
        }
    }

    func testUnrepresentableQuotaDateCannotTrapOrBeDecodedFromCache() throws {
        let invalid = AccountQuotaWindow(durationMinutes: 300, usedPercent: 1, resetsAt: Date(timeIntervalSince1970: 1e20))
        XCTAssertEqual(invalid.id, "quota-window-300-invalid")
        let data = Data(#"{"durationMinutes":300,"usedPercent":1,"resetsAt":1e20}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        XCTAssertThrowsError(try decoder.decode(AccountQuotaWindow.self, from: data))
        XCTAssertEqual(AccountQuotaWindow(durationMinutes: 300, usedPercent: 1,
            resetsAt: Date(timeIntervalSince1970: 1_800_000_000)).id, "quota-window-300-1800000000")
    }
}

private struct NumericBoundaryTransport: CodexAppServerRequesting {
    let data: Data
    func request(method: String) async throws -> Data { data }
}
