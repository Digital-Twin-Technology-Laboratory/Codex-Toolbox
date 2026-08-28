import Foundation
import XCTest
@testable import CodexToolboxCore

final class NetworkRecoveryPolicyTests: XCTestCase {
    func testClassifiesSupportedURLErrors() {
        XCTAssertEqual(NetworkRecoveryPolicy.failure(in: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(NetworkRecoveryPolicy.failure(in: URLError(.networkConnectionLost)), .connectionLost)
        XCTAssertEqual(NetworkRecoveryPolicy.failure(in: URLError(.timedOut)), .timedOut)
        XCTAssertEqual(NetworkRecoveryPolicy.failure(in: URLError(.cannotConnectToHost)), .cannotReachHost)
        XCTAssertEqual(NetworkRecoveryPolicy.failure(in: URLError(.cannotFindHost)), .cannotReachHost)
        XCTAssertEqual(NetworkRecoveryPolicy.failure(in: URLError(.dnsLookupFailed)), .cannotReachHost)
    }

    func testFindsTransientErrorInsideWrapper() {
        let wrapper = NSError(
            domain: "SUSparkleErrorDomain",
            code: 2_001,
            userInfo: [NSUnderlyingErrorKey: URLError(.networkConnectionLost)]
        )

        XCTAssertEqual(NetworkRecoveryPolicy.failure(in: wrapper), .connectionLost)
    }

    func testDoesNotClassifyCancellationOrApplicationErrors() {
        XCTAssertNil(NetworkRecoveryPolicy.failure(in: URLError(.cancelled)))
        XCTAssertNil(NetworkRecoveryPolicy.failure(in: RadarClientError.httpStatus(503)))
        XCTAssertNil(NetworkRecoveryPolicy.failure(in: RadarClientError.invalidPayload("bad")))
    }

    func testRetryDelaysAreBounded() {
        XCTAssertEqual(NetworkRecoveryPolicy.interactiveRetryDelay(after: 0), .seconds(2))
        XCTAssertEqual(NetworkRecoveryPolicy.interactiveRetryDelay(after: 1), .seconds(5))
        XCTAssertNil(NetworkRecoveryPolicy.interactiveRetryDelay(after: 2))
        XCTAssertEqual(NetworkRecoveryPolicy.backgroundRetryDelay(after: 0), .seconds(30))
        XCTAssertNil(NetworkRecoveryPolicy.backgroundRetryDelay(after: 1))
    }
}
