import Foundation
import XCTest
@testable import CodexToolboxCore

final class BoundedDownloadTests: XCTestCase, @unchecked Sendable {
    override func tearDown() { DownloadProtocol.mode = .valid; super.tearDown() }

    func testOversizedDeclaredAndStreamingBodiesPreserveLastKnownRecommendation() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let repository = StationRecommendationRepository(
            client: URLSessionStationRecommendationClient(session: session), store: DownloadStore()
        )
        let valid = await repository.refresh()
        XCTAssertEqual(valid.snapshot?.mode, "valid")
        for mode in [DownloadProtocol.Mode.declaredOversize, .streamingOversize] {
            DownloadProtocol.mode = mode
            let began = ContinuousClock.now
            do {
                _ = try await BoundedHTTPResponse.data(for: URLRequest(url: URL(string: "https://example.invalid/feed")!), session: session, maximumBytes: 4 * 1024 * 1024)
                XCTFail("An oversized response must be rejected before decoding")
            } catch let error as BoundedHTTPResponse.Failure {
                guard case .oversized = error else { return XCTFail("Unexpected bounded download failure") }
            }
            XCTAssertLessThan(began.duration(to: .now), .seconds(2))
            let result = await repository.refresh()
            XCTAssertEqual(result.snapshot, valid.snapshot)
            XCTAssertTrue(result.isStale)
        }
    }

    func testCancelledDownloadDoesNotWaitForServerCompletion() async throws {
        DownloadProtocol.mode = .neverCompletes
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DownloadProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let client = URLSessionStationRecommendationClient(session: session)
        let task = Task { try await client.fetch(cacheValidators: nil) }
        try await Task.sleep(for: .milliseconds(50))
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
    }
}

private actor DownloadStore: StationRecommendationStoring {
    private var snapshot: StationRecommendationSnapshot?
    func load() async throws -> StationRecommendationSnapshot? { snapshot }
    func save(_ snapshot: StationRecommendationSnapshot) async throws { self.snapshot = snapshot }
}

private final class DownloadProtocol: URLProtocol, @unchecked Sendable {
    enum Mode { case valid, declaredOversize, streamingOversize, neverCompletes }
    nonisolated(unsafe) static var mode = Mode.valid
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode = Self.mode
        let headers = mode == .declaredOversize ? ["Content-Length": "999999999"] : [:]
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        switch mode {
        case .valid:
            client?.urlProtocol(self, didLoad: Data(#"{"schema":1,"mode":"valid","recommendations":[{"key":"daily_development","items":[{"model":"test","effort":"high"}]}]}"#.utf8))
        case .declaredOversize:
            client?.urlProtocol(self, didLoad: Data([32]))
        case .neverCompletes: return
        case .streamingOversize:
            let chunk = Data(repeating: 32, count: 1024 * 1024)
            for _ in 0..<5 { client?.urlProtocol(self, didLoad: chunk) }
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
