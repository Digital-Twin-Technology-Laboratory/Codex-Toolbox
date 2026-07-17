import Foundation
import XCTest
@testable import CodexToolboxCore

final class ResetCreditsClientTests: XCTestCase, @unchecked Sendable {
    func testSanitizesOpaqueIDsAndUsesAvailableCountAsAuthority() async throws {
        let response: [String: Any] = [
            "rateLimitResetCredits": [
                "availableCount": 3,
                "credits": [
                    [
                        "id": "opaque-secret-one",
                        "resetType": "weekly",
                        "status": "expired",
                        "grantedAt": 1_700_000_000,
                        "expiresAt": 1_710_000_000,
                        "title": "Expired",
                        "description": "No longer available"
                    ],
                    [
                        "creditId": "opaque-secret-two",
                        "resetType": "weekly",
                        "status": "available",
                        "grantedAt": "2026-07-01T00:00:00Z",
                        "expiresAt": "2026-07-20T00:00:00Z",
                        "title": "Reset card",
                        "description": "One reset"
                    ]
                ]
            ]
        ]
        let transport = RecordingTransport(response: jsonData(response))
        let fetchedAt = Date(timeIntervalSince1970: 123)
        let client = ResetCreditsClient(transport: transport, now: { fetchedAt })

        let snapshot = try await client.readResetCredits()

        XCTAssertEqual(snapshot.availableCount, 3)
        XCTAssertEqual(snapshot.credits.count, 2)
        XCTAssertTrue(snapshot.credits.first?.isAvailable == true)
        XCTAssertEqual(snapshot.fetchedAt, fetchedAt)
        let requestedMethods = await transport.methods
        XCTAssertEqual(
            requestedMethods,
            [ProcessCodexAppServerTransport.allowedMethod]
        )
        let encoded = String(decoding: try JSONEncoder().encode(snapshot), as: UTF8.self)
        XCTAssertFalse(encoded.contains("opaque-secret"))
        XCTAssertFalse(encoded.contains("creditId"))
    }

    func testCacheContainsOnlySanitizedSnapshotFields() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cacheURL = directory.appendingPathComponent("reset-credits.json")
        let snapshot = ResetCreditsSnapshot(
            availableCount: 1,
            credits: [
                ResetCreditSummary(
                    resetType: "daily",
                    status: "available",
                    grantedAt: Date(timeIntervalSince1970: 1),
                    expiresAt: Date(timeIntervalSince1970: 2),
                    title: "Card",
                    description: "Description"
                )
            ],
            fetchedAt: Date(timeIntervalSince1970: 3)
        )
        let store = ResetCreditsCacheStore(fileURL: cacheURL)

        try await store.save(snapshot)
        let restored = try await store.load()

        XCTAssertEqual(restored, snapshot)
        let text = try String(contentsOf: cacheURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"schemaVersion\" : 1"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("creditId"))
    }

    func testTransportRejectsConsumeWithoutLaunchingAProcess() async throws {
        let transport = ProcessCodexAppServerTransport(
            executableURL: URL(fileURLWithPath: "/usr/bin/false")
        )

        do {
            _ = try await transport.request(method: "account/rateLimitResetCredit/consume")
            XCTFail("consume method must never be sent")
        } catch let error as ResetCreditsError {
            XCTAssertEqual(error, .disallowedMethod("account/rateLimitResetCredit/consume"))
        }
    }

    func testProcessTransportCompletesInitializationHandshake() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("fake-codex")
        let handshakeTranscript = directory.appendingPathComponent("handshake.jsonl")
        let script = """
        #!/bin/sh
        IFS= read -r initialize
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r request
        printf '%s\\n%s\\n' "$initialized" "$request" > '\(handshakeTranscript.path)'
        printf '%s\\n' '{"id":2,"result":{"rateLimitResetCredits":{"availableCount":1,"credits":[]}}}'
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let transport = ProcessCodexAppServerTransport(executableURL: executable, timeout: 2)
        let client = ResetCreditsClient(transport: transport)

        let snapshot = try await client.readResetCredits()

        XCTAssertEqual(snapshot.availableCount, 1)
        XCTAssertTrue(snapshot.credits.isEmpty)
        let transcript = try String(contentsOf: handshakeTranscript, encoding: .utf8)
        let methods = try transcript.split(separator: "\n").compactMap { line -> String? in
            let object = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            return object?["method"] as? String
        }
        XCTAssertEqual(methods, ["initialized", "account/rateLimits/read"])
    }

    func testProcessTransportReportsTimeout() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("slow-codex")
        try Data("#!/bin/sh\nsleep 2\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let transport = ProcessCodexAppServerTransport(executableURL: executable, timeout: 0.1)

        do {
            _ = try await transport.request(method: ProcessCodexAppServerTransport.allowedMethod)
            XCTFail("request should time out")
        } catch let error as ResetCreditsError {
            XCTAssertEqual(error, .timeout)
        }
    }

    func testClientPreservesTypedRecoveryErrors() async throws {
        for expected in [
            ResetCreditsError.notLoggedIn("login required"),
            ResetCreditsError.protocolIncompatible("unexpected response"),
            ResetCreditsError.timeout
        ] {
            let client = ResetCreditsClient(transport: RecordingTransport(error: expected))
            do {
                _ = try await client.readResetCredits()
                XCTFail("expected typed error")
            } catch let actual as ResetCreditsError {
                XCTAssertEqual(actual, expected)
            }
        }
    }

    private func jsonData(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ResetCreditsClientTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor RecordingTransport: CodexAppServerRequesting {
    private let response: Data?
    private let error: ResetCreditsError?
    private(set) var methods: [String] = []

    init(response: Data) {
        self.response = response
        error = nil
    }

    init(error: ResetCreditsError) {
        response = nil
        self.error = error
    }

    func request(method: String) throws -> Data {
        methods.append(method)
        if let error { throw error }
        return response ?? Data()
    }
}
