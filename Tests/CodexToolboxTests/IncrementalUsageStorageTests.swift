import Foundation
import XCTest
import SQLite3
@testable import CodexToolboxCore

final class IncrementalUsageStorageTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func sample(at date: Date, account: String = "a") -> NativeTaskQuotaSnapshot {
        NativeTaskQuotaSnapshot(accountKey: account,
            thread: NativeThread(id: "root", title: "Task", createdAt: nil, descendantIDs: [], earliestCreatedAt: nil),
            row: NativeTaskUsageRow(id: "root", status: "available", usageSource: "included_plan", fiveHourPercent: nil, weeklyPercent: 2, groups: []),
            collectedAt: date, dataAsOf: date.addingTimeInterval(-1), planType: "pro",
            timezoneIdentifier: "GMT", continuityID: "run")
    }
    private func modificationDates(in url: URL) throws -> [String: Date] {
        try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey]).map {
            ($0.lastPathComponent, try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate!)
        })
    }
    func testNativeMigrationPreservesDuplicateRowsAndRetentionRemovesEveryCopy() async throws {
        struct Envelope: Codable { var schemaVersion = 1; var snapshots: [NativeTaskQuotaSnapshot] }
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("native.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000), first = sample(at: Date(timeIntervalSince1970: 1_800_000_000))
        let encoder = JSONEncoder(); try encoder.encode(Envelope(snapshots: [first, first])).write(to: url)
        let store = NativeTaskQuotaStore(fileURL: url)
        let imported = try await store.snapshots(accountKey: "a"); XCTAssertEqual(imported, [first, first])
        try await store.append([first], now: now)
        try await store.exportLegacyHistory()
        let exported = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url))
        XCTAssertEqual(exported.snapshots, [first, first])
        let later = sample(at: now.addingTimeInterval(91 * 86400))
        try await store.append([later], now: later.collectedAt)
        let remaining = try await store.snapshots(accountKey: "a"); XCTAssertEqual(remaining, [later])
        let reopened = NativeTaskQuotaStore(fileURL: url)
        let persisted = try await reopened.snapshots(accountKey: "a"); XCTAssertEqual(persisted, [later])
        await store.close()
        await reopened.close()
    }

    func testInterruptedExportBeforeJSONReplacementCompletesOnReopen() async throws {
        struct Envelope: Codable { var schemaVersion = 1; var snapshots: [NativeTaskQuotaSnapshot] }
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("native.json"), now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = sample(at: now), second = sample(at: now.addingTimeInterval(60))
        let encoder = JSONEncoder()
        let original = try encoder.encode(Envelope(snapshots: [first]))
        try original.write(to: url)
        let store = NativeTaskQuotaStore(fileURL: url)
        try await store.append([second], now: second.collectedAt); await store.close()
        // Inject the durable state at the crash boundary, before the atomic JSON replacement.
        do {
            let database = try IncrementalUsageDatabase(url: url.appendingPathExtension("sqlite"))
            try database.transaction {
                try database.setMetadata("exportPending", encoder.encode(Envelope(snapshots: [first, second])))
                try database.setMetadata("exportPrevious", IncrementalUsageDatabase.fingerprint(original))
            }
        }
        let reopened = NativeTaskQuotaStore(fileURL: url)
        let values = try await reopened.snapshots(accountKey: "a")
        XCTAssertEqual(values, [first, second])
        XCTAssertEqual(try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url)).snapshots, [first, second])
        await reopened.close()
    }

    func testInterruptedExportFinalizationPreservesLaterOldVersionWrites() async throws {
        struct Envelope: Codable { var schemaVersion = 1; var snapshots: [NativeTaskQuotaSnapshot] }
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("native.json"), now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = sample(at: now), second = sample(at: now.addingTimeInterval(60)), third = sample(at: now.addingTimeInterval(120))
        let encoder = JSONEncoder(); try encoder.encode(Envelope(snapshots: [first])).write(to: url)
        let store = NativeTaskQuotaStore(fileURL: url); try await store.append([second], now: second.collectedAt)
        var handle: OpaquePointer?; XCTAssertEqual(sqlite3_open(url.appendingPathExtension("sqlite").path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "CREATE TRIGGER fail_export BEFORE INSERT ON metadata WHEN NEW.key = 'exported' BEGIN SELECT RAISE(ABORT, 'test'); END", nil, nil, nil), SQLITE_OK)
        do { try await store.exportLegacyHistory(); XCTFail("Injected export finalization failure") } catch { }
        let written = try JSONDecoder().decode(Envelope.self, from: Data(contentsOf: url)); XCTAssertEqual(written.snapshots, [first, second])
        await store.close()
        XCTAssertEqual(sqlite3_exec(handle, "DROP TRIGGER fail_export", nil, nil, nil), SQLITE_OK); sqlite3_close(handle)
        try encoder.encode(Envelope(snapshots: [first, second, third])).write(to: url, options: .atomic)
        let reopened = NativeTaskQuotaStore(fileURL: url)
        let recovered = try await reopened.snapshots(accountKey: "a"); XCTAssertEqual(recovered, [first, second, third])
        await reopened.close()
    }

    func testIdenticalNativeRetryDoesNotWriteButNewObservationTimePersists() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("native.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = NativeTaskQuotaStore(fileURL: source)
        let first = sample(at: now)
        try await store.append([first], now: now)
        let before = try modificationDates(in: dir)
        try await Task.sleep(for: .milliseconds(20))
        try await store.append([first], now: now)
        XCTAssertEqual(try modificationDates(in: dir), before, "An identical retry must not rewrite persistent storage")
        let later = sample(at: now.addingTimeInterval(60))
        try await store.append([later], now: later.collectedAt)
        let reopened = NativeTaskQuotaStore(fileURL: source)
        let values = try await reopened.snapshots(accountKey: "a")
        XCTAssertEqual(values, [first, later], "A new sampling time is new evidence even if percentages match")
        await store.close()
        await reopened.close()
    }
    func testAccountSampleMigrationPreservesForeignTimezoneAndMissingRolloutHistory() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("ledger.json")
        let ledger = VersionedUsageLedger(schemaVersion: 7, generatedAt: .distantPast,
            timezoneIdentifier: "Pacific/Honolulu", threads: ["deleted": ThreadUsageLedgerEntry(
                threadID: "deleted", rootTaskID: "deleted", title: "Old task", dailyTokens: ["2020-01-01": 123],
                checkpoint: nil, isComplete: false)], warnings: [])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(ledger); try original.write(to: source)
        let reader = LocalCodexUsageReader(codexHome: dir, ledgerURL: source)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        try await reader.recordAccountQuotaSnapshot(windows: [AccountQuotaWindow(durationMinutes: 10080,
            usedPercent: 2, resetsAt: now.addingTimeInterval(86400))], planType: "pro", timestamp: now, accountKey: "a")
        XCTAssertEqual(try Data(contentsOf: source), original, "Import must leave the legacy source intact")
        try await reader.exportLegacyHistory()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(VersionedUsageLedger.self, from: Data(contentsOf: source))
        XCTAssertEqual(exported.timezoneIdentifier, "Pacific/Honolulu")
        XCTAssertEqual(exported.threads["deleted"]?.dailyTokens["2020-01-01"], 123)
        XCTAssertEqual(exported.accountObservations.count, 1)
        XCTAssertEqual(try Data(contentsOf: source.appendingPathExtension("pre-1.4.2-backup")), original)
        await reader.close()
    }

    func testDuplicateAccountMigrationAndSameMinuteReplacementRemainAccountIsolated() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ledger.json"), now = Date(timeIntervalSince1970: 1_800_000_000)
        let windows = [AccountQuotaWindow(durationMinutes: 10080, usedPercent: 2, resetsAt: now.addingTimeInterval(86400))]
        let context = UsageExecutionContext(modelID: nil, reasoningEffort: nil, serviceTier: nil, planType: "pro", hasAccountRateLimits: true)
        let first = ThreadQuotaUsageObservation(timestamp: now, tokenIncrement: 0, accountKey: "a", executionContext: context, windows: windows)
        let other = ThreadQuotaUsageObservation(timestamp: now, tokenIncrement: 0, accountKey: "b", executionContext: context, windows: windows)
        var ledger = VersionedUsageLedger.empty(timezoneIdentifier: "GMT")
        ledger.accountObservations = [first, first, other]
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ledger).write(to: url)
        let reader = LocalCodexUsageReader(codexHome: dir, ledgerURL: url)
        try await reader.exportLegacyHistory()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let migrated = try decoder.decode(VersionedUsageLedger.self, from: Data(contentsOf: url))
        XCTAssertEqual(migrated.accountObservations.filter { $0.accountKey == "a" }, [first, first])
        try await reader.recordAccountQuotaSnapshot(windows: windows, planType: "pro", timestamp: now.addingTimeInterval(1), accountKey: "a")
        await reader.close()
        let reopened = LocalCodexUsageReader(codexHome: dir, ledgerURL: url)
        try await reopened.exportLegacyHistory(); await reopened.close()
        let updated = try decoder.decode(VersionedUsageLedger.self, from: Data(contentsOf: url))
        XCTAssertEqual(updated.accountObservations.count, 2)
        XCTAssertEqual(updated.accountObservations.filter { $0.accountKey == "b" }, [other])
        XCTAssertEqual(updated.accountObservations.first { $0.accountKey == "a" }?.timestamp, now.addingTimeInterval(1))
    }

    func testRollbackRewriteKeepsUnchangedBucketTimezoneWithoutResurrectingRemovedThreads() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ledger.json")
        var ledger = VersionedUsageLedger.empty(timezoneIdentifier: "Pacific/Honolulu")
        for id in ["kept", "removed"] {
            ledger.threads[id] = .init(threadID: id, rootTaskID: id, title: id, dailyTokens: ["2020-01-01": 123],
                checkpoint: nil, isComplete: false, sourceTimezoneIdentifier: "GMT")
        }
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ledger).write(to: url)
        let reader = LocalCodexUsageReader(codexHome: dir, ledgerURL: url)
        try await reader.exportLegacyHistory(); await reader.close()
        // The old binary drops unknown per-thread fields and may remove historical rows.
        ledger.threads["kept"]?.sourceTimezoneIdentifier = nil
        ledger.threads.removeValue(forKey: "removed")
        try encoder.encode(ledger).write(to: url, options: .atomic)
        let upgraded = LocalCodexUsageReader(codexHome: dir, ledgerURL: url)
        try await upgraded.exportLegacyHistory(); await upgraded.close()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let recovered = try decoder.decode(VersionedUsageLedger.self, from: Data(contentsOf: url))
        XCTAssertEqual(recovered.threads["kept"]?.sourceTimezoneIdentifier, "GMT")
        XCTAssertEqual(recovered.threads["kept"]?.dailyTokens, ["2020-01-01": 123])
        XCTAssertNil(recovered.threads["removed"])
        try FileManager.default.removeItem(at: url)
        let cleared = LocalCodexUsageReader(codexHome: dir, ledgerURL: url)
        try await cleared.exportLegacyHistory(); await cleared.close()
        XCTAssertTrue(try decoder.decode(VersionedUsageLedger.self, from: Data(contentsOf: url)).threads.isEmpty)
    }

    func testRollbackAppendPreservesPerDayTimezoneAndMarksMixedDay() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ledger.json")
        var ledger = VersionedUsageLedger.empty(timezoneIdentifier: "Pacific/Honolulu")
        ledger.threads["kept"] = .init(threadID: "kept", rootTaskID: "kept", title: "Task",
            dailyTokens: ["2020-01-01": 123, "2020-01-02": 10], checkpoint: nil, isComplete: false, sourceTimezoneIdentifier: "GMT")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(ledger).write(to: url)
        let reader = LocalCodexUsageReader(codexHome: dir, ledgerURL: url)
        try await reader.exportLegacyHistory(); await reader.close()
        ledger.threads["kept"]?.sourceTimezoneIdentifier = nil
        ledger.threads["kept"]?.dailyTokens["2020-01-02"] = 17
        ledger.threads["kept"]?.dailyTokens["2020-01-03"] = 5
        try encoder.encode(ledger).write(to: url, options: .atomic)
        let upgraded = LocalCodexUsageReader(codexHome: dir, ledgerURL: url)
        try await upgraded.exportLegacyHistory(); await upgraded.close()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let threads = try XCTUnwrap(object["threads"] as? [String: [String: Any]])
        let entry = try XCTUnwrap(threads["kept"])
        let timezones = entry["dayBucketTimezones"] as? [String: [String]] ?? [:]
        XCTAssertEqual(timezones["2020-01-01"], ["GMT"])
        XCTAssertEqual(Set(timezones["2020-01-02"] ?? []), Set(["GMT", "Pacific/Honolulu"]))
        XCTAssertEqual(entry["sourceTimezoneIdentifier"] as? String, "Pacific/Honolulu")
        XCTAssertEqual(entry["dailyTokens"] as? [String: Int], ["2020-01-01": 123, "2020-01-02": 17, "2020-01-03": 5])
        XCTAssertEqual(entry["isComplete"] as? Bool, false)
    }

    func testRollbackExportThenOldVersionUpdateIsImportedOnNextUpgrade() async throws {
        struct Envelope: Codable { var schemaVersion = 1; var snapshots: [NativeTaskQuotaSnapshot] }
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("native.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = sample(at: now), second = sample(at: now.addingTimeInterval(60), account: "b")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(Envelope(snapshots: [first])); try original.write(to: url)
        let store = NativeTaskQuotaStore(fileURL: url)
        let restored = try await store.snapshots(accountKey: "a"); XCTAssertEqual(restored, [first])
        try await store.exportLegacyHistory()
        try encoder.encode(Envelope(snapshots: [first, second])).write(to: url, options: .atomic)
        let nextVersion = NativeTaskQuotaStore(fileURL: url)
        let oldVersionAddition = try await nextVersion.snapshots(accountKey: "b")
        XCTAssertEqual(oldVersionAddition, [second])
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("pre-1.4.2-backup")), original)
        await store.close()
        await nextVersion.close()
    }
    func testFailedNativeTransactionDoesNotAdvanceInMemoryStateAndCanRetry() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("native.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = sample(at: now), next = sample(at: now.addingTimeInterval(60))
        let store = NativeTaskQuotaStore(fileURL: url)
        try await store.append([first], now: now)
        var lock: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.appendingPathExtension("sqlite").path, &lock), SQLITE_OK)
        defer { sqlite3_close(lock) }
        XCTAssertEqual(sqlite3_exec(lock, "BEGIN EXCLUSIVE", nil, nil, nil), SQLITE_OK)
        do { try await store.append([next], now: next.collectedAt); XCTFail("Locked transaction must fail") }
        catch { }
        let afterFailure = try await store.snapshots(accountKey: "a"); XCTAssertEqual(afterFailure, [first])
        XCTAssertEqual(sqlite3_exec(lock, "ROLLBACK", nil, nil, nil), SQLITE_OK)
        try await store.append([next], now: next.collectedAt)
        let reopened = NativeTaskQuotaStore(fileURL: url)
        let recovered = try await reopened.snapshots(accountKey: "a"); XCTAssertEqual(recovered, [first, next])
        await store.close()
        await reopened.close()
    }
    func testClearedLedgerDoesNotResurrectLegacyBackupAndDuplicateSamplingDoesNotWrite() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ledger.json")
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let ledger = VersionedUsageLedger(schemaVersion: 7, generatedAt: now, timezoneIdentifier: "GMT",
            threads: ["deleted": ThreadUsageLedgerEntry(threadID: "deleted", rootTaskID: "deleted", title: "Old", dailyTokens: ["2020-01-01": 123], checkpoint: nil, isComplete: true)], warnings: [])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let original = try encoder.encode(ledger); try original.write(to: url)
        let reader = LocalCodexUsageReader(codexHome: dir, ledgerURL: url)
        let windows = [AccountQuotaWindow(durationMinutes: 10080, usedPercent: 2, resetsAt: now.addingTimeInterval(86400))]
        try await reader.recordAccountQuotaSnapshot(windows: windows, planType: "pro", timestamp: now, accountKey: "a")
        let before = try modificationDates(in: dir)
        try await reader.recordAccountQuotaSnapshot(windows: windows, planType: "pro", timestamp: now, accountKey: "a")
        XCTAssertEqual(try modificationDates(in: dir), before)
        try await reader.clearHistory()
        let reopened = LocalCodexUsageReader(codexHome: dir, ledgerURL: url)
        try await reopened.exportLegacyHistory()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let exported = try decoder.decode(VersionedUsageLedger.self, from: Data(contentsOf: url))
        XCTAssertTrue(exported.threads.isEmpty); XCTAssertTrue(exported.accountObservations.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url.appendingPathExtension("pre-1.4.2-backup")), original)
        await reader.close()
        await reopened.close()
    }

    func testUnsupportedLedgerMigrationLeavesSourceUntouchedAndCanRetry() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("ledger.json")
        var ledger = VersionedUsageLedger.empty(timezoneIdentifier: "GMT"); ledger.schemaVersion = 99
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let invalid = try encoder.encode(ledger); try invalid.write(to: url)
        let reader = LocalCodexUsageReader(codexHome: dir, ledgerURL: url)
        do { try await reader.exportLegacyHistory(); XCTFail("Future schema must not migrate as empty history") } catch { }
        XCTAssertEqual(try Data(contentsOf: url), invalid)
        ledger.schemaVersion = 7
        try encoder.encode(ledger).write(to: url, options: .atomic)
        try await reader.exportLegacyHistory()
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let result = try decoder.decode(VersionedUsageLedger.self, from: Data(contentsOf: url))
        XCTAssertEqual(result.schemaVersion, 7)
        await reader.close()
    }

}
