import XCTest
@testable import CodexToolboxCore

final class SmokeTests: XCTestCase {
    func testApplicationMetadata() {
        XCTAssertEqual(AppMetadata.displayName, "Codex Toolbox")
        XCTAssertEqual(AppMetadata.bundleIdentifier, "io.github.zzzzzzjw.ShowCodexIQ")
        XCTAssertEqual(
            AppMetadata.version(in: ["CodexToolboxReleaseVersion": "1.0.0"]),
            "1.0.0"
        )
        XCTAssertEqual(
            AppMetadata.version(in: ["ShowCodexIQReleaseVersion": "0.2.0-beta.2"]),
            "0.2.0-beta.2"
        )
        XCTAssertEqual(
            AppMetadata.version(in: ["CFBundleShortVersionString": "0.2.0"]),
            "0.2.0"
        )
        XCTAssertEqual(AppMetadata.version(in: nil), "0.0.0-dev")
        XCTAssertEqual(AppMetadata.build(in: ["CFBundleVersion": "7"]), "7")
        XCTAssertEqual(AppMetadata.build(in: nil), "0")
    }
}
