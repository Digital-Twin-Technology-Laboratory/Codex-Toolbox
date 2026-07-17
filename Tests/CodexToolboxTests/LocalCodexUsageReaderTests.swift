import Foundation
import SQLite3
import XCTest
@testable import CodexToolboxCore

final class LocalCodexUsageReaderTests: XCTestCase, @unchecked Sendable {
    func testSelectsLatestMostCompleteReadableDatabase() async throws {
        let workspace = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let old = workspace.appendingPathComponent("state_old.sqlite")
        let current = workspace.appendingPathComponent("state_current.sqlite")
        let mostComplete = workspace.appendingPathComponent("state_most_complete.sqlite")
        try createDatabase(
            at: old,
            threads: [("old", "Old", "", 100, 10)],
            edges: []
        )
        try createDatabase(
            at: current,
            threads: [
                ("new-a", "New A", "", 25, 20),
                ("new-b", "New B", "", 30, 20)
            ],
            edges: []
        )
        try createDatabase(
            at: mostComplete,
            threads: [
                ("complete-a", "Complete A", "", 1, 20),
                ("complete-b", "Complete B", "", 1, 20),
                ("complete-c", "Complete C", "", 1, 20)
            ],
            edges: []
        )

        let reader = LocalCodexUsageReader(
            codexHome: workspace,
            ledgerURL: workspace.appendingPathComponent("ledger.json")
        )
        let selected = try await reader.selectedStateDatabase()

        XCTAssertEqual(selected.standardizedFileURL, mostComplete.standardizedFileURL)
    }

    func testAggregatesRootsDeduplicatesIncrementsAndPreservesHistory() async throws {
        let workspace = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let rootRollout = workspace.appendingPathComponent("root.jsonl")
        let childRollout = workspace.appendingPathComponent("child.jsonl")
        let grandchildRollout = workspace.appendingPathComponent("grandchild.jsonl")
        let database = workspace.appendingPathComponent("state_test.sqlite")
        let ledger = workspace.appendingPathComponent("usage-ledger.json")

        let rootLines = [
            tokenLine(timestamp: "2026-07-17T15:59:59Z", cumulative: 10, increment: 10),
            tokenLine(timestamp: "2026-07-17T15:59:59Z", cumulative: 10, increment: 10),
            tokenLine(timestamp: "2026-07-17T16:00:01Z", cumulative: 25, increment: 15),
            "{not-json}"
        ].joined(separator: "\n") + "\n"
        let childLines = tokenLine(
            timestamp: "2026-07-17T16:00:02Z",
            cumulative: 7,
            increment: 7
        ) + "\n"
        try Data(rootLines.utf8).write(to: rootRollout)
        try Data(childLines.utf8).write(to: childRollout)
        try Data(
            (tokenLine(timestamp: "2026-07-17T16:00:03Z", cumulative: 4, increment: 4) + "\n").utf8
        ).write(to: grandchildRollout)
        try createDatabase(
            at: database,
            threads: [
                ("root", "Root Task", rootRollout.path, 25, 100),
                ("child", "Child Task", childRollout.path, 7, 101),
                ("grandchild", "Archived Grandchild", grandchildRollout.path, 4, 102)
            ],
            edges: [("root", "child"), ("child", "grandchild")],
            archivedThreadIDs: ["grandchild"]
        )

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let reader = LocalCodexUsageReader(
            codexHome: workspace,
            stateDatabaseURL: database,
            ledgerURL: ledger
        )
        let first = try await reader.readUsage(now: Date(timeIntervalSince1970: 1), calendar: calendar)

        XCTAssertEqual(first.summary(for: "2026-07-17")?.totalTokens, 10)
        let firstToday = try XCTUnwrap(first.summary(for: "2026-07-18"))
        XCTAssertEqual(firstToday.totalTokens, 26)
        XCTAssertEqual(firstToday.tasks.map(\.rootTaskID), ["root"])
        XCTAssertEqual(firstToday.tasks.first?.title, "Root Task")
        XCTAssertEqual(firstToday.tasks.first?.descendantCount, 2)
        XCTAssertFalse(firstToday.isComplete)
        XCTAssertTrue(first.warnings.contains { $0.contains("损坏") })

        try append(
            tokenLine(timestamp: "2026-07-17T16:05:00Z", cumulative: 12, increment: 5) + "\n",
            to: childRollout
        )
        let second = try await reader.readUsage(now: Date(timeIntervalSince1970: 2), calendar: calendar)
        XCTAssertEqual(second.summary(for: "2026-07-18")?.totalTokens, 31)
        XCTAssertFalse(try XCTUnwrap(second.summary(for: "2026-07-18")).isComplete)

        let replacement = tokenLine(
            timestamp: "2026-07-17T16:10:00Z",
            cumulative: 3,
            increment: 3
        ) + "\n"
        try Data(replacement.utf8).write(to: rootRollout)
        let afterTruncation = try await reader.readUsage(
            now: Date(timeIntervalSince1970: 3),
            calendar: calendar
        )
        XCTAssertNil(afterTruncation.summary(for: "2026-07-17"))
        XCTAssertEqual(afterTruncation.summary(for: "2026-07-18")?.totalTokens, 19)

        try FileManager.default.removeItem(at: childRollout)
        let afterMissingFile = try await reader.readUsage(
            now: Date(timeIntervalSince1970: 4),
            calendar: calendar
        )
        XCTAssertEqual(afterMissingFile.summary(for: "2026-07-18")?.totalTokens, 19)
        XCTAssertFalse(try XCTUnwrap(afterMissingFile.summary(for: "2026-07-18")).isComplete)
        XCTAssertTrue(afterMissingFile.warnings.contains { $0.contains("不可用") })

        let ledgerJSON = try String(contentsOf: ledger, encoding: .utf8)
        XCTAssertTrue(ledgerJSON.contains("\"schemaVersion\" : 1"))
        XCTAssertTrue(ledgerJSON.contains("\"parsedOffset\""))
    }

