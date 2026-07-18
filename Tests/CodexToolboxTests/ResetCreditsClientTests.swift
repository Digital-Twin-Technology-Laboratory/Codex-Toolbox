import Foundation
import XCTest
@testable import CodexToolboxCore

final class ResetCreditsClientTests: XCTestCase, @unchecked Sendable {
    func testSanitizesOpaqueIDsAndUsesAvailableCountAsAuthority() async throws {
        let response: [String: Any] = [
            "rateLimits": [
                "limitId": "opaque-rate-limit-id",
                "primary": [
                    "usedPercent": 12.5,
                    "windowDurationMins": 300,
                    "resetsAt": 1_800_000_000
                ],
                "secondary": [
                    "usedPercent": 24,
                    "windowDurationMins": 10_080,
                    "resetsAt": 1_800_100_000
                ]
            ],
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
                        "description": "One reset",
                        "access_token": "must-never-persist",
                        "refresh_token": "must-never-persist-either",
                        "cookie": "session=must-never-persist"
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
        XCTAssertEqual(snapshot.quotaWindows.map(\.durationMinutes), [300, 10_080])
        XCTAssertEqual(snapshot.quotaWindows.map(\.usedPercent), [12.5, 24])
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
        XCTAssertFalse(encoded.contains("must-never-persist"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("title"))
        XCTAssertFalse(encoded.localizedCaseInsensitiveContains("description"))
        XCTAssertFalse(encoded.contains("opaque-rate-limit-id"))
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
                    sequence: 1,
                    status: "available",
                    grantedAt: Date(timeIntervalSince1970: 1),
                    expiresAt: Date(timeIntervalSince1970: 2)
                )
            ],
            fetchedAt: Date(timeIntervalSince1970: 3)
        )
        let store = ResetCreditsCacheStore(fileURL: cacheURL)

        try await store.save(snapshot)
        let restored = try await store.load()

        XCTAssertEqual(restored, snapshot)
        let text = try String(contentsOf: cacheURL, encoding: .utf8)
        XCTAssertTrue(text.contains("\"schemaVersion\" : 3"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("creditId"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("access_token"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("refresh_token"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("cookie"))
        XCTAssertFalse(text.localizedCaseInsensitiveContains("description"))
    }

    func testLoadsLegacyVersionTwoCacheWithoutQuotaWindows() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cacheURL = directory.appendingPathComponent("reset-credits.json")
        let legacy = """
        {
          "schemaVersion": 2,
          "snapshot": {
            "availableCount": 1,
            "credits": [],
            "fetchedAt": "2026-07-18T00:00:00Z"
          }
        }
        """
        try Data(legacy.utf8).write(to: cacheURL)

        let restored = try await ResetCreditsCacheStore(fileURL: cacheURL).load()

        XCTAssertEqual(restored?.availableCount, 1)
        XCTAssertTrue(restored?.quotaWindows.isEmpty == true)
    }

    func testQuotaEstimateAllocatesAccountUsageAcrossLocalWindowTokens() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_768_608_000)
        let history = UsageHistory(
            generatedAt: now,
            timezoneIdentifier: calendar.timeZone.identifier,
            days: [
                DailyUsageSummary(dateKey: "2026-01-16", totalTokens: 400, tasks: [], isComplete: true),
                DailyUsageSummary(dateKey: "2026-01-17", totalTokens: 600, tasks: [], isComplete: true)
            ]
        )
        let window = AccountQuotaWindow(
            durationMinutes: 10_080,
            usedPercent: 20,
            resetsAt: now.addingTimeInterval(86_400)
        )

        let estimate = QuotaUsageEstimator.estimatedPercent(
            taskTokens: 100,
            history: history,
            window: window,
            now: now,
            calendar: calendar
        )

        XCTAssertEqual(estimate ?? -1, 2, accuracy: 0.0001)
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

    func testLocalizedErrorsNeverPrintCredentialsOrCompleteUniqueIDs() {
        let secret = "access_token=top-secret refresh_token=also-secret " +
            "cookie=session-secret id=123e4567-e89b-12d3-a456-426614174000"
        let errors: [ResetCreditsError] = [
            .launchFailed(secret),
            .notLoggedIn(secret),
            .protocolIncompatible(secret),
            .server(secret)
        ]

        for error in errors {
            let message = error.localizedDescription
            XCTAssertFalse(message.contains("top-secret"))
            XCTAssertFalse(message.contains("also-secret"))
            XCTAssertFalse(message.contains("session-secret"))
            XCTAssertFalse(message.contains("123e4567-e89b-12d3-a456-426614174000"))
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
