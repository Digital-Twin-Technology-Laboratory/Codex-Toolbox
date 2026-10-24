import Foundation
import SQLite3
import XCTest
@testable import CodexToolboxCore

final class StateDatabaseRetryTests: XCTestCase {
    func testTransientFailureRetriesWithBoundedDelays() throws {
        var attempts = 0
        var slept: [TimeInterval] = []
        let value = try StateDatabaseRetry.run(delays: [0.05, 0.2], sleep: { slept.append($0) }) { () throws -> Int in
            attempts += 1
            if attempts < 3 { throw StateDatabaseReadFailure(code: SQLITE_CANTOPEN, message: "unable to open database file") }
            return 7
        }
        XCTAssertEqual(value, 7)
        XCTAssertEqual(attempts, 3)
        XCTAssertEqual(slept, [0.05, 0.2])
    }

    func testExhaustedRetriesRethrowLastFailure() {
        var attempts = 0
        XCTAssertThrowsError(try StateDatabaseRetry.run(delays: [0.05, 0.2], sleep: { _ in }) { () throws -> Int in
            attempts += 1
            throw StateDatabaseReadFailure(code: SQLITE_BUSY, message: "database is locked")
        }) { error in
            XCTAssertEqual((error as? StateDatabaseReadFailure)?.code, SQLITE_BUSY)
        }
        XCTAssertEqual(attempts, 3)
    }

    func testPermanentFailureAndMissingFileDoNotRetry() {
        var attempts = 0
        XCTAssertThrowsError(try StateDatabaseRetry.run(sleep: { _ in XCTFail("must not sleep") }) { () throws -> Int in
            attempts += 1
            throw StateDatabaseReadFailure(code: SQLITE_CORRUPT, message: "database disk image is malformed")
        })
        XCTAssertEqual(attempts, 1)

        attempts = 0
        XCTAssertThrowsError(try StateDatabaseRetry.run(canRetry: { false }, sleep: { _ in XCTFail("must not sleep") }) { () throws -> Int in
            attempts += 1
            throw StateDatabaseReadFailure(code: SQLITE_CANTOPEN, message: "unable to open database file")
        })
        XCTAssertEqual(attempts, 1)
    }

    func testExtendedCantOpenCodeIsTransient() {
        XCTAssertTrue(StateDatabaseReadFailure(code: SQLITE_CANTOPEN | (1 << 8), message: "").isTransient)
        XCTAssertFalse(StateDatabaseReadFailure(code: SQLITE_ERROR, message: "").isTransient)
    }

    func testWALDatabaseRemainsReadableAfterWriterRemovesWAL() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("状态 数据库#?-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        let database = workspace.appendingPathComponent("state_5.sqlite")
        var writer: OpaquePointer?
        XCTAssertEqual(sqlite3_open(database.path, &writer), SQLITE_OK)
        let id = UUID().uuidString
        XCTAssertEqual(sqlite3_exec(writer, """
            PRAGMA journal_mode=WAL;
            CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT, rollout_path TEXT, tokens_used INTEGER,
                created_at INTEGER, updated_at INTEGER);
            INSERT INTO threads VALUES ('\(id)', 'Task', '', 5, 1, 4000000);
            """, nil, nil, nil), SQLITE_OK)
        XCTAssertTrue(FileManager.default.fileExists(atPath: database.path + "-wal"))
        XCTAssertEqual(sqlite3_close(writer), SQLITE_OK)
        // Apple's SQLite keeps the WAL by default; Codex's bundled SQLite removes it on close.
        for suffix in ["-wal", "-shm"] { try? FileManager.default.removeItem(atPath: database.path + suffix) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path + "-wal"))

        let reader = LocalCodexUsageReader(codexHome: workspace, stateDatabaseURL: database,
            ledgerURL: workspace.appendingPathComponent("ledger.json"))
        let selected = try await reader.selectedStateDatabase()
        XCTAssertEqual(selected.path, database.standardizedFileURL.path)
        let catalogue = try await reader.nativeCatalogue(now: Date(timeIntervalSince1970: 4_000_001))
        XCTAssertEqual(catalogue.threads.map(\.id), [id])
        // Reading must never recreate Codex's files.
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path + "-wal"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: database.path + "-shm"))
    }

    func testMissingDatabaseKeepsExistingNotFoundMessage() async throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("StateDatabaseRetryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workspace) }
        try Data("not a database".utf8).write(to: workspace.appendingPathComponent("state_5.sqlite"))
        let reader = LocalCodexUsageReader(codexHome: workspace, ledgerURL: workspace.appendingPathComponent("ledger.json"))
        do {
            _ = try await reader.selectedStateDatabase()
            XCTFail("expected failure")
        } catch {
            XCTAssertEqual(error.localizedDescription, "在 \(workspace.path) 中未找到可读取的 Codex 状态数据库。")
        }
    }
}
