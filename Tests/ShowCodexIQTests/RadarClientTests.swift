import Foundation
import XCTest
@testable import ShowCodexIQCore

final class RadarClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.handler = nil
        super.tearDown()
    }

    func testSendsCacheValidatorsAndDecodesPayload() async throws {
        let payload = try Data(contentsOf: try fixtureURL("current-v2.json"))
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
        XCTAssertEqual(snapshot.benchmarks.count, 3)
        XCTAssertEqual(snapshot.validators.etag, "new-etag")
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
        URLProtocolStub.handler = { request in
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
    }

    private func makeClient() -> URLSessionRadarClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSessionRadarClient(
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://example.test/current.json")!
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
