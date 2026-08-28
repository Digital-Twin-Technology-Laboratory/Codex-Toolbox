import Foundation
import XCTest
@testable import CodexToolboxCore

final class ResetCreditsClientTests: XCTestCase, @unchecked Sendable {
    func testPartialResponsePreservesKnownDetailsWhenAvailableCountIsUnchanged() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let knownCredit = ResetCreditSummary(
            sequence: 1,
            status: "available",
            grantedAt: Date(timeIntervalSince1970: 10),
            expiresAt: Date(timeIntervalSince1970: 20)
        )
        let previous = ResetCreditsSnapshot(
            availableCount: 1,
            credits: [knownCredit],
            quotaWindows: [],
            planType: "plus",
            fetchedAt: Date(timeIntervalSince1970: 30)
        )
        let refreshedWindow = AccountQuotaWindow(
            durationMinutes: 300,
            usedPercent: 25,
            resetsAt: Date(timeIntervalSince1970: 40)
        )
        let partial = ResetCreditsSnapshot(
            availableCount: 1,
            credits: [],
            quotaWindows: [refreshedWindow],
            planType: "pro",
            fetchedAt: Date(timeIntervalSince1970: 50)
        )

        let merged = partial.preservingCreditDetails(from: previous)

        XCTAssertEqual(merged.credits, [knownCredit])
        XCTAssertEqual(merged.availableCount, 1)
        XCTAssertEqual(merged.quotaWindows, [refreshedWindow])
        XCTAssertEqual(merged.planType, "pro")
        XCTAssertEqual(merged.fetchedAt, Date(timeIntervalSince1970: 50))

        let store = ResetCreditsCacheStore(
            fileURL: directory.appendingPathComponent("reset-credits.json")
        )
        try await store.save(merged)
        let restoredAfterRelaunch = try await store.load()

