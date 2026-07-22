import Foundation
import SQLite3

public enum LocalCodexUsageError: LocalizedError, Sendable {
    case stateDatabaseNotFound(URL)
    case unreadableStateDatabase(String)
    case unsupportedLedgerSchema(Int)

    public var errorDescription: String? {
        switch self {
        case let .stateDatabaseNotFound(home):
            "在 \(home.path) 中未找到可读取的 Codex 状态数据库。"
        case let .unreadableStateDatabase(message):
            "Codex 状态数据库不可读取：\(message)"
        case let .unsupportedLedgerSchema(version):
            "Token 历史账本版本不受支持（schemaVersion \(version)）。"
        }
    }
}

private struct CodexThreadRow: Sendable {
    let id: String
    let title: String
    let rolloutPath: String
    let createdAt: Int64
}

private enum TaskTitleResolver {
    static func resolve(
        title: String,
        firstUserMessage: String,
        preview: String,
        workingDirectory: String
    ) -> String {
        let normalizedTitle = normalized(title)
        let fallbacks = [firstUserMessage, preview].map(normalized).filter { !$0.isEmpty }

        if !normalizedTitle.isEmpty, !isGeneric(normalizedTitle) {
            return normalizedTitle
        }
        if let concreteFallback = fallbacks.first(where: { !isGeneric($0) }) {
            return concreteFallback
        }
        if let fallback = fallbacks.first { return fallback }

        let directoryName = URL(fileURLWithPath: workingDirectory).lastPathComponent
        if !directoryName.isEmpty, directoryName != "/" {
            return "\(directoryName) 中的任务"
        }
        return normalizedTitle.isEmpty ? "未命名任务" : normalizedTitle
    }

    private static func normalized(_ value: String) -> String {
        let words = value.split(whereSeparator: \.isWhitespace)
        return String(words.joined(separator: " ").prefix(120))
    }

    private static func isGeneric(_ value: String) -> Bool {
        value.range(
            of: #"^(?:任务|对话|task|conversation)\s*#?\s*\d+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }
}

private struct CodexThreadInventory: Sendable {
    let threads: [String: CodexThreadRow]
    let parentByChild: [String: String]
}

private struct DatabaseScore: Comparable, Sendable {
    let latestUpdate: Int64
    let taskCount: Int64
    let totalTokens: Int64
    let path: String

    static func < (lhs: DatabaseScore, rhs: DatabaseScore) -> Bool {
        if lhs.latestUpdate != rhs.latestUpdate { return lhs.latestUpdate < rhs.latestUpdate }
        if lhs.taskCount != rhs.taskCount { return lhs.taskCount < rhs.taskCount }
        if lhs.totalTokens != rhs.totalTokens { return lhs.totalTokens < rhs.totalTokens }
        return lhs.path < rhs.path
    }
}

private final class ReadOnlySQLiteDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw LocalCodexUsageError.unreadableStateDatabase(message)
        }
    }

    deinit {
        if let handle { sqlite3_close(handle) }
    }

    func score(path: String) throws -> DatabaseScore {
        let statement = try prepare(
            "SELECT COALESCE(MAX(updated_at), 0), COUNT(*), " +
            "COALESCE(SUM(tokens_used), 0) FROM threads"
        )
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw databaseError() }
        return DatabaseScore(
            latestUpdate: sqlite3_column_int64(statement, 0),
            taskCount: sqlite3_column_int64(statement, 1),
            totalTokens: sqlite3_column_int64(statement, 2),
            path: path
        )
    }

    func inventory() throws -> CodexThreadInventory {
        let columns = try tableColumns("threads")
        let firstUserMessage = columns.contains("first_user_message")
            ? "COALESCE(first_user_message, '')" : "''"
        let preview = columns.contains("preview") ? "COALESCE(preview, '')" : "''"
        let workingDirectory = columns.contains("cwd") ? "COALESCE(cwd, '')" : "''"
        let statement = try prepare(
            "SELECT id, COALESCE(title, ''), COALESCE(rollout_path, ''), " +
            "COALESCE(created_at, 0), \(firstUserMessage), \(preview), " +
            "\(workingDirectory) FROM threads"
        )
        defer { sqlite3_finalize(statement) }
        var threads: [String: CodexThreadRow] = [:]
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = text(statement, column: 0)
            guard !id.isEmpty else { continue }
            threads[id] = CodexThreadRow(
                id: id,
                title: TaskTitleResolver.resolve(
                    title: text(statement, column: 1),
                    firstUserMessage: text(statement, column: 4),
                    preview: text(statement, column: 5),
                    workingDirectory: text(statement, column: 6)
                ),
                rolloutPath: text(statement, column: 2),
                createdAt: sqlite3_column_int64(statement, 3)
            )
        }

        var parents: [String: String] = [:]
        if let edgeStatement = try? prepare(
            "SELECT parent_thread_id, child_thread_id FROM thread_spawn_edges"
        ) {
            defer { sqlite3_finalize(edgeStatement) }
            while sqlite3_step(edgeStatement) == SQLITE_ROW {
                let parent = text(edgeStatement, column: 0)
                let child = text(edgeStatement, column: 1)
                if !parent.isEmpty, !child.isEmpty { parents[child] = parent }
            }
        }
        return CodexThreadInventory(threads: threads, parentByChild: parents)
    }

    private func tableColumns(_ table: String) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        var columns: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            columns.insert(text(statement, column: 1))
        }
        return columns
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard let handle,
              sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw databaseError()
        }
        return statement
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func databaseError() -> LocalCodexUsageError {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        return .unreadableStateDatabase(message)
    }
}

