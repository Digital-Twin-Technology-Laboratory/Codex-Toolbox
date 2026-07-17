import XCTest
@testable import ShowCodexIQCore

final class MetricFormatterTests: XCTestCase {
    func testMetricFormatting() {
        XCTAssertEqual(MetricFormatter.detailValue(105, metric: .iq), "105")
        XCTAssertEqual(MetricFormatter.detailValue(2.429979, metric: .cost), "$2.43")
        XCTAssertEqual(MetricFormatter.detailValue(1_955, metric: .duration), "33 分钟")
        XCTAssertEqual(MetricFormatter.detailValue(82.25, metric: .overall), "82.3")
        XCTAssertEqual(MetricFormatter.menuBarValue(5_103, metric: .duration), "1.4h")
        XCTAssertEqual(MetricFormatter.compactModelName("GPT-5.6 Sol xhigh"), "5.6 Sol xh")
    }

    func testBenchmarkDateFormatting() {
        XCTAssertEqual(MetricFormatter.benchmarkDateLabel("2026-07-13-pm"), "2026-07-13 · PM")
        XCTAssertEqual(MetricFormatter.benchmarkDateLabel("2026-07-13-am_2"), "2026-07-13 · AM")
        XCTAssertEqual(
            MetricFormatter.benchmarkDateLabel("2026-07-17T13:03:49+08:00"),
            "2026-07-17 · 13:03:49"
        )
        XCTAssertEqual(
            MetricFormatter.benchmarkDateLabel("2026-07-17T07:03:49.123Z"),
            "2026-07-17 · 07:03:49"
        )
        XCTAssertEqual(
            MetricFormatter.benchmarkDateLabel("2026-07-17T00:00:00Z"),
            "2026-07-17 · 00:00:00"
        )
        XCTAssertEqual(
            MetricFormatter.benchmarkDateLabel("2026-07-17T12:00:00Z"),
            "2026-07-17 · 12:00:00"
        )
        XCTAssertEqual(
            MetricFormatter.benchmarkDateLabel(
                "2026-07-17T13:03:49+08:00",
                includesDetailedTime: false
            ),
            "2026-07-17 · PM"
        )
        XCTAssertEqual(MetricFormatter.benchmarkDateLabel("2026-07-17T24:03:49Z"), "2026-07-17")
        XCTAssertEqual(MetricFormatter.benchmarkDateLabel("2026-07-13"), "2026-07-13")
        XCTAssertEqual(MetricFormatter.benchmarkDateLabel("unknown"), "unknown")
    }
}
