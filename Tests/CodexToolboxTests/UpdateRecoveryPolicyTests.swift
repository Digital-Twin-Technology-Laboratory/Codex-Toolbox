import Foundation
import XCTest
@testable import CodexToolboxCore

final class UpdateRecoveryPolicyTests: XCTestCase {
    private let offline = URLError(.notConnectedToInternet)

    func testManualTransientFailureRetriesTwiceThenPresentsChineseError() {
        XCTAssertEqual(
            UpdateRecoveryPolicy.action(
                origin: .userInitiated,
                completedRetries: 0,
                error: offline
            ),
            .retry(after: .seconds(2))
        )
        XCTAssertEqual(
            UpdateRecoveryPolicy.action(
                origin: .userInitiated,
                completedRetries: 1,
                error: offline
            ),
            .retry(after: .seconds(5))
        )
        XCTAssertEqual(
            UpdateRecoveryPolicy.action(
                origin: .userInitiated,
                completedRetries: 2,
                error: offline
            ),
            .present("暂时无法连接更新服务器，请检查网络或代理后重试。")
        )
    }

    func testScheduledTransientFailureRetriesOnceThenPreservesState() {
        XCTAssertEqual(
            UpdateRecoveryPolicy.action(
                origin: .scheduled,
                completedRetries: 0,
                error: offline
            ),
            .retry(after: .seconds(30))
        )
        XCTAssertEqual(
            UpdateRecoveryPolicy.action(
                origin: .scheduled,
                completedRetries: 1,
                error: offline
            ),
            .preservePreviousState
        )
    }

    func testNonNetworkFailureIsPresentedWithoutRetry() {
        XCTAssertEqual(
            UpdateRecoveryPolicy.action(
                origin: .userInitiated,
                completedRetries: 0,
                error: NSError(domain: "SUSparkleErrorDomain", code: 1)
            ),
            .present("无法完成更新检查，请稍后重试。")
        )
    }
}
