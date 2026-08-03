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
        XCTAssertTrue(ledgerJSON.contains("\"schemaVersion\" : 5"))
        XCTAssertTrue(ledgerJSON.contains("\"parsedOffset\""))
    }

    func testRolloutParserHandlesChunkBoundariesAndReusesEndCheckpoint() throws {
        let workspace = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let rollout = workspace.appendingPathComponent("large.jsonl")
        let data = Data(
            ((1...700).map {
                tokenLine(
                    timestamp: "2026-07-18T00:00:00Z",
                    cumulative: Int64($0),
                    increment: 1
                )
            }.joined(separator: "\n") + "\n").utf8
        )
        XCTAssertGreaterThan(data.count, 64 * 1_024)
        try data.write(to: rollout)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "GMT"))
        let first = try RolloutTokenParser.parse(fileURL: rollout, previous: nil, calendar: calendar)

        XCTAssertEqual(first.dailyTokens["2026-07-18"], 700)
        XCTAssertEqual(first.checkpoint.parsedOffset, UInt64(data.count))
        let previous = ThreadUsageLedgerEntry(
            threadID: "thread",
            rootTaskID: "thread",
            title: "Large rollout",
            dailyTokens: first.dailyTokens,
            quotaObservations: first.quotaObservations,
            checkpoint: first.checkpoint,
            isComplete: false
        )

        let reused = try RolloutTokenParser.parse(fileURL: rollout, previous: previous, calendar: calendar)

        XCTAssertTrue(reused.resumedFromCheckpoint)
        XCTAssertEqual(reused.damagedLineCount, 0)
        XCTAssertEqual(reused.dailyTokens, first.dailyTokens)
        XCTAssertEqual(reused.quotaObservations, first.quotaObservations)
        XCTAssertEqual(reused.checkpoint, first.checkpoint)
    }

    func testExtractsSanitizedQuotaObservationsAndAggregatesThemToTheRoot() async throws {
        let workspace = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let rollout = workspace.appendingPathComponent("quota.jsonl")
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let lines = [
            turnContextLine(model: "gpt-5.6-sol"),
            tokenLine(
                timestamp: "2026-07-22T08:00:00Z",
                cumulative: 100,
                increment: 100,
                quotaPercent: 12,
                quotaReset: reset
            ),
            tokenLine(
                timestamp: "2026-07-22T08:01:00Z",
                cumulative: 300,
                increment: 200,
                quotaPercent: 13,
                quotaReset: reset
            )
        ].joined(separator: "\n") + "\n"
        try Data(lines.utf8).write(to: rollout)
        let database = workspace.appendingPathComponent("state_test.sqlite")
        let ledger = workspace.appendingPathComponent("usage-ledger.json")
        try createDatabase(
            at: database,
            threads: [("child", "Child", rollout.path, 300, 1), ("root", "Root", "", 0, 2)],
            edges: [("root", "child")]
        )
        let reader = LocalCodexUsageReader(
            codexHome: workspace,
            stateDatabaseURL: database,
            ledgerURL: ledger
        )

        let history = try await reader.readUsage()

        XCTAssertEqual(history.quotaObservations.count, 2)
        XCTAssertEqual(history.quotaObservations.map(\.rootTaskID), ["root", "root"])
        XCTAssertEqual(history.quotaObservations.map(\.tokenIncrement), [100, 200])
        XCTAssertEqual(
            try XCTUnwrap(history.quotaObservations[0].quotaUsageWeight),
            632.5,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(history.quotaObservations[1].quotaUsageWeight),
            1_265,
            accuracy: 0.0001
        )
        XCTAssertEqual(history.quotaObservations.flatMap(\.windows).map(\.durationMinutes), [10_080, 10_080])
        XCTAssertEqual(history.quotaObservations.flatMap(\.windows).map(\.usedPercent), [12, 13])
        let ledgerText = try String(contentsOf: ledger, encoding: .utf8)
        XCTAssertTrue(ledgerText.contains("\"quotaUsageWeight\""))
        XCTAssertFalse(ledgerText.contains("opaque-limit-id"))
        XCTAssertFalse(ledgerText.contains("must-not-persist"))
        XCTAssertFalse(ledgerText.contains("prolite"))
    }

    func testQuotaUsageWeightingMatchesPublishedCodexRateCard() throws {
        let usage: [String: Any] = [
            "input_tokens": 1_000,
            "cached_input_tokens": 400,
            "output_tokens": 200
        ]
        let cases: [(model: String, expected: Double)] = [
            ("gpt-5.6-sol", 4_600),
            ("gpt-5.6-terra", 1_840),
            ("gpt-5.6-luna", 184),
            ("gpt-5.5", 4_600),
            ("gpt-5.5-cyber", 11_500),
            ("gpt-5.4", 2_300),
            ("gpt-5.4-mini", 692),
            ("gpt-5.3-codex", 1_960),
            ("gpt-5.2", 1_960)
        ]

        for item in cases {
            XCTAssertEqual(
                QuotaUsageWeighting.weight(
                    lastUsage: usage,
                    modelID: item.model,
                    fallbackTokens: 9_999
                ),
                item.expected,
                accuracy: 0.0001,
                item.model
            )
        }

        XCTAssertEqual(
            QuotaUsageWeighting.weight(
                lastUsage: usage,
                modelID: "future-unknown-model",
                fallbackTokens: 9_999
            ),
            9_999
        )
        XCTAssertEqual(
            QuotaUsageWeighting.weight(
                lastUsage: usage,
                modelID: "gpt-5.3-codex-spark",
                fallbackTokens: 9_999
            ),
            9_999,
            "Research-preview pricing must not inherit the finalized GPT-5.3-Codex rate"
        )
    }

    func testMigratesVersionOneLedgerByPreservingTokensAndForcingQuotaBackfill() throws {
        let workspace = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let ledgerURL = workspace.appendingPathComponent("usage-ledger.json")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: Date())
        let todayKey = String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
        let legacy = """
        {
          "schemaVersion": 1,
          "generatedAt": "2026-07-22T00:00:00Z",
          "timezoneIdentifier": "GMT",
          "warnings": [],
          "threads": {
            "thread": {
              "threadID": "thread",
              "rootTaskID": "thread",
              "title": "Legacy",
              "dailyTokens": {"\(todayKey)": 123},
              "checkpoint": {
                "path": "/tmp/legacy.jsonl",
                "fileSize": 20,
                "parsedOffset": 20,
                "seenCumulativeTotals": [123]
              },
              "isComplete": true
            },
            "old-thread": {
              "threadID": "old-thread",
              "rootTaskID": "old-thread",
              "title": "Old",
              "dailyTokens": {"2000-01-01": 456},
              "checkpoint": {
                "path": "/tmp/old.jsonl",
                "fileSize": 30,
                "parsedOffset": 30,
                "seenCumulativeTotals": [456]
              },
              "isComplete": true
            }
          }
        }
        """
        try Data(legacy.utf8).write(to: ledgerURL)

        let migrated = try UsageLedgerStore(fileURL: ledgerURL).load(timezoneIdentifier: "GMT")

        XCTAssertEqual(migrated.schemaVersion, 5)
        XCTAssertEqual(migrated.threads["thread"]?.dailyTokens[todayKey], 123)
        XCTAssertNil(migrated.threads["thread"]?.checkpoint)
        XCTAssertTrue(migrated.threads["thread"]?.quotaObservations.isEmpty == true)
        XCTAssertEqual(migrated.threads["old-thread"]?.checkpoint?.parsedOffset, 30)
    }

    func testMigratesOlderQuotaWeightsWithoutDiscardingCheckpoints() throws {
        let workspace = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let activeReset = now.addingTimeInterval(3_600)
        for sourceVersion in [2, 3, 4] {
            let ledgerURL = workspace.appendingPathComponent("usage-ledger-\(sourceVersion).json")
            let legacy = """
            {
              "schemaVersion": \(sourceVersion),
              "generatedAt": "\(formatter.string(from: now))",
              "timezoneIdentifier": "GMT",
              "warnings": [],
              "threads": {
                "thread": {
                  "threadID": "thread",
                  "rootTaskID": "thread",
                  "title": "Legacy active window",
                  "dailyTokens": {"2026-07-31": 123},
                  "quotaObservations": [{
                    "timestamp": "\(formatter.string(from: now))",
                    "tokenIncrement": 123,
                    "windows": [{
                      "durationMinutes": 10080,
                      "usedPercent": 12,
                      "resetsAt": "\(formatter.string(from: activeReset))"
                    }]
                  }],
                  "checkpoint": {
                    "path": "/tmp/legacy-active.jsonl",
                    "fileSize": 20,
                    "parsedOffset": 20,
                    "seenCumulativeTotals": [123]
                  },
                  "isComplete": true
                }
              }
            }
            """
            try Data(legacy.utf8).write(to: ledgerURL)

            let migrated = try UsageLedgerStore(fileURL: ledgerURL).load(timezoneIdentifier: "GMT")

            XCTAssertEqual(migrated.schemaVersion, 5, "source schema \(sourceVersion)")
            XCTAssertEqual(migrated.threads["thread"]?.dailyTokens["2026-07-31"], 123)
            XCTAssertTrue(migrated.threads["thread"]?.quotaObservations.isEmpty == true)
            XCTAssertEqual(migrated.threads["thread"]?.checkpoint?.parsedOffset, 20)
        }
    }

    func testMigratesExpiredRawTokenObservationsWithoutReparsingOldThreads() throws {
        let workspace = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let ledgerURL = workspace.appendingPathComponent("usage-ledger.json")
        let formatter = ISO8601DateFormatter()
        let now = Date()
        let expiredReset = now.addingTimeInterval(-3_600)
        let legacy = """
        {
          "schemaVersion": 3,
          "generatedAt": "\(formatter.string(from: now))",
          "timezoneIdentifier": "GMT",
          "warnings": [],
          "threads": {
            "thread": {
              "threadID": "thread",
              "rootTaskID": "thread",
              "title": "Expired raw-token calibration",
              "dailyTokens": {"2026-07-01": 123},
              "quotaObservations": [{
                "timestamp": "\(formatter.string(from: expiredReset.addingTimeInterval(-60)))",
                "tokenIncrement": 123,
                "windows": [{
                  "durationMinutes": 10080,
                  "usedPercent": 12,
                  "resetsAt": "\(formatter.string(from: expiredReset))"
                }]
              }],
              "checkpoint": {
                "path": "/tmp/legacy-expired.jsonl",
                "fileSize": 20,
                "parsedOffset": 20,
                "seenCumulativeTotals": [123]
              },
              "isComplete": true
            }
          }
        }
        """
        try Data(legacy.utf8).write(to: ledgerURL)

        let migrated = try UsageLedgerStore(fileURL: ledgerURL).load(timezoneIdentifier: "GMT")

        XCTAssertEqual(migrated.schemaVersion, 5)
        XCTAssertTrue(migrated.threads["thread"]?.quotaObservations.isEmpty == true)
        XCTAssertEqual(migrated.threads["thread"]?.checkpoint?.parsedOffset, 20)
        XCTAssertEqual(migrated.threads["thread"]?.dailyTokens["2026-07-01"], 123)
    }

    func testQuotaEstimatorUsesLocalStepsAndRejectsRemoteJumpAfterGap() throws {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let window = AccountQuotaWindow(
            durationMinutes: 10_080,
            usedPercent: 31,
            resetsAt: reset
        )
        let start = reset.addingTimeInterval(-5_000)
        let observations = [
            quotaObservation(at: start, task: "a", tokens: 100, percent: 12, reset: reset),
            quotaObservation(at: start.addingTimeInterval(10), task: "a", tokens: 400, percent: 12, reset: reset),
            quotaObservation(at: start.addingTimeInterval(20), task: "small", tokens: 100, percent: 12, reset: reset),
            quotaObservation(at: start.addingTimeInterval(30), task: "a", tokens: 500, percent: 13, reset: reset),
            // The 13% -> 30% jump happened while this Mac was inactive and must be ignored.
            quotaObservation(at: start.addingTimeInterval(2_000), task: "b", tokens: 100, percent: 30, reset: reset),
            quotaObservation(at: start.addingTimeInterval(2_010), task: "b", tokens: 400, percent: 30, reset: reset),
            quotaObservation(at: start.addingTimeInterval(2_020), task: "b", tokens: 600, percent: 31, reset: reset)
        ]
        let history = UsageHistory(
            generatedAt: start.addingTimeInterval(2_030),
            timezoneIdentifier: "GMT",
            days: [],
            quotaObservations: observations
        )

        let estimates = TaskQuotaEstimator.estimates(
            history: history,
            window: window,
            now: start.addingTimeInterval(2_030)
        )
        let firstDay = dayKey(start)

        XCTAssertEqual(try XCTUnwrap(estimates["\(firstDay)|a"]).percent, 1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(estimates["\(firstDay)|small"]).percent, 0.1, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(estimates["\(firstDay)|b"]).percent, 1.1, accuracy: 0.0001)
        XCTAssertLessThan(estimates.values.reduce(0) { $0 + $1.percent }, 3)
        XCTAssertTrue(estimates.values.allSatisfy { $0.confidence == .low })
    }

    func testQuotaEstimatorReportsMediumConfidenceAfterTenPointCalibrationSpan() throws {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let window = AccountQuotaWindow(
            durationMinutes: 10_080,
            usedPercent: 22,
            resetsAt: reset
        )
        let start = reset.addingTimeInterval(-1_000)
        var observations = [
            quotaObservation(at: start, task: "task", tokens: 0, percent: 12, reset: reset)
        ]
        for step in 0..<10 {
            observations.append(
                quotaObservation(
                    at: start.addingTimeInterval(Double(step * 20 + 10)),
                    task: "task",
                    tokens: 500,
                    percent: Double(12 + step),
                    reset: reset
                )
            )
            observations.append(
                quotaObservation(
                    at: start.addingTimeInterval(Double(step * 20 + 20)),
                    task: "task",
                    tokens: 500,
                    percent: Double(13 + step),
                    reset: reset
                )
            )
        }
        let history = UsageHistory(
            generatedAt: start.addingTimeInterval(220),
            timezoneIdentifier: "GMT",
            days: [],
            quotaObservations: observations
        )

        let estimate = try XCTUnwrap(
            TaskQuotaEstimator.estimates(
                history: history,
                window: window,
                now: start.addingTimeInterval(220)
            )["\(dayKey(start))|task"]
        )

        XCTAssertEqual(estimate.percent, 10, accuracy: 0.0001)
        XCTAssertEqual(estimate.confidence, .medium)
        XCTAssertEqual(estimate.observedStepCount, 10)
    }

    func testQuotaEstimatorCapsLocalTotalAndRejectsExpiredWindow() throws {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let window = AccountQuotaWindow(
            durationMinutes: 300,
            usedPercent: 0.5,
            resetsAt: reset
        )
        let start = reset.addingTimeInterval(-600)
        let history = UsageHistory(
            generatedAt: start.addingTimeInterval(30),
            timezoneIdentifier: "GMT",
            days: [],
            quotaObservations: [
                LocalQuotaUsageObservation(
                    timestamp: start,
                    rootTaskID: "task",
                    tokenIncrement: 0,
                    windows: [windowAt(percent: 0, reset: reset, duration: 300)]
                ),
                LocalQuotaUsageObservation(
                    timestamp: start.addingTimeInterval(10),
                    rootTaskID: "task",
                    tokenIncrement: 1_000,
                    windows: [windowAt(percent: 0, reset: reset, duration: 300)]
                ),
                LocalQuotaUsageObservation(
                    timestamp: start.addingTimeInterval(20),
                    rootTaskID: "task",
                    tokenIncrement: 1_000,
                    windows: [windowAt(percent: 1, reset: reset, duration: 300)]
                )
            ]
        )

        let active = TaskQuotaEstimator.estimates(
            history: history,
            window: window,
            now: start.addingTimeInterval(30)
        )
        let expired = TaskQuotaEstimator.estimates(
            history: history,
            window: window,
            now: reset
        )

        XCTAssertEqual(
            try XCTUnwrap(active["\(dayKey(start))|task"]).percent,
            0.5,
            accuracy: 0.0001
        )
        XCTAssertTrue(expired.isEmpty)
    }

    func testQuotaEstimatorSeparatesTheSameRootTaskByLocalDay() throws {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let window = AccountQuotaWindow(
            durationMinutes: 10_080,
            usedPercent: 4,
            resetsAt: reset
        )
        let dayOne = Date(timeIntervalSince1970: 1_799_900_000)
        let dayTwo = dayOne.addingTimeInterval(86_400)
        let history = UsageHistory(
            generatedAt: dayTwo.addingTimeInterval(30),
            timezoneIdentifier: "GMT",
            days: [],
            quotaObservations: [
                quotaObservation(at: dayOne, task: "shared", tokens: 0, percent: 0, reset: reset),
                quotaObservation(
                    at: dayOne.addingTimeInterval(10),
                    task: "shared",
                    tokens: 1_000,
                    percent: 1,
                    reset: reset
                ),
                quotaObservation(at: dayTwo, task: "shared", tokens: 100, percent: 2, reset: reset),
                quotaObservation(
                    at: dayTwo.addingTimeInterval(10),
                    task: "shared",
                    tokens: 1_000,
                    percent: 3,
                    reset: reset
                )
            ]
        )

        let estimates = TaskQuotaEstimator.estimates(
            history: history,
            window: window,
            now: dayTwo.addingTimeInterval(30)
        )

        XCTAssertEqual(estimates.count, 2)
        XCTAssertEqual(
            try XCTUnwrap(estimates["\(dayKey(dayOne))|shared"]).percent,
            1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            try XCTUnwrap(estimates["\(dayKey(dayTwo))|shared"]).percent,
            1.1,
            accuracy: 0.0001
        )
    }

    func testQuotaEstimatorUsesCreditWeightInsteadOfTreatingRawTokensAsEquivalent() throws {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let window = AccountQuotaWindow(
            durationMinutes: 10_080,
            usedPercent: 1,
            resetsAt: reset
        )
        let start = reset.addingTimeInterval(-1_000)
        let history = UsageHistory(
            generatedAt: start.addingTimeInterval(30),
            timezoneIdentifier: "GMT",
            days: [],
            quotaObservations: [
                quotaObservation(at: start, task: "raw-heavy", tokens: 0, percent: 0, reset: reset),
                quotaObservation(
                    at: start.addingTimeInterval(10),
                    task: "raw-heavy",
                    tokens: 1_000,
                    quotaUsageWeight: 100,
                    percent: 0,
                    reset: reset
                ),
                quotaObservation(
                    at: start.addingTimeInterval(20),
                    task: "credit-heavy",
                    tokens: 100,
                    quotaUsageWeight: 1_000,
                    percent: 1,
                    reset: reset
                )
            ]
        )

        let estimates = TaskQuotaEstimator.estimates(
            history: history,
            window: window,
            now: start.addingTimeInterval(30)
        )
        let date = dayKey(start)
        let rawHeavy = try XCTUnwrap(estimates["\(date)|raw-heavy"])
        let creditHeavy = try XCTUnwrap(estimates["\(date)|credit-heavy"])

        XCTAssertEqual(rawHeavy.percent, 1.0 / 11.0, accuracy: 0.0001)
        XCTAssertEqual(creditHeavy.percent, 10.0 / 11.0, accuracy: 0.0001)
        XCTAssertGreaterThan(creditHeavy.percent, rawHeavy.percent)
    }

    func testQuotaEstimatorRejectsConcurrentSnapshotOutlierWithinActiveSegment() throws {
        let reset = Date(timeIntervalSince1970: 1_800_000_000)
        let window = AccountQuotaWindow(
            durationMinutes: 10_080,
            usedPercent: 8,
            resetsAt: reset
        )
        let start = reset.addingTimeInterval(-1_000)
        var observations = [
            quotaObservation(at: start, task: "normal", tokens: 0, percent: 0, reset: reset)
        ]
        for step in 1...5 {
            observations.append(
                quotaObservation(
                    at: start.addingTimeInterval(Double(step * 10)),
                    task: "normal",
                    tokens: 1_000,
                    percent: Double(step),
                    reset: reset
                )
            )
        }
        observations.append(
            quotaObservation(
                at: start.addingTimeInterval(60),
                task: "concurrent",
                tokens: 100,
                percent: 8,
                reset: reset
            )
        )
        let history = UsageHistory(
            generatedAt: start.addingTimeInterval(70),
            timezoneIdentifier: "GMT",
            days: [],
            quotaObservations: observations
        )

        let estimates = TaskQuotaEstimator.estimates(
            history: history,
            window: window,
            now: start.addingTimeInterval(70)
        )
        let concurrent = try XCTUnwrap(estimates["\(dayKey(start))|concurrent"])

        XCTAssertEqual(concurrent.percent, 0.1, accuracy: 0.0001)
        XCTAssertEqual(concurrent.observedStepCount, 0)
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

    func testGenericDatabaseTitleFallsBackToConcreteConversationName() async throws {
        let workspace = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: workspace) }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let rollout = workspace.appendingPathComponent("conversation.jsonl")
        try Data(
            (tokenLine(timestamp: "2026-07-18T00:00:00Z", cumulative: 8, increment: 8) + "\n").utf8
        ).write(to: rollout)
        let database = workspace.appendingPathComponent("state_test.sqlite")
        try createDatabase(
            at: database,
            threads: [("thread", "对话 1", rollout.path, 8, 1)],
            edges: [],
            firstUserMessages: ["thread": "为 Codex Toolbox 修复菜单栏折叠摘要"]
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai"))
        let reader = LocalCodexUsageReader(
            codexHome: workspace,
            stateDatabaseURL: database,
            ledgerURL: workspace.appendingPathComponent("ledger.json")
        )

        let history = try await reader.readUsage(calendar: calendar)

        XCTAssertEqual(
            history.summary(for: "2026-07-18")?.tasks.first?.title,
            "为 Codex Toolbox 修复菜单栏折叠摘要"
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalCodexUsageReaderTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func tokenLine(
        timestamp: String,
        cumulative: Int64,
        increment: Int64,
        quotaPercent: Double? = nil,
        quotaReset: Date? = nil
    ) -> String {
        var payload: [String: Any] = [
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
        if let quotaPercent, let quotaReset {
            payload["rate_limits"] = [
                "limit_id": "opaque-limit-id",
                "plan_type": "prolite",
                "credits": ["balance": "must-not-persist"],
                "primary": [
                    "used_percent": quotaPercent,
                    "window_minutes": 10_080,
                    "resets_at": quotaReset.timeIntervalSince1970
                ]
            ]
        }
        let event: [String: Any] = [
            "timestamp": timestamp,
            "type": "event_msg",
            "payload": payload
        ]
        let data = try! JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func turnContextLine(model: String) -> String {
        let event: [String: Any] = [
            "type": "turn_context",
            "payload": ["model": model]
        ]
        let data = try! JSONSerialization.data(withJSONObject: event, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func quotaObservation(
        at timestamp: Date,
        task: String,
        tokens: Int64,
        quotaUsageWeight: Double? = nil,
        percent: Double,
        reset: Date
    ) -> LocalQuotaUsageObservation {
        LocalQuotaUsageObservation(
            timestamp: timestamp,
            rootTaskID: task,
            tokenIncrement: tokens,
            quotaUsageWeight: quotaUsageWeight,
            windows: [
                AccountQuotaWindow(
                    durationMinutes: 10_080,
                    usedPercent: percent,
                    resetsAt: reset
                )
            ]
        )
    }

    private func dayKey(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private func windowAt(
        percent: Double,
        reset: Date,
        duration: Int
    ) -> AccountQuotaWindow {
        AccountQuotaWindow(
            durationMinutes: duration,
            usedPercent: percent,
            resetsAt: reset
        )
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
        archivedThreadIDs: Set<String> = [],
        firstUserMessages: [String: String] = [:]
    ) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw NSError(domain: "SQLiteTest", code: 1)
        }
        defer { sqlite3_close(database) }
        try execute(
            "CREATE TABLE threads (id TEXT PRIMARY KEY, title TEXT, rollout_path TEXT, " +
            "tokens_used INTEGER, archived INTEGER, created_at INTEGER, updated_at INTEGER, " +
            "first_user_message TEXT, preview TEXT, cwd TEXT); " +
            "CREATE TABLE thread_spawn_edges (parent_thread_id TEXT, child_thread_id TEXT);",
            in: database
        )
        for (index, thread) in threads.enumerated() {
            try execute(
                "INSERT INTO threads VALUES (" +
                "'\(sql(thread.id))','\(sql(thread.title))','\(sql(thread.rollout))'," +
                "\(thread.tokens),\(archivedThreadIDs.contains(thread.id) ? 1 : 0),\(index + 1),\(thread.updated)," +
                "'\(sql(firstUserMessages[thread.id] ?? ""))','','');",
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