    func testClearHistoryRemovesLedger() async throws {
        let workspace = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let ledger = workspace.appendingPathComponent("usage-ledger.json")
        try Data("{}".utf8).write(to: ledger)
        let reader = LocalCodexUsageReader(codexHome: workspace, ledgerURL: ledger)

        try await reader.clearHistory()

        XCTAssertFalse(FileManager.default.fileExists(atPath: ledger.path))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalCodexUsageReaderTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func tokenLine(timestamp: String, cumulative: Int64, increment: Int64) -> String {
        let event: [String: Any] = [
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": [
                "type": "token_count",
                "info": [
                    "total_token_usage": [
                        "input_tokens": cumulative,
                        "cached_input_tokens": cumulative / 2,
                        "output_tokens": cumulative / 3,
                        "reasoning_output_tokens": cumulative / 4,
                        "total_tokens": cumulative
                    ],
                    "last_token_usage": [
                        "input_tokens": increment,
                        "cached_input_tokens": increment / 2,
                        "output_tokens": increment / 3,
                        "reasoning_output_tokens": increment / 4,
                        "total_tokens": increment
                    ]
                ]
            ]
        ]
        let data = try! JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func append(_ string: String, to url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(string.utf8))
    }

    private func createDatabase(
        at url: URL,
        threads: [(id: String, title: String, rollout: String, tokens: Int64, updated: Int64)],
        edges: [(parent: String, child: String)],
        archivedThreadIDs: Set<String> = []
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "SQLiteTest", code: 1)
        }
        defer { sqlite3_close(database) }
        try execute(
            "CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT, rollout_path TEXT, " +
            "tokens_used INTEGER, archived INTEGER, created_at INTEGER, updated_at INTEGER); " +
            "CREATE TABLE thread_spawn_edges (parent_thread_id TEXT, child_thread_id TEXT);",
            in: database
        )
        for (index, thread) in threads.enumerated() {
            try execute(
                "INSERT INTO threads VALUES (" +
                "'\(sql(thread.id))','\(sql(thread.title))','\(sql(thread.rollout))'," +
                "\(thread.tokens),\(archivedThreadIDs.contains(thread.id) ? 1 : 0),\(index + 1),\(thread.updated));",
                in: database
            )
        }
        for edge in edges {
            try execute(
                "INSERT INTO thread_spawn_edges VALUES ('\(sql(edge.parent))','\(sql(edge.child))');",
                in: database
            )
        }
    }

    private func execute(_ sql: String, in database: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorMessage)
            throw NSError(domain: "SQLiteTest", code: 2, userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    private func sql(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }
}
