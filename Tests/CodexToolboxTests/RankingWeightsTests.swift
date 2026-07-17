import XCTest
@testable import CodexToolboxCore

final class RankingWeightsTests: XCTestCase {
    func testPartitionBoundariesProduceValidWeights() {
        let weights = RankingWeights(firstBoundary: 62, secondBoundary: 81)

        XCTAssertEqual(weights, RankingWeights(iq: 62, cost: 19, duration: 19))
        XCTAssertTrue(weights.isValid)
        XCTAssertEqual(weights.firstBoundary, 62)
        XCTAssertEqual(weights.secondBoundary, 81)
    }

    func testPartitionBoundariesClampAtTrackEdgesAndDoNotCross() {
        let belowRange = RankingWeights(firstBoundary: -10, secondBoundary: -5)
        let crossed = RankingWeights(firstBoundary: 70, secondBoundary: 40)
        let aboveRange = RankingWeights(firstBoundary: 110, secondBoundary: 120)

        XCTAssertEqual(belowRange, RankingWeights(iq: 0, cost: 0, duration: 100))
        XCTAssertEqual(crossed, RankingWeights(iq: 70, cost: 0, duration: 30))
        XCTAssertEqual(aboveRange, RankingWeights(iq: 100, cost: 0, duration: 0))
        XCTAssertTrue(belowRange.isValid)
        XCTAssertTrue(crossed.isValid)
        XCTAssertTrue(aboveRange.isValid)
    }
}