struct ParsedRollout: Sendable {
    let dailyTokens: [String: Int64]
    let quotaObservations: [ThreadQuotaUsageObservation]
    let checkpoint: UsageRolloutCheckpoint
    let damagedLineCount: Int
    let resumedFromCheckpoint: Bool
}

enum RolloutTokenParser {
    static func parse(
        fileURL: URL,
        previous: ThreadUsageLedgerEntry?,
        calendar: Calendar
    ) throws -> ParsedRollout {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let currentSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let previousCheckpoint = previous?.checkpoint
        let canResume = previousCheckpoint.map {
            $0.path == fileURL.path && currentSize >= Int64($0.parsedOffset)
        } ?? false
        let startOffset = canResume ? previousCheckpoint?.parsedOffset ?? 0 : 0
        var dailyTokens = canResume ? previous?.dailyTokens ?? [:] : [:]
        var quotaObservations = canResume ? previous?.quotaObservations ?? [] : []
        var seenTotals = Set(canResume ? previousCheckpoint?.seenCumulativeTotals ?? [] : [])
        var damagedLineCount = 0

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: startOffset)

        var buffer = Data()
        var parsedOffset = startOffset
        while true {
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                let consumed = buffer.distance(from: buffer.startIndex, to: newline) + 1
                buffer.removeSubrange(buffer.startIndex...newline)
                parsedOffset += UInt64(consumed)
                guard !line.isEmpty else { continue }
                guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    damagedLineCount += 1
                    continue
                }
                guard event["type"] as? String == "event_msg",
                      let payload = event["payload"] as? [String: Any],
                      payload["type"] as? String == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let totalUsage = info["total_token_usage"] as? [String: Any],
                      let cumulative = integer(totalUsage["total_tokens"]),
                      cumulative > 0,
                      seenTotals.insert(cumulative).inserted,
                      let lastUsage = info["last_token_usage"] as? [String: Any],
                      let increment = integer(lastUsage["total_tokens"]),
                      increment >= 0,
                      let timestamp = date(event["timestamp"]) else { continue }
                let day = dayKey(timestamp, calendar: calendar)
                dailyTokens[day, default: 0] += increment
                let windows = quotaWindows(from: payload["rate_limits"])
                if !windows.isEmpty {
                    quotaObservations.append(
                        ThreadQuotaUsageObservation(
                            timestamp: timestamp,
                            tokenIncrement: increment,
                            windows: windows
                        )
                    )
                }
            }
        }

        return ParsedRollout(
            dailyTokens: dailyTokens,
            quotaObservations: quotaObservations,
            checkpoint: UsageRolloutCheckpoint(
                path: fileURL.path,
                fileSize: currentSize,
                parsedOffset: parsedOffset,
                seenCumulativeTotals: seenTotals.sorted()
            ),
            damagedLineCount: damagedLineCount,
            resumedFromCheckpoint: canResume
        )
    }

    private static func integer(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func quotaWindows(from value: Any?) -> [AccountQuotaWindow] {
        guard let rateLimits = value as? [String: Any] else { return [] }
        var seen = Set<String>()
        return ["primary", "secondary"].compactMap { key in
            guard let row = rateLimits[key] as? [String: Any],
                  let duration = integer(row["window_minutes"]),
                  duration > 0,
                  duration <= Int64(Int.max),
                  let usedPercent = number(row["used_percent"]),
                  usedPercent.isFinite,
                  let resetsAt = date(row["resets_at"]) else { return nil }
            let identity = "\(duration)|\(Int64(resetsAt.timeIntervalSince1970))"
            guard seen.insert(identity).inserted else { return nil }
            return AccountQuotaWindow(
                durationMinutes: Int(duration),
                usedPercent: usedPercent,
                resetsAt: resetsAt
            )
        }
    }

    private static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let string = value as? String else { return nil }
        return try? Date(string, strategy: .iso8601)
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

public actor LocalCodexUsageReader: CodexUsageReading, UsageHistoryClearing {
    private let codexHome: URL
    private let explicitDatabaseURL: URL?
    private let fileManager: FileManager
    private let ledgerStore: UsageLedgerStore

    public init(
        codexHome: URL? = nil,
        stateDatabaseURL: URL? = nil,
        ledgerURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let resolvedHome: URL
        if let codexHome {
            resolvedHome = codexHome
        } else if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"], !configured.isEmpty {
            resolvedHome = URL(fileURLWithPath: configured, isDirectory: true)
        } else {
            resolvedHome = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex", isDirectory: true)
        }
        self.codexHome = resolvedHome.standardizedFileURL
        explicitDatabaseURL = stateDatabaseURL?.standardizedFileURL
        self.fileManager = fileManager
        let defaultLedger = ApplicationSupportLayout(fileManager: fileManager).usageLedgerURL
        ledgerStore = UsageLedgerStore(fileURL: ledgerURL ?? defaultLedger)
    }

    public func selectedStateDatabase() throws -> URL {
        if let explicitDatabaseURL {
            guard fileManager.fileExists(atPath: explicitDatabaseURL.path) else {
                throw LocalCodexUsageError.stateDatabaseNotFound(codexHome)
            }
            _ = try ReadOnlySQLiteDatabase(url: explicitDatabaseURL).score(path: explicitDatabaseURL.path)
            return explicitDatabaseURL
        }

        let directories = [codexHome, codexHome.appendingPathComponent("sqlite", isDirectory: true)]
        var best: (DatabaseScore, URL)?
        for directory in directories {
            guard let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for candidate in contents where candidate.lastPathComponent.hasPrefix("state_")
                && candidate.pathExtension == "sqlite" {
                guard let database = try? ReadOnlySQLiteDatabase(url: candidate),
                      let score = try? database.score(path: candidate.path),
                      score.taskCount > 0 else { continue }
                if best == nil || best!.0 < score { best = (score, candidate) }
            }
        }
        guard let best else { throw LocalCodexUsageError.stateDatabaseNotFound(codexHome) }
        return best.1
    }

    public func readUsage(now: Date = Date(), calendar: Calendar = .current) async throws -> UsageHistory {
        let timezoneIdentifier = calendar.timeZone.identifier
        var ledger = try ledgerStore.load(timezoneIdentifier: timezoneIdentifier)
        let databaseURL = try selectedStateDatabase()
        let inventory = try ReadOnlySQLiteDatabase(url: databaseURL).inventory()
        let fallbackRollouts = buildRolloutIndex()
        var warnings: [String] = []

        for thread in inventory.threads.values {
            let rootID = rootID(for: thread.id, parents: inventory.parentByChild)
            let previous = ledger.threads[thread.id]
            guard let rolloutURL = rolloutURL(for: thread, fallbackIndex: fallbackRollouts) else {
                var preserved = previous ?? ThreadUsageLedgerEntry(
                    threadID: thread.id,
                    rootTaskID: rootID,
                    title: thread.title,
                    dailyTokens: [:],
                    checkpoint: nil,
                    isComplete: false
                )
                preserved.rootTaskID = rootID
                preserved.title = thread.title
                preserved.isComplete = false
                ledger.threads[thread.id] = preserved
                warnings.append("任务 \(thread.id) 的 rollout 文件不可用，历史可能不完整。")
                continue
            }
            do {
                let parsed = try RolloutTokenParser.parse(
                    fileURL: rolloutURL,
                    previous: previous,
                    calendar: calendar
                )
                ledger.threads[thread.id] = ThreadUsageLedgerEntry(
                    threadID: thread.id,
                    rootTaskID: rootID,
                    title: thread.title,
                    dailyTokens: parsed.dailyTokens,
                    quotaObservations: parsed.quotaObservations,
                    checkpoint: parsed.checkpoint,
                    isComplete: parsed.damagedLineCount == 0
                        && (!parsed.resumedFromCheckpoint || previous?.isComplete != false)
                )
                if parsed.damagedLineCount > 0 {
                    warnings.append("任务 \(thread.id) 跳过了 \(parsed.damagedLineCount) 行损坏的 rollout 数据。")
                }
            } catch {
                var preserved = previous ?? ThreadUsageLedgerEntry(
                    threadID: thread.id,
                    rootTaskID: rootID,
                    title: thread.title,
                    dailyTokens: [:],
                    checkpoint: nil,
                    isComplete: false
                )
                preserved.rootTaskID = rootID
                preserved.title = thread.title
                preserved.isComplete = false
                ledger.threads[thread.id] = preserved
                warnings.append("任务 \(thread.id) 的 rollout 读取失败：\(error.localizedDescription)")
            }
        }

        // Threads no longer present in the selected database keep their recorded
        // history. This is required for archived/deleted local tasks.
        ledger.generatedAt = now
        ledger.warnings = warnings
        let history = history(from: ledger, now: now)
        try ledgerStore.save(ledger)
        return history
    }

    public func clearHistory() async throws {
        try ledgerStore.clear()
    }

    private func history(from ledger: VersionedUsageLedger, now: Date) -> UsageHistory {
        struct Aggregate {
            var tokens: Int64 = 0
            var memberIDs: Set<String> = []
            var complete = true
        }
        var byDayAndRoot: [String: [String: Aggregate]] = [:]
        var memberCountByRoot: [String: Int] = [:]
        var quotaObservations: [LocalQuotaUsageObservation] = []
        for entry in ledger.threads.values {
            memberCountByRoot[entry.rootTaskID, default: 0] += 1
            quotaObservations.append(
                contentsOf: entry.quotaObservations.map {
                    LocalQuotaUsageObservation(
                        timestamp: $0.timestamp,
                        rootTaskID: entry.rootTaskID,
                        tokenIncrement: $0.tokenIncrement,
                        windows: $0.windows
                    )
                }
            )
            for (day, tokens) in entry.dailyTokens {
                var aggregate = byDayAndRoot[day, default: [:]][entry.rootTaskID, default: Aggregate()]
                aggregate.tokens += tokens
                aggregate.memberIDs.insert(entry.threadID)
                aggregate.complete = aggregate.complete && entry.isComplete
                byDayAndRoot[day, default: [:]][entry.rootTaskID] = aggregate
            }
        }
        let days = byDayAndRoot.map { day, roots in
            let tasks = roots.map { rootID, aggregate in
                let root = ledger.threads[rootID]
                let fallback = ledger.threads.values.first { $0.rootTaskID == rootID }
                return DailyTaskUsage(
                    dateKey: day,
                    rootTaskID: rootID,
                    title: root?.title ?? fallback?.title ?? "未命名任务",
                    tokens: aggregate.tokens,
                    descendantCount: max(0, (memberCountByRoot[rootID] ?? aggregate.memberIDs.count) - 1)
                )
            }
            return DailyUsageSummary(
                dateKey: day,
                totalTokens: tasks.reduce(0) { $0 + $1.tokens },
                tasks: tasks,
                isComplete: roots.values.allSatisfy(\.complete)
            )
        }
        return UsageHistory(
            generatedAt: now,
            timezoneIdentifier: ledger.timezoneIdentifier,
            days: days,
            warnings: ledger.warnings,
            quotaObservations: quotaObservations
        )
    }

    private func rootID(for threadID: String, parents: [String: String]) -> String {
        var current = threadID
        var seen: Set<String> = []
        while let parent = parents[current], seen.insert(current).inserted {
            current = parent
        }
        return current
    }

    private func rolloutURL(for thread: CodexThreadRow, fallbackIndex: [String: URL]) -> URL? {
        if !thread.rolloutPath.isEmpty {
            let direct = URL(fileURLWithPath: thread.rolloutPath)
            if fileManager.fileExists(atPath: direct.path) { return direct }
        }
        return fallbackIndex.first { $0.key.contains(thread.id) }?.value
    }

    private func buildRolloutIndex() -> [String: URL] {
        var result: [String: URL] = [:]
        let roots = [
            codexHome.appendingPathComponent("archived_sessions", isDirectory: true),
            codexHome.appendingPathComponent("sessions", isDirectory: true)
        ]
        for root in roots {
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                result[url.lastPathComponent] = url
            }
        }
        return result
    }
}
