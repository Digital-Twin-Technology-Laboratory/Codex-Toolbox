import Foundation
import XCTest
@testable import CodexToolboxCore

final class RadarClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testSendsCacheValidatorsAndDecodesPayload() async throws {
        let payload = try Data(contentsOf: try fixtureURL("intelligence-efficiency-v2.json"))
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "old-etag")
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-Modified-Since"), "old-date")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["ETag": "new-etag", "Last-Modified": "new-date"]
            )!
            return (response, payload)
        }
        let client = makeClient()

        let result = try await client.fetch(
            cacheValidators: CacheValidators(etag: "old-etag", lastModified: "old-date")
        )

        guard case let .modified(snapshot) = result else {
            return XCTFail("Expected a modified response")
        }
        XCTAssertEqual(snapshot.schemaVersion, "intelligence-efficiency/2")
        XCTAssertEqual(snapshot.sourceMonitoredAt, "2026-08-02T13:23:26+08:00")
        XCTAssertEqual(snapshot.benchmarks.count, 21)
        XCTAssertEqual(snapshot.validators.etag, "new-etag")
    }

    func testRejectsUnsupportedEfficiencySchema() async {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [:]
            )!
            return (
                response,
                Data(#"{"schema":3,"source_updated_at":"2026-08-02T13:23:26+08:00","points":[]}"#.utf8)
            )
        }

        do {
            _ = try await makeClient().fetch(cacheValidators: nil)
            XCTFail("Expected the request to fail")
        } catch let error as RadarClientError {
            guard case let .invalidPayload(message) = error else {
                return XCTFail("Expected invalid payload, got \(error)")
            }
            XCTAssertTrue(message.contains("3"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRejectsSnapshotWithoutUsablePoints() async {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [:]
            )!
            return (
                response,
                Data(#"{"schema":2,"source_updated_at":"2026-08-02T13:23:26+08:00","points":[{"model":"","effort":"low","iq":10}]}"#.utf8)
            )
        }

        do {
            _ = try await makeClient().fetch(cacheValidators: nil)
            XCTFail("Expected the request to fail")
        } catch let error as RadarClientError {
            guard case let .invalidPayload(message) = error else {
                return XCTFail("Expected invalid payload, got \(error)")
            }
            XCTAssertTrue(message.contains("没有可用"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testHandlesNotModified() async throws {
        URLProtocolStub.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 304,
                httpVersion: nil,
                headerFields: [:]
            )!
            return (response, Data())
        }

        let result = try await makeClient().fetch(
            cacheValidators: CacheValidators(etag: "etag", lastModified: nil)
        )

        guard case let .notModified(validators) = result else {
            return XCTFail("Expected a not-modified response")
        }
        XCTAssertEqual(validators.etag, "etag")
    }

    func testMapsHTTPFailure() async {
        var requestCount = 0
        URLProtocolStub.handler = { request in
            requestCount += 1
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: [:]
            )!
            return (response, Data())
        }

        do {
            _ = try await makeClient().fetch(cacheValidators: nil)
            XCTFail("Expected the request to fail")
        } catch let error as RadarClientError {
            XCTAssertEqual(error, .httpStatus(503))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testRetriesTransientFailuresThenSucceeds() async throws {
        let payload = try Data(contentsOf: try fixtureURL("intelligence-efficiency-v2.json"))
        var requestCount = 0
        URLProtocolStub.handler = { request in
            requestCount += 1
            if requestCount < 3 {
                throw URLError(.notConnectedToInternet)
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [:]
            )!
            return (response, payload)
        }

        _ = try await makeClient(noDelay: true).fetch(cacheValidators: nil)

        XCTAssertEqual(requestCount, 3)
    }

    private func makeClient(noDelay: Bool = false) -> URLSessionRadarClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let sleep: @Sendable (Duration) async throws -> Void
        if noDelay {
            sleep = { _ in }
        } else {
            sleep = { duration in try await Task.sleep(for: duration) }
        }
        return URLSessionRadarClient(
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://example.test/current.json")!,
            sleep: sleep
        )
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

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: RadarClientError.invalidResponse)
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