        XCTAssertEqual(restoredAfterRelaunch, merged)
        XCTAssertEqual(restoredAfterRelaunch?.credits, [knownCredit])
    }

    func testPartialResponseDoesNotPreserveDetailsWhenAvailableCountChanges() {
        let previous = ResetCreditsSnapshot(
            availableCount: 1,
            credits: [
                ResetCreditSummary(
                    sequence: 1,
                    status: "available",
                    grantedAt: nil,
                    expiresAt: nil
                )
            ],
            fetchedAt: Date(timeIntervalSince1970: 10)
        )
        let changed = ResetCreditsSnapshot(
            availableCount: 0,
            credits: [],
            fetchedAt: Date(timeIntervalSince1970: 20)
        )

        let merged = changed.preservingCreditDetails(from: previous)

        XCTAssertTrue(merged.credits.isEmpty)
        XCTAssertEqual(merged.availableCount, 0)
    }

    func testCompleteResponseReplacesPreviouslyKnownDetails() {
        let previousCredit = ResetCreditSummary(
            sequence: 1,
            status: "available",
            grantedAt: Date(timeIntervalSince1970: 10),
            expiresAt: Date(timeIntervalSince1970: 20)
        )
        let refreshedCredit = ResetCreditSummary(
            sequence: 1,
            status: "available",
            grantedAt: Date(timeIntervalSince1970: 30),
            expiresAt: Date(timeIntervalSince1970: 40)
        )
        let previous = ResetCreditsSnapshot(
            availableCount: 1,
            credits: [previousCredit],
            fetchedAt: Date(timeIntervalSince1970: 50)
        )
        let complete = ResetCreditsSnapshot(
            availableCount: 1,
            credits: [refreshedCredit],
            fetchedAt: Date(timeIntervalSince1970: 60)
        )

        let merged = complete.preservingCreditDetails(from: previous)

        XCTAssertEqual(merged.credits, [refreshedCredit])
    }

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

    func testProcessTransportClassifiesRateLimitFetchFailureAsTemporary() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent("failing-codex")
        let script = """
        #!/bin/sh
        IFS= read -r initialize
        printf '%s\\n' '{"id":1,"result":{}}'
        IFS= read -r initialized
        IFS= read -r request
        printf '%s\\n' '{"id":2,"error":{"code":-32603,"message":"failed to fetch codex rate limits: error sending request for url (https://chatgpt.com/backend-api/wham/usage)"}}'
        """
        try Data(script.utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let transport = ProcessCodexAppServerTransport(executableURL: executable, timeout: 2)

        do {
            _ = try await transport.request(method: ProcessCodexAppServerTransport.allowedMethod)
            XCTFail("temporary upstream failure should be typed")
        } catch let error as ResetCreditsError {
            guard case .temporarilyUnavailable = error else {
                return XCTFail("unexpected error: \(error)")
            }
            XCTAssertEqual(
                error.localizedDescription,
                "Codex 账户服务暂时无法连接，请稍后重试。"
            )
        }
    }

    func testClientRetriesTemporaryFailureThenSucceeds() async throws {
        let response: [String: Any] = [
            "rateLimitResetCredits": ["availableCount": 1, "credits": []]
        ]
        let transport = SequencedTransport(outcomes: [
            .failure(.temporarilyUnavailable("upstream request failed")),
            .success(jsonData(response))
        ])
        let client = ResetCreditsClient(
            transport: transport,
            sleep: { _ in }
        )

        let snapshot = try await client.readResetCredits()
        let callCount = await transport.callCount()

        XCTAssertEqual(snapshot.availableCount, 1)
        XCTAssertEqual(callCount, 2)
    }

    func testClientRetriesTimeoutOnlyOnce() async throws {
        let transport = SequencedTransport(outcomes: [
            .failure(.timeout),
            .failure(.timeout),
            .failure(.timeout)
        ])
        let client = ResetCreditsClient(
            transport: transport,
            sleep: { _ in }
        )

        do {
            _ = try await client.readResetCredits()
            XCTFail("timeout retry budget should be bounded")
        } catch let error as ResetCreditsError {
            XCTAssertEqual(error, .timeout)
        }
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 2)
    }

    func testClientDoesNotRetryAuthenticationFailure() async throws {
        let transport = SequencedTransport(outcomes: [
            .failure(.notLoggedIn("login required")),
            .failure(.temporarilyUnavailable("must not be reached"))
        ])
        let client = ResetCreditsClient(
            transport: transport,
            sleep: { _ in }
        )

        do {
            _ = try await client.readResetCredits()
            XCTFail("authentication failure should be returned immediately")
        } catch let error as ResetCreditsError {
            XCTAssertEqual(error, .notLoggedIn("login required"))
        }
        let callCount = await transport.callCount()
        XCTAssertEqual(callCount, 1)
    }

    func testClientPreservesTypedRecoveryErrors() async throws {
        for expected in [
            ResetCreditsError.notLoggedIn("login required"),
            ResetCreditsError.protocolIncompatible("unexpected response"),
            ResetCreditsError.timeout
        ] {
            let client = ResetCreditsClient(
                transport: RecordingTransport(error: expected),
                sleep: { _ in }
            )
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
            .temporarilyUnavailable(secret),
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

    func testOnlyTemporaryServerAndTimeoutErrorsAreTransient() {
        XCTAssertTrue(ResetCreditsError.timeout.isTransient)
        XCTAssertTrue(ResetCreditsError.temporarilyUnavailable("upstream").isTransient)
        XCTAssertFalse(ResetCreditsError.notLoggedIn("login").isTransient)
        XCTAssertFalse(ResetCreditsError.protocolIncompatible("schema").isTransient)
        XCTAssertFalse(ResetCreditsError.server("internal").isTransient)
    }

    private func jsonData(_ object: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ResetCreditsClientTests-\(UUID().uuidString)", isDirectory: true)
    }
}

private actor SequencedTransport: CodexAppServerRequesting {
    enum Outcome: Sendable {
        case success(Data)
        case failure(ResetCreditsError)
    }

    private var outcomes: [Outcome]
    private var calls = 0

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    func request(method: String) throws -> Data {
        calls += 1
        switch outcomes.removeFirst() {
        case let .success(data): return data
        case let .failure(error): throw error
        }
    }

    func callCount() -> Int { calls }
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
