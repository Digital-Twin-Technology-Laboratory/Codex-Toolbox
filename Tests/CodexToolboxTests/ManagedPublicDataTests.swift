import Foundation
import XCTest
@testable import CodexToolboxCore

final class ManagedPublicDataTests: XCTestCase, @unchecked Sendable {
    override func tearDown() { OwnedProtocol.handler = nil; OwnedProtocol.headers = ["ETag": "owned"]; super.tearDown() }
    private func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [OwnedProtocol.self]
        return URLSession(configuration: config)
    }
    func testAllPublicEndpointsBelongToWebsite() {
        for url in [AppMetadata.radarJSONURL, AppMetadata.stationRecommendationsURL, AppMetadata.rateCardManifestURL, AppMetadata.apiPriceManifestURL] {
            XCTAssertEqual(url.host, "zjwspace.cn")
            XCTAssertTrue(url.path.hasPrefix("/api/codex-toolbox/v1/"))
        }
    }
    func testLegacyValidatorsDecodeWithoutLosingPayload() throws {
        let old = try JSONDecoder().decode(CacheValidators.self, from: Data(#"{"etag":"legacy","lastModified":"old"}"#.utf8))
        XCTAssertEqual(old.etag, "legacy"); XCTAssertNil(old.sourceURL)
    }
    func testRecommendationMigratesValidatorsThenUsesOwned304() async throws {
        let endpoint = AppMetadata.stationRecommendationsURL
        OwnedProtocol.handler = { request in
            XCTAssertEqual(request.url, endpoint)
            XCTAssertNil(request.value(forHTTPHeaderField: "If-None-Match"))
            XCTAssertNil(request.value(forHTTPHeaderField: "If-Modified-Since"))
            return (200, Data(#"{"schema":1,"mode":"test","managed":{"revision":1,"generation":1,"status":"upstream_error"},"recommendations":[{"key":"daily_development","items":[{"model":"gpt-future","effort":"high"}]}]}"#.utf8))
        }
        let client = URLSessionStationRecommendationClient(session: session())
        guard case let .modified(value) = try await client.fetch(cacheValidators: CacheValidators(etag: "legacy")) else { return XCTFail() }
        XCTAssertEqual(value.validators.sourceURL, endpoint.absoluteString)
        XCTAssertEqual(value.managed?.status, "upstream_error")
        OwnedProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "owned")
            return (304, Data())
        }
        guard case .notModified = try await client.fetch(cacheValidators: value.validators) else { return XCTFail() }
    }
    func testPriceClientsRejectUnsolicited304AndOnlySendMatchingValidators() async throws {
        for owned in [false, true] {
            OwnedProtocol.handler = { request in
                XCTAssertEqual(request.url?.host, "zjwspace.cn")
                XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), owned ? "owned" : nil)
                return (304, Data())
            }
            do {
                _ = try await URLSessionRateCardClient(session: session()).fetch(cacheValidators: CacheValidators(etag: "owned", sourceURL: owned ? AppMetadata.rateCardManifestURL.absoluteString : nil))
                XCTAssertTrue(owned)
            } catch { XCTAssertFalse(owned) }
            do {
                _ = try await URLSessionAPIPriceCardClient(session: session()).fetch(cacheValidators: CacheValidators(etag: "owned", sourceURL: owned ? AppMetadata.apiPriceManifestURL.absoluteString : nil))
                XCTAssertTrue(owned)
            } catch { XCTAssertFalse(owned) }
        }
    }
    func testSuccessfulResponseWithoutValidatorsDropsPreviousETag() async throws {
        OwnedProtocol.headers = [:]
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (name, endpoint) in [("codex-rate-card-v1.json", AppMetadata.rateCardManifestURL), ("api-price-card-v1.json", AppMetadata.apiPriceManifestURL)] {
            let data = try Data(contentsOf: root.appendingPathComponent("Sources/CodexToolbox/Resources/" + name))
            OwnedProtocol.handler = { _ in (200, data) }
            let old = CacheValidators(etag: "old", lastModified: "old", sourceURL: endpoint.absoluteString)
            let validators: CacheValidators
            if name.hasPrefix("codex") {
                guard case let .modified(_, v) = try await URLSessionRateCardClient(session: session()).fetch(cacheValidators: old) else { return XCTFail() }
                validators = v
            } else {
                guard case let .modified(_, v) = try await URLSessionAPIPriceCardClient(session: session()).fetch(cacheValidators: old) else { return XCTFail() }
                validators = v
            }
            XCTAssertNil(validators.etag); XCTAssertNil(validators.lastModified)
        }
        OwnedProtocol.handler = { _ in (200, Data(#"{"schema":1,"mode":"test","recommendations":[{"key":"daily_development","items":[{"model":"gpt-future","effort":"high"}]}]}"#.utf8)) }
        guard case let .modified(value) = try await URLSessionStationRecommendationClient(session: session()).fetch(cacheValidators: CacheValidators(etag: "old", sourceURL: AppMetadata.stationRecommendationsURL.absoluteString)) else { return XCTFail() }
        XCTAssertNil(value.validators.etag)
    }

    func testServerPricePayloadsUseExistingHistoryAndCalculations() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for (name, endpoint) in [("codex-rate-card-v1.json", AppMetadata.rateCardManifestURL), ("api-price-card-v1.json", AppMetadata.apiPriceManifestURL)] {
            let data = try Data(contentsOf: root.appendingPathComponent("Sources/CodexToolbox/Resources/" + name))
            OwnedProtocol.handler = { request in XCTAssertEqual(request.url, endpoint); return (200, data) }
            if name.hasPrefix("codex") {
                guard case let .modified(manifest, _) = try await URLSessionRateCardClient(session: session()).fetch(cacheValidators: nil) else { return XCTFail() }
                XCTAssertEqual(manifest, try JSONDecoder().decode(RateCardManifest.self, from: data))
            } else {
                guard case let .modified(manifest, _) = try await URLSessionAPIPriceCardClient(session: session()).fetch(cacheValidators: nil) else { return XCTFail() }
                XCTAssertEqual(manifest, try JSONDecoder().decode(APIPriceManifest.self, from: data))
            }
        }
    }
}

private final class OwnedProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var headers = ["ETag": "owned"]
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: Self.headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}
