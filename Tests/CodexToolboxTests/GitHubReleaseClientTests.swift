import Foundation
import XCTest
@testable import CodexToolboxCore

final class GitHubReleaseClientTests: XCTestCase {
    override func tearDown() {
        ReleaseURLProtocolStub.handler = nil
        super.tearDown()
    }

    func testMalformedVersionsAreRejectedWithoutCrashing() {
        let url = URL(string: "https://github.test/example/releases")!
        let current = AppRelease(version: "1.4.0", pageURL: url, publishedAt: nil)
        for malformed in ["", " ", "v", "-", "+metadata", "1..2.3", "1.x.2.3", "1.2", "1.2.3.4", "1.2.3-", "1.2.3+"] {
            XCTAssertFalse(AppRelease(version: malformed, pageURL: url, publishedAt: nil).isNewer(than: "1.0.0"), malformed)
            XCTAssertFalse(current.isNewer(than: malformed), malformed)
        }
    }

    func testReleaseAndPrereleaseOrderingIgnoresBuildMetadata() {
        let url = URL(string: "https://github.test/example/releases")!
        XCTAssertTrue(AppRelease(version: "v1.4.0", pageURL: url, publishedAt: nil).isNewer(than: "1.4.0-rc.2"))
        XCTAssertTrue(AppRelease(version: "1.4.0-rc.10", pageURL: url, publishedAt: nil).isNewer(than: "1.4.0-rc.2"))
        XCTAssertFalse(AppRelease(version: "1.4.0+56", pageURL: url, publishedAt: nil).isNewer(than: "1.4.0+55"))
    }

    func testChecksLatestOfficialReleaseAndComparesSemanticVersions() async throws {
        ReleaseURLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-GitHub-Api-Version"), "2022-11-28")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            let body = #"{"tag_name":"v1.1.0","html_url":"https://github.com/example/releases/tag/v1.1.0","published_at":"2026-07-20T04:00:00Z"}"#
            return (response, Data(body.utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseURLProtocolStub.self]
        let client = GitHubReleaseClient(
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://api.github.test/releases/latest")!
        )

        let release = try await client.latestRelease()

        XCTAssertEqual(release.version, "1.1.0")
        XCTAssertTrue(release.isNewer(than: "1.0.0"))
        XCTAssertFalse(release.isNewer(than: "1.1.0"))
        XCTAssertTrue(AppRelease(version: "1.0.0", pageURL: release.pageURL, publishedAt: nil)
            .isNewer(than: "1.0.0-beta.2"))
    }

    func testMapsMissingOfficialRelease() async {
        ReleaseURLProtocolStub.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseURLProtocolStub.self]
        let client = GitHubReleaseClient(
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://api.github.test/releases/latest")!
        )

        do {
            _ = try await client.latestRelease()
            XCTFail("Expected the update check to report a missing release")
        } catch let error as ReleaseCheckError {
            XCTAssertEqual(error, .unavailable(404))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testFallsBackToLatestReleaseWebRedirectWhenAPIRateLimited() async throws {
        let fallbackURL = URL(string: "https://github.test/example/releases/latest")!
        ReleaseURLProtocolStub.handler = { request in
            if request.url?.host == "api.github.test" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 403, httpVersion: nil, headerFields: nil)!,
                    Data()
                )
            }
            XCTAssertEqual(request.url, fallbackURL)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "text/html")
            let finalURL = URL(string: "https://github.test/example/releases/tag/v1.2.3")!
            return (
                HTTPURLResponse(url: finalURL, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data()
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReleaseURLProtocolStub.self]
        let client = GitHubReleaseClient(
            session: URLSession(configuration: configuration),
            endpoint: URL(string: "https://api.github.test/releases/latest")!,
            releasePageEndpoint: fallbackURL
        )

        let release = try await client.latestRelease()

        XCTAssertEqual(release.version, "1.2.3")
        XCTAssertEqual(release.pageURL.absoluteString, "https://github.test/example/releases/tag/v1.2.3")
    }
}

private final class ReleaseURLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: ReleaseCheckError.invalidResponse)
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
