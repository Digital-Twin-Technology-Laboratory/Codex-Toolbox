import Foundation
import SQLite3

public enum LocalCodexUsageError: LocalizedError, Sendable {
    case stateDatabaseNotFound(URL)
    case unreadableStateDatabase(String)
    case unsupportedLedgerSchema(Int)
    case tokenTotalOutOfRange

    public var errorDescription: String? {
        switch self {
        case let .stateDatabaseNotFound(home):
            "在 \(home.path) 中未找到可读取的 Codex 状态数据库。"
        case let .unreadableStateDatabase(message):
            "Codex 状态数据库不可读取：\(message)"
        case .tokenTotalOutOfRange:
            "Token 历史数据超出可统计范围。"
        case let .unsupportedLedgerSchema(version):
            "Token 历史账本版本不受支持（schemaVersion \(version)）。"
        }
    }
}

private enum TokenLedgerArithmetic {
    static func adding(_ lhs: Int64, _ rhs: Int64) throws -> Int64 {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        guard lhs >= 0, rhs >= 0, !overflow else { throw LocalCodexUsageError.tokenTotalOutOfRange }
        return sum
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
        displayName: String,
        title: String,
        firstUserMessage: String,
        preview: String,
        workingDirectory: String
    ) -> String {
        // Codex keeps the sidebar name separately from the initial user message.
        // An explicit name wins even if it resembles a generic fallback title.
        let normalizedName = normalized(displayName)
        if !normalizedName.isEmpty { return normalizedName }
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

struct StateDatabaseReadFailure: Error {
    let code: Int32
    let message: String

    /// Codex removes `-wal`/`-shm` when its last connection closes; a read that
    /// races that cleanup fails briefly with CANTOPEN or BUSY.
    var isTransient: Bool {
        [SQLITE_CANTOPEN, SQLITE_BUSY, SQLITE_LOCKED].contains(code & 0xff)
    }
}

enum StateDatabaseRetry {
    static let delays: [TimeInterval] = [0.05, 0.2]

    static func run<T>(
        delays: [TimeInterval] = delays,
        canRetry: () -> Bool = { true },
        sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        _ body: () throws -> T
    ) throws -> T {
        var attempt = 0
        while true {
            do {
                return try body()
            } catch let failure as StateDatabaseReadFailure {
                guard failure.isTransient, attempt < delays.count, canRetry() else { throw failure }
                try Task.checkCancellation()
                sleep(delays[attempt])
                attempt += 1
            }
        }
    }
}

private final class ReadOnlySQLiteDatabase {
    private var handle: OpaquePointer?

    static func read<T>(_ url: URL, _ body: (ReadOnlySQLiteDatabase) throws -> T) throws -> T {
        do {
            return try StateDatabaseRetry.run(canRetry: { FileManager.default.fileExists(atPath: url.path) }) {
                do {
                    return try body(ReadOnlySQLiteDatabase(url: url, immutable: false))
                } catch let failure as StateDatabaseReadFailure
                    where failure.code & 0xff == SQLITE_CANTOPEN && !hasPendingWAL(url) {
                    // A read-only connection cannot recreate the -wal/-shm files that Codex
                    // removes on close. Without WAL content the main file is fully checkpointed.
                    return try body(ReadOnlySQLiteDatabase(url: url, immutable: true))
                }
            }
        } catch let failure as StateDatabaseReadFailure {
            throw LocalCodexUsageError.unreadableStateDatabase(failure.message)
        }
    }

    private static func hasPendingWAL(_ url: URL) -> Bool {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path + "-wal")
        return ((attributes?[.size] as? NSNumber)?.int64Value ?? 0) > 0
    }

    private init(url: URL, immutable: Bool) throws {
        var flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        var location = url.path
        if immutable {
            var components = URLComponents()
            components.scheme = "file"
            components.path = url.path
            components.query = "immutable=1"
            location = components.string ?? location
            flags |= SQLITE_OPEN_URI
        }
        let result = sqlite3_open_v2(location, &handle, flags, nil)
        guard result == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let handle { sqlite3_close(handle) }
            handle = nil
            throw StateDatabaseReadFailure(code: result, message: message)
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
        guard try step(statement) else { throw databaseError() }
        return DatabaseScore(
            latestUpdate: sqlite3_column_int64(statement, 0),
            taskCount: sqlite3_column_int64(statement, 1),
            totalTokens: sqlite3_column_int64(statement, 2),
            path: path
        )
    }

    func inventory() throws -> CodexThreadInventory {
        let columns = try tableColumns("threads")
        let displayName = columns.contains("name") ? "COALESCE(name, '')" : "''"
        let firstUserMessage = columns.contains("first_user_message")
            ? "COALESCE(first_user_message, '')" : "''"
        let preview = columns.contains("preview") ? "COALESCE(preview, '')" : "''"
        let workingDirectory = columns.contains("cwd") ? "COALESCE(cwd, '')" : "''"
        let statement = try prepare(
            "SELECT id, COALESCE(title, ''), COALESCE(rollout_path, ''), " +
            "COALESCE(created_at, 0), \(firstUserMessage), \(preview), " +
            "\(workingDirectory), \(displayName) FROM threads"
        )
        defer { sqlite3_finalize(statement) }
        var threads: [String: CodexThreadRow] = [:]
        while try step(statement) {
            let id = text(statement, column: 0)
            guard !id.isEmpty else { continue }
            threads[id] = CodexThreadRow(
                id: id,
                title: TaskTitleResolver.resolve(
                    displayName: text(statement, column: 7),
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
            while try step(edgeStatement) {
                let parent = text(edgeStatement, column: 0)
                let child = text(edgeStatement, column: 1)
                if !parent.isEmpty, !child.isEmpty { parents[child] = parent }
            }
        }
        return CodexThreadInventory(threads: threads, parentByChild: parents)
    }

    func nativeCatalogue(now: Date) throws -> NativeCatalogue {
        let columns = try tableColumns("threads")
        guard columns.contains("updated_at"), columns.contains("created_at") else {
            throw LocalCodexUsageError.unreadableStateDatabase("缺少聊天时间字段")
        }
        let inventory = try inventory()
        let since = now.addingTimeInterval(-30 * 86400)
        // Archived tasks can still appear in the selected day's consumption ranking.
        let stmt = try prepare("SELECT id FROM threads WHERE updated_at >= \(Int64(since.timeIntervalSince1970)) ORDER BY updated_at DESC, id")
        defer { sqlite3_finalize(stmt) }
        var active: [String] = []
        while try step(stmt) {
            active.append(text(stmt, column: 0))
        }
        var seenRoots = Set<String>()
        let roots = active.compactMap { id -> String? in
            var root = id; var visited = Set<String>()
            while let parent = inventory.parentByChild[root] {
                guard visited.insert(root).inserted, visited.count <= 1000 else { return nil }
                root = parent
            }
            return seenRoots.insert(root).inserted ? root : nil
        }
        var children: [String: [String]] = [:]
        for (child, parent) in inventory.parentByChild { children[parent, default: []].append(child) }
        var result: [NativeThread] = []; var excluded = 0
        var owned = Set<String>()
        for id in roots {
            guard let root = inventory.threads[id], UUID(uuidString: id) != nil else { excluded += 1; continue }
            var visited: Set<String> = [id]; var queue = children[id] ?? []
            var invalid = false
            while let child = queue.popLast() {
                guard UUID(uuidString: child) != nil, visited.insert(child).inserted else { invalid = true; break }
                queue += children[child] ?? []
                if visited.count > 1000 { invalid = true; break }
            }
            if invalid || !owned.isDisjoint(with: visited) { excluded += 1; continue }
            owned.formUnion(visited)
            result.append(NativeThread(id: id, title: root.title,
                createdAt: root.createdAt > 0 ? Date(timeIntervalSince1970: Double(root.createdAt)).ISO8601Format() : nil,
                descendantIDs: visited.subtracting([id]).sorted(),
                earliestCreatedAt: visited.allSatisfy({ (inventory.threads[$0]?.createdAt ?? 0) > 0 })
                    ? visited.compactMap { inventory.threads[$0]?.createdAt }.min().map { Date(timeIntervalSince1970: Double($0)).ISO8601Format() }
                    : nil))
        }
        return NativeCatalogue(threads: result, eligibleCount: roots.count, excludedCount: excluded, since: since.ISO8601Format())
    }

    private func tableColumns(_ table: String) throws -> Set<String> {
        let statement = try prepare("PRAGMA table_info(\(table))")
        defer { sqlite3_finalize(statement) }
        var columns: Set<String> = []
        while try step(statement) {
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

    /// A failed step must not look like the end of the table.
    private func step(_ statement: OpaquePointer) throws -> Bool {
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw databaseError()
        }
    }

    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else { return "" }
        return String(cString: value)
    }

    private func databaseError() -> StateDatabaseReadFailure {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
        return StateDatabaseReadFailure(code: handle.map(sqlite3_errcode) ?? SQLITE_ERROR, message: message)
    }
}

struct RolloutPendingData: Sendable {
    var path: String
    var fileIdentity: UInt64?
    var parsedOffset: UInt64
    var observedOffset: UInt64
    var modifiedAt: Date?
    var data: Data
}

struct ParsedRollout: Sendable {
    let dailyTokens: [String: Int64]
    let quotaObservations: [ThreadQuotaUsageObservation]
    let checkpoint: UsageRolloutCheckpoint
    let damagedLineCount: Int
    let resumedFromCheckpoint: Bool
    var pending: RolloutPendingData? = nil
    var bytesRead: Int = 0
}

enum QuotaUsageWeighting {
    // Compatibility fallback for pre-schema-7 callers. Standard-mode rates
    // are normalized against GPT-5.6 Terra's 50-credit input-token rate:
    // https://help.openai.com/en/articles/20001106-codex-rate-card
    // Schema 7 uses the versioned manifest and execution context instead.
    private struct Multipliers {
        let input: Double
        let cachedInput: Double
        let output: Double
    }

    static func weight(
        lastUsage: [String: Any],
        modelID: String?,
        fallbackTokens: Int64
    ) -> Double {
        guard let multipliers = multipliers(for: modelID),
              let input = number(lastUsage["input_tokens"]),
              let cached = number(lastUsage["cached_input_tokens"]),
              let output = number(lastUsage["output_tokens"]),
              input >= 0,
              cached >= 0,
              output >= 0 else {
            return Double(max(0, fallbackTokens))
        }
        let boundedCached = min(input, cached)
        let weighted = (input - boundedCached) * multipliers.input
            + boundedCached * multipliers.cachedInput
            + output * multipliers.output
        return weighted.isFinite ? max(0, weighted) : Double(max(0, fallbackTokens))
    }

    private static func multipliers(for modelID: String?) -> Multipliers? {
        guard let modelID = modelID?.lowercased() else { return nil }
        if modelID.contains("gpt-5.6-terra") {
            return Multipliers(input: 1, cachedInput: 0.1, output: 6)
        }
        if modelID.contains("gpt-5.6-luna") {
            return Multipliers(input: 0.1, cachedInput: 0.01, output: 0.6)
        }
        if modelID.contains("gpt-5.6-sol") || modelID.contains("gpt-5.6") {
            return Multipliers(input: 2.5, cachedInput: 0.25, output: 15)
        }
        if modelID.contains("gpt-5.5-cyber") {
            return Multipliers(input: 6.25, cachedInput: 0.625, output: 37.5)
        }
        if modelID.contains("gpt-5.5") {
            return Multipliers(input: 2.5, cachedInput: 0.25, output: 15)
        }
        if modelID.contains("gpt-5.4-mini") {
            return Multipliers(input: 0.375, cachedInput: 0.0375, output: 2.26)
        }
        if modelID.contains("gpt-5.4") {
            return Multipliers(input: 1.25, cachedInput: 0.125, output: 7.5)
        }
        if modelID.contains("gpt-5.3-codex-spark") {
            return nil
        }
        if modelID.contains("gpt-5.3-codex") || modelID.contains("gpt-5.2") {
            return Multipliers(input: 0.875, cachedInput: 0.0875, output: 7)
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }
}

enum RolloutTokenParser {
    static func parse(
        fileURL: URL,
        previous: ThreadUsageLedgerEntry?,
        calendar: Calendar,
        rateCard: RateCardManifest? = nil,
        rateCardMode: RateCardMode = .automatic,
        pending: RolloutPendingData? = nil
    ) throws -> ParsedRollout {
        try Task.checkCancellation()
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let currentSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let previousCheckpoint = previous?.checkpoint
        let fileIdentity = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value
        let modifiedAt = attributes[.modificationDate] as? Date
        if let previousCheckpoint,
           previousCheckpoint.path == fileURL.path,
           currentSize == previousCheckpoint.fileSize,
           previousCheckpoint.fileIdentity != nil,
           previousCheckpoint.fileIdentity == fileIdentity,
           previousCheckpoint.modifiedAt == modifiedAt {
            return ParsedRollout(
                dailyTokens: previous?.dailyTokens ?? [:],
                quotaObservations: previous?.quotaObservations ?? [],
                checkpoint: previousCheckpoint,
                damagedLineCount: 0,
                resumedFromCheckpoint: true, pending: pending
            )
        }
        var bytesRead = 0
        var prefixMatches = true
        if let digest = previousCheckpoint?.prefixDigest, let length = previousCheckpoint?.prefixLength {
            let prefixHandle = try FileHandle(forReadingFrom: fileURL)
            defer { try? prefixHandle.close() }
            var boundary = try prefixHandle.read(upToCount: length) ?? Data()
            let offset = previousCheckpoint?.parsedOffset ?? 0
            try prefixHandle.seek(toOffset: offset >= UInt64(length) ? offset - UInt64(length) : 0)
            boundary.append(try prefixHandle.read(upToCount: length) ?? Data())
            bytesRead += boundary.count
            prefixMatches = IncrementalUsageDatabase.fingerprint(boundary) == digest
        }
        let canResume = prefixMatches && (previousCheckpoint.map {
            $0.path == fileURL.path && currentSize >= Int64($0.parsedOffset)
                && ($0.fileIdentity == nil || $0.fileIdentity == fileIdentity)
                && !(currentSize == $0.fileSize && $0.modifiedAt != nil && $0.modifiedAt != modifiedAt)
        } ?? false)
        let startOffset = canResume ? previousCheckpoint?.parsedOffset ?? 0 : 0
        var dailyTokens = canResume ? previous?.dailyTokens ?? [:] : [:]
        var quotaObservations = canResume ? previous?.quotaObservations ?? [] : []
        var seenTotals = Set(canResume ? previousCheckpoint?.seenCumulativeTotals ?? [] : [])
        var currentContext = canResume
            ? previousCheckpoint?.lastExecutionContext
                ?? UsageExecutionContext(
                    modelID: previousCheckpoint?.lastModelID,
                    reasoningEffort: nil,
                    serviceTier: nil
                )
            : UsageExecutionContext(modelID: nil, reasoningEffort: nil, serviceTier: nil)
        var damagedLineCount = 0

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var buffer = Data()
        var readOffset = startOffset
        if canResume, let pending, pending.path == fileURL.path, pending.fileIdentity == fileIdentity,
           pending.parsedOffset == startOffset, UInt64(currentSize) >= pending.observedOffset,
           !(UInt64(currentSize) == pending.observedOffset && pending.modifiedAt != modifiedAt) {
            let length = min(pending.data.count, 4096)
            try handle.seek(toOffset: startOffset)
            let first = try handle.read(upToCount: length) ?? Data()
            try handle.seek(toOffset: pending.observedOffset - UInt64(length))
            let last = try handle.read(upToCount: length) ?? Data()
            bytesRead += first.count + last.count
            if first == pending.data.prefix(length), last == pending.data.suffix(length) {
                buffer = pending.data
                readOffset = pending.observedOffset
            }
        }
        try handle.seek(toOffset: readOffset)
        var parsedOffset = startOffset
        var searchedBytes = buffer.count
        while true {
            try Task.checkCancellation()
            let chunk = try handle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty { break }
            bytesRead += chunk.count
            buffer.append(chunk)
            var lineStart = buffer.startIndex
            var searchStart = buffer.index(buffer.startIndex, offsetBy: searchedBytes)
            while let newline = buffer[searchStart...].firstIndex(of: 0x0A) {
                let line = Data(buffer[lineStart..<newline])
                let consumed = buffer.distance(from: lineStart, to: newline) + 1
                lineStart = buffer.index(after: newline)
                searchStart = lineStart
                parsedOffset += UInt64(consumed)
                guard !line.isEmpty else { continue }
                guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                    damagedLineCount += 1
                    continue
                }
                if ["session_meta", "turn_context"].contains(event["type"] as? String ?? ""),
                   let payload = event["payload"] as? [String: Any] {
                    currentContext = updatedContext(currentContext, from: payload)
                    continue
                }
                guard event["type"] as? String == "event_msg",
                      let payload = event["payload"] as? [String: Any] else { continue }
                if payload["type"] as? String == "thread_settings_applied" {
                    let settings = payload["thread_settings"] as? [String: Any] ?? payload
                    currentContext = updatedContext(currentContext, from: settings)
                    continue
                }
                guard payload["type"] as? String == "token_count",
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
                dailyTokens[day] = try TokenLedgerArithmetic.adding(dailyTokens[day, default: 0], increment)
                let rateLimits = payload["rate_limits"] as? [String: Any]
                currentContext = UsageExecutionContext(
                    modelID: currentContext.modelID,
                    reasoningEffort: currentContext.reasoningEffort,
                    serviceTier: currentContext.serviceTier,
                    modelProviderID: currentContext.modelProviderID,
                    authenticationMode: currentContext.authenticationMode == .api ? .api : (rateLimits?["plan_type"] != nil ? .chatGPT : nil),
                    planType: string(rateLimits?["plan_type"]),
                    hasAccountRateLimits: rateLimits?["primary"] != nil
                        || rateLimits?["secondary"] != nil,
                    rateCardMode: rateCardMode,
                    rateCardVersion: rateCard?.version(at: timestamp)?.id
                )
                let windows = quotaWindows(from: payload["rate_limits"])
                let breakdown = tokenBreakdown(from: lastUsage, fallbackTokens: increment)
                let estimate = breakdown.flatMap {
                    rateCard?.credits(
                        for: $0,
                        context: currentContext,
                        mode: rateCardMode,
                        at: timestamp
                    )
                }
                quotaObservations.append(
                    ThreadQuotaUsageObservation(
                        timestamp: timestamp,
                        tokenIncrement: increment,
                        tokenBreakdown: breakdown,
                        executionContext: currentContext,
                        creditEstimate: estimate,
                        windows: windows
                    )
                )
            }
            if lineStart != buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<lineStart)
            }
            searchedBytes = buffer.count
        }

        let prefixLength = Int(min(parsedOffset, 4096))
        try handle.seek(toOffset: 0)
        var boundary = try handle.read(upToCount: prefixLength) ?? Data()
        try handle.seek(toOffset: parsedOffset - UInt64(prefixLength))
        boundary.append(try handle.read(upToCount: prefixLength) ?? Data())
        bytesRead += boundary.count
        let prefixDigest = IncrementalUsageDatabase.fingerprint(boundary)
        return ParsedRollout(
            dailyTokens: dailyTokens,
            quotaObservations: quotaObservations,
            checkpoint: UsageRolloutCheckpoint(
                path: fileURL.path,
                fileSize: Int64(parsedOffset) + Int64(buffer.count),
                parsedOffset: parsedOffset,
                seenCumulativeTotals: seenTotals.sorted(),
                lastModelID: currentContext.modelID,
                lastExecutionContext: currentContext,
                fileIdentity: fileIdentity,
                modifiedAt: modifiedAt,
                prefixDigest: prefixDigest,
                prefixLength: prefixLength
            ),
            damagedLineCount: damagedLineCount,
            resumedFromCheckpoint: canResume,
            pending: buffer.isEmpty ? nil : RolloutPendingData(path: fileURL.path, fileIdentity: fileIdentity,
                parsedOffset: parsedOffset, observedOffset: parsedOffset + UInt64(buffer.count), modifiedAt: modifiedAt, data: buffer),
            bytesRead: bytesRead
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

    private static func string(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func updatedContext(
        _ current: UsageExecutionContext,
        from payload: [String: Any]
    ) -> UsageExecutionContext {
        let provider = string(payload["model_provider_id"])
            ?? string(payload["modelProviderId"]) ?? string(payload["model_provider"])
            ?? current.modelProviderID
        let rawMode = string(payload["auth_mode"]) ?? string(payload["authentication_mode"])
        let mode: UsageAuthenticationMode? = switch rawMode {
        case "api", "api_key", "apikey": .api
        case "chatgpt", "chatGPT": .chatGPT
        default: nil
        }
        return UsageExecutionContext(
            modelID: string(payload["model"]) ?? current.modelID,
            reasoningEffort: string(payload["reasoning_effort"])
                ?? string(payload["reasoningEffort"]) ?? current.reasoningEffort,
            serviceTier: string(payload["service_tier"])
                ?? string(payload["serviceTier"]) ?? current.serviceTier,
            modelProviderID: provider,
            authenticationMode: mode,
            // A new turn/provider never inherits a previous turn's account evidence.
            planType: nil,
            hasAccountRateLimits: false,
            rateCardMode: current.rateCardMode,
            rateCardVersion: current.rateCardVersion
        )
    }

    private static func tokenBreakdown(
        from usage: [String: Any],
        fallbackTokens: Int64
    ) -> UsageTokenBreakdown? {
        guard let input = integer(usage["input_tokens"]),
              let cached = integer(usage["cached_input_tokens"]),
              let output = integer(usage["output_tokens"]),
              let reasoning = integer(usage["reasoning_output_tokens"]),
              input >= 0,
              cached >= 0,
              output >= 0,
              reasoning >= 0 else { return nil }
        let cacheWrite = integer(usage["cache_write_input_tokens"])
            ?? integer(usage["cache_write_tokens"])
            ?? integer(usage["cache_write"])
        let breakdown = UsageTokenBreakdown(
            inputTokens: input,
            cachedInputTokens: cached,
            cacheWriteInputTokens: cacheWrite,
            outputTokens: output,
            reasoningOutputTokens: reasoning,
            totalTokens: integer(usage["total_tokens"]) ?? fallbackTokens
        )
        return breakdown.hasConsistentComponents ? breakdown : nil
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

public actor LocalCodexUsageReader: CodexUsageReading, UsageHistoryClearing, AccountQuotaSnapshotRecording, NativeThreadReading {
    private let codexHome: URL
    private let explicitDatabaseURL: URL?
    private let fileManager: FileManager
    private let ledgerStore: SQLiteUsageLedgerStore
    private var databaseScores: [String: (signature: String, score: DatabaseScore)] = [:]
    private var pendingRollouts: [String: RolloutPendingData] = [:]
    internal private(set) var rolloutBytesReadLastRefresh = 0
    private var rejectedTimezoneReplays: [String: String] = [:]
    private var rolloutIndex: [String: URL]?
    private var rolloutDirectories: [URL: String] = [:]

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
        ledgerStore = SQLiteUsageLedgerStore(fileURL: ledgerURL ?? defaultLedger)
    }

    public func selectedStateDatabase() throws -> URL {
        if let explicitDatabaseURL {
            guard fileManager.fileExists(atPath: explicitDatabaseURL.path) else {
                throw LocalCodexUsageError.stateDatabaseNotFound(codexHome)
            }
            _ = try databaseScore(explicitDatabaseURL)
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
                guard let score = try? databaseScore(candidate),
                      score.taskCount > 0 else { continue }
                if best == nil || best!.0 < score { best = (score, candidate) }
            }
        }
        guard let best else { throw LocalCodexUsageError.stateDatabaseNotFound(codexHome) }
        return best.1
    }

    private func fileSignature(_ url: URL) -> String {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path) else { return "missing" }
        return "\(attributes[.systemFileNumber] ?? "")|\(attributes[.size] ?? "")|\((attributes[.modificationDate] as? Date)?.timeIntervalSinceReferenceDate ?? 0)"
    }
    private func databaseScore(_ url: URL) throws -> DatabaseScore {
        let signature = fileSignature(url) + fileSignature(URL(fileURLWithPath: url.path + "-wal"))
        if let cached = databaseScores[url.path], cached.signature == signature { return cached.score }
        let score = try ReadOnlySQLiteDatabase.read(url) { try $0.score(path: url.path) }
        databaseScores[url.path] = (signature, score)
        return score
    }

    public func nativeCatalogue(now: Date) async throws -> NativeCatalogue {
        try ReadOnlySQLiteDatabase.read(selectedStateDatabase()) { try $0.nativeCatalogue(now: now) }
    }

    public func readUsage(
        now: Date,
        calendar: Calendar,
        rateCard: RateCardManifest?,
        rateCardMode: RateCardMode,
        apiPriceCard: APIPriceManifest?
    ) async throws -> UsageHistory {
        try Task.checkCancellation()
        let timezoneIdentifier = calendar.timeZone.identifier
        var ledger = try ledgerStore.load(timezoneIdentifier: timezoneIdentifier)
        for id in ledger.threads.keys where ledger.threads[id]?.sourceTimezoneIdentifier == nil {
            ledger.threads[id]?.sourceTimezoneIdentifier = ledger.timezoneIdentifier
        }
        ledger.timezoneIdentifier = timezoneIdentifier
        let databaseURL = try selectedStateDatabase()
        let inventory = try ReadOnlySQLiteDatabase.read(databaseURL) { try $0.inventory() }
        var fallbackRollouts: [String: URL]?
        var pendingUpdates = pendingRollouts
        var rejectedUpdates = rejectedTimezoneReplays
        var bytesRead = 0
        var warnings: [String] = []

        for thread in inventory.threads.values {
            try Task.checkCancellation()
            let rootID = rootID(for: thread.id, parents: inventory.parentByChild)
            let previous = ledger.threads[thread.id]
            let directRolloutURL = rolloutURL(for: thread, fallbackIndex: [:])
            if directRolloutURL == nil, fallbackRollouts == nil {
                fallbackRollouts = buildRolloutIndex()
            }
            guard let rolloutURL = directRolloutURL ?? rolloutURL(
                for: thread,
                fallbackIndex: fallbackRollouts ?? [:]
            ) else {
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
                let changingTimezone = previous.map {
                    ($0.sourceTimezoneIdentifier != nil && $0.sourceTimezoneIdentifier != timezoneIdentifier)
                        || $0.dayBucketTimezones.values.contains { $0 != [timezoneIdentifier] }
                } ?? false
                let signature = fileSignature(rolloutURL) + timezoneIdentifier
                if changingTimezone, rejectedUpdates[thread.id] == signature {
                    ledger.threads[thread.id]?.rootTaskID = rootID
                    ledger.threads[thread.id]?.title = thread.title
                    continue
                }
                var sourceCalendar = calendar
                if changingTimezone { sourceCalendar.timeZone = TimeZone(identifier: previous!.sourceTimezoneIdentifier!) ?? calendar.timeZone }
                let retryingRejectedReplay = changingTimezone && rejectedUpdates[thread.id] != nil
                var parsed = try RolloutTokenParser.parse(
                    fileURL: rolloutURL,
                    previous: changingTimezone && !retryingRejectedReplay ? nil : previous,
                    calendar: sourceCalendar,
                    rateCard: rateCard,
                    rateCardMode: rateCardMode,
                    pending: changingTimezone && !retryingRejectedReplay ? nil : pendingRollouts[thread.id]
                )
                bytesRead += parsed.bytesRead
                var retainedSourceTimezone = false
                if changingTimezone, let previous {
                    if !parsed.resumedFromCheckpoint, try Self.coversHistory(parsed, previous: previous, calendar: sourceCalendar) {
                        var days: [String: Int64] = [:]
                        for observation in parsed.quotaObservations {
                            let day = Self.dayKey(observation.timestamp, calendar: calendar)
                            days[day] = try TokenLedgerArithmetic.adding(days[day, default: 0], observation.tokenIncrement)
                        }
                        parsed = ParsedRollout(dailyTokens: days,
                            quotaObservations: Self.preservingObservations(previous.quotaObservations, replayed: parsed.quotaObservations),
                            checkpoint: parsed.checkpoint, damagedLineCount: parsed.damagedLineCount, resumedFromCheckpoint: false)
                        rejectedUpdates.removeValue(forKey: thread.id)
                    } else {
                        if !parsed.resumedFromCheckpoint, !retryingRejectedReplay, previous.checkpoint != nil {
                            parsed = try RolloutTokenParser.parse(fileURL: rolloutURL, previous: previous,
                                calendar: sourceCalendar, rateCard: rateCard, rateCardMode: rateCardMode,
                                pending: pendingRollouts[thread.id])
                            bytesRead += parsed.bytesRead
                        }
                        if !parsed.resumedFromCheckpoint {
                            // Unidentifiable old events cannot replace history. Start a conservative
                            // checkpoint so subsequent, provably appended events still get counted.
                            parsed = ParsedRollout(dailyTokens: previous.dailyTokens, quotaObservations: previous.quotaObservations,
                                checkpoint: parsed.checkpoint, damagedLineCount: parsed.damagedLineCount,
                                resumedFromCheckpoint: false, pending: parsed.pending)
                        }
                        retainedSourceTimezone = true
                        rejectedUpdates[thread.id] = signature
                    }
                }
                pendingUpdates[thread.id] = parsed.pending
                var bucketTimezones = (parsed.resumedFromCheckpoint || retainedSourceTimezone) ? previous?.dayBucketTimezones ?? [:] : [:]
                for day in bucketTimezones.keys where parsed.dailyTokens[day] != previous?.dailyTokens[day] {
                    bucketTimezones[day] = Array(Set(bucketTimezones[day, default: []] + [sourceCalendar.timeZone.identifier])).sorted()
                }
                ledger.threads[thread.id] = ThreadUsageLedgerEntry(
                    threadID: thread.id,
                    rootTaskID: rootID,
                    title: thread.title,
                    dailyTokens: parsed.dailyTokens,
                    quotaObservations: parsed.quotaObservations,
                    checkpoint: parsed.checkpoint,
                    isComplete: !retainedSourceTimezone && parsed.damagedLineCount == 0
                        && (!parsed.resumedFromCheckpoint || previous?.isComplete != false),
                    sourceTimezoneIdentifier: retainedSourceTimezone ? previous?.sourceTimezoneIdentifier : timezoneIdentifier,
                    dayBucketTimezones: bucketTimezones
                )
                if parsed.damagedLineCount > 0 {
                    warnings.append("任务 \(thread.id) 跳过了 \(parsed.damagedLineCount) 行损坏的 rollout 数据。")
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch LocalCodexUsageError.tokenTotalOutOfRange {
                throw LocalCodexUsageError.tokenTotalOutOfRange
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
        let history = try history(
            from: ledger,
            now: now,
            rateCard: rateCard,
            rateCardMode: rateCardMode,
            apiPriceCard: apiPriceCard
        )
        try Task.checkCancellation()
        try ledgerStore.save(ledger)
        pendingRollouts = pendingUpdates.filter { inventory.threads[$0.key] != nil }
        rejectedTimezoneReplays = rejectedUpdates.filter { inventory.threads[$0.key] != nil }
        rolloutBytesReadLastRefresh = bytesRead
        return history
    }

    /// Release persistent storage after pending refresh work has finished.
    public func close() { ledgerStore.close(); pendingRollouts = [:]; rejectedTimezoneReplays = [:] }

    public func exportLegacyHistory() throws {
        try ledgerStore.exportLegacyHistory()
    }

    public func clearHistory() async throws {
        try ledgerStore.clear()
        pendingRollouts = [:]; rejectedTimezoneReplays = [:]
    }

    public func recordAccountQuotaSnapshot(
        windows: [AccountQuotaWindow],
        planType: String?,
        timestamp: Date,
        accountKey: String? = nil
    ) async throws {
        guard !windows.isEmpty else { return }
        try ledgerStore.recordAccountObservation(
            ThreadQuotaUsageObservation(
                timestamp: timestamp,
                tokenIncrement: 0,
                accountKey: accountKey,
                executionContext: UsageExecutionContext(
                    modelID: nil,
                    reasoningEffort: nil,
                    serviceTier: nil,
                    planType: planType,
                    hasAccountRateLimits: true
                ),
                windows: windows
            ),
            timezoneIdentifier: Calendar.current.timeZone.identifier
        )
    }

    private struct ObservationIdentity: Hashable {
        var timestamp: Date
        var tokens: Int64
        init(_ value: ThreadQuotaUsageObservation) { timestamp = value.timestamp; tokens = value.tokenIncrement }
    }
    private static func coversHistory(_ parsed: ParsedRollout, previous: ThreadUsageLedgerEntry, calendar: Calendar) throws -> Bool {
        guard parsed.damagedLineCount == 0, parsed.checkpoint.parsedOffset == UInt64(parsed.checkpoint.fileSize),
              previous.dayBucketTimezones.values.allSatisfy({ $0 == [calendar.timeZone.identifier] }),
              previous.dailyTokens.allSatisfy({ parsed.dailyTokens[$0.key, default: 0] >= $0.value }) else { return false }
        // Daily totals alone cannot identify missing events: newer events can have the same sum.
        var observedDays: [String: Int64] = [:]
        for observation in previous.quotaObservations {
            let day = dayKey(observation.timestamp, calendar: calendar)
            observedDays[day] = try TokenLedgerArithmetic.adding(observedDays[day, default: 0], observation.tokenIncrement)
        }
        guard observedDays.filter({ $0.value != 0 }) == previous.dailyTokens.filter({ $0.value != 0 }) else { return false }
        var counts = Dictionary(parsed.quotaObservations.map { (ObservationIdentity($0), 1) }, uniquingKeysWith: +)
        for observation in previous.quotaObservations {
            let key = ObservationIdentity(observation)
            guard counts[key, default: 0] > 0 else { return false }
            counts[key, default: 0] -= 1
        }
        return true
    }
    private static func preservingObservations(_ previous: [ThreadQuotaUsageObservation], replayed: [ThreadQuotaUsageObservation]) -> [ThreadQuotaUsageObservation] {
        var result = previous
        var counts = Dictionary(previous.map { (ObservationIdentity($0), 1) }, uniquingKeysWith: +)
        for observation in replayed {
            let key = ObservationIdentity(observation)
            if counts[key, default: 0] > 0 { counts[key, default: 0] -= 1 }
            else { result.append(observation) }
        }
        return result.sorted { $0.timestamp < $1.timestamp }
    }

    private func history(
        from ledger: VersionedUsageLedger,
        now: Date,
        rateCard: RateCardManifest?,
        rateCardMode: RateCardMode,
        apiPriceCard: APIPriceManifest?
    ) throws -> UsageHistory {
        struct Aggregate {
            var tokens: Int64 = 0
            var observedTokens: Int64 = 0
            var credits: Double = 0
            var creditPrecision: CreditEstimatePrecision?
            var hasUnpricedObservation = false
            var costUSD: Decimal = 0
            var costPrecision: CostEstimatePrecision?
            var pricedTokens: Int64 = 0
            var costBreakdown = APICostBreakdown(
                freshInputUSD: 0,
                cachedInputUSD: 0,
                cacheWriteUSD: 0,
                outputUSD: 0
            )
            var memberIDs: Set<String> = []
            var complete = true
        }
        var byDayAndRoot: [String: [String: Aggregate]] = [:]
        var memberCountByRoot: [String: Int] = [:]
        var quotaObservations: [LocalQuotaUsageObservation] = []
        var historyCalendar = Calendar(identifier: .gregorian)
        historyCalendar.timeZone = TimeZone(identifier: ledger.timezoneIdentifier) ?? .current
        let mixedRoots = Set(ledger.threads.values.filter {
            !$0.dayBucketTimezones.isEmpty
        }.map(\.rootTaskID))
        let foreignRoots = mixedRoots.union(ledger.threads.values.filter {
            $0.sourceTimezoneIdentifier != nil && $0.sourceTimezoneIdentifier != ledger.timezoneIdentifier && !$0.dailyTokens.isEmpty
        }.map(\.rootTaskID))
        for entry in ledger.threads.values {
            try Task.checkCancellation()
            var entryCalendar = historyCalendar
            if let sourceTimezone = entry.sourceTimezoneIdentifier { entryCalendar.timeZone = TimeZone(identifier: sourceTimezone) ?? historyCalendar.timeZone }
            memberCountByRoot[entry.rootTaskID, default: 0] += 1
            for (observationIndex, observation) in entry.quotaObservations.enumerated() {
                if observationIndex.isMultiple(of: 256) { try Task.checkCancellation() }
                if mixedRoots.contains(entry.rootTaskID) { continue }
                let estimate = observation.tokenBreakdown.flatMap { breakdown in
                    observation.executionContext.flatMap { context in
                        rateCard?.credits(
                            for: breakdown,
                            context: context,
                            mode: rateCardMode,
                            at: observation.timestamp
                        )
                    }
                }
                let costEstimate = observation.tokenBreakdown.flatMap { breakdown in
                    observation.executionContext.flatMap { context in
                        apiPriceCard?.cost(
                            for: breakdown,
                            context: context,
                            at: observation.timestamp
                        )
                    }
                }
                if !foreignRoots.contains(entry.rootTaskID) { quotaObservations.append(
                    LocalQuotaUsageObservation(
                        timestamp: observation.timestamp,
                        rootTaskID: entry.rootTaskID,
                        tokenIncrement: observation.tokenIncrement,
                        accountKey: observation.accountKey,
                        quotaUsageWeight: observation.quotaUsageWeight,
                        tokenBreakdown: observation.tokenBreakdown,
                        executionContext: observation.executionContext,
                        creditEstimate: estimate,
                        windows: observation.windows
                    )
                )
                }
                let day = Self.dayKey(observation.timestamp, calendar: entryCalendar)
                var aggregate = byDayAndRoot[day, default: [:]][entry.rootTaskID, default: Aggregate()]
                aggregate.observedTokens = try TokenLedgerArithmetic.adding(aggregate.observedTokens, observation.tokenIncrement)
                if let estimate {
                    aggregate.credits += estimate.credits
                    aggregate.creditPrecision = Self.mergedPrecision(
                        aggregate.creditPrecision,
                        estimate.precision
                    )
                } else if observation.tokenIncrement > 0 {
                    aggregate.hasUnpricedObservation = true
                }
                if let costEstimate {
                    aggregate.costUSD += costEstimate.amountUSD
                    aggregate.pricedTokens = try TokenLedgerArithmetic.adding(aggregate.pricedTokens, min(
                        observation.tokenIncrement,
                        costEstimate.pricedTokens
                    ))
                    aggregate.costPrecision = Self.mergedCostPrecision(
                        aggregate.costPrecision,
                        costEstimate.precision
                    )
                    aggregate.costBreakdown = Self.adding(
                        aggregate.costBreakdown,
                        costEstimate.breakdown
                    )
                }
                byDayAndRoot[day, default: [:]][entry.rootTaskID] = aggregate
            }
            for (day, tokens) in entry.dailyTokens {
                var aggregate = byDayAndRoot[day, default: [:]][entry.rootTaskID, default: Aggregate()]
                aggregate.tokens = try TokenLedgerArithmetic.adding(aggregate.tokens, tokens)
                aggregate.memberIDs.insert(entry.threadID)
                aggregate.complete = aggregate.complete && entry.isComplete && !foreignRoots.contains(entry.rootTaskID)
                if foreignRoots.contains(entry.rootTaskID) { aggregate.hasUnpricedObservation = true; aggregate.costPrecision = .lowerBound }
                byDayAndRoot[day, default: [:]][entry.rootTaskID] = aggregate
            }
        }
        var fallbackTitles: [String: String] = [:]
        for entry in ledger.threads.values where fallbackTitles[entry.rootTaskID] == nil {
            fallbackTitles[entry.rootTaskID] = entry.title
        }
        let days = try byDayAndRoot.map { day, roots in
            try Task.checkCancellation()
            let tasks = roots.map { rootID, aggregate in
                let root = ledger.threads[rootID]
                return DailyTaskUsage(
                    dateKey: day,
                    rootTaskID: rootID,
                    title: root?.title ?? fallbackTitles[rootID] ?? "未命名任务",
                    tokens: aggregate.tokens,
                    credits: aggregate.hasUnpricedObservation
                        || aggregate.observedTokens < aggregate.tokens
                        ? nil : aggregate.credits,
                    creditPrecision: aggregate.creditPrecision,
                    costUSD: aggregate.pricedTokens > 0 ? aggregate.costUSD : nil,
                    costPrecision: aggregate.pricedTokens < aggregate.tokens
                        ? .lowerBound
                        : aggregate.costPrecision,
                    pricedTokens: aggregate.pricedTokens,
                    costBreakdown: aggregate.pricedTokens > 0
                        ? aggregate.costBreakdown
                        : nil,
                    descendantCount: max(0, (memberCountByRoot[rootID] ?? aggregate.memberIDs.count) - 1)
                )
            }
            let totalTokens = try tasks.reduce(Int64(0)) { try TokenLedgerArithmetic.adding($0, $1.tokens) }
            let pricedTokens = try tasks.reduce(Int64(0)) { try TokenLedgerArithmetic.adding($0, $1.pricedTokens) }
            let mergedCostPrecision = tasks.reduce(nil) { partial, task in
                Self.mergedCostPrecision(partial, task.costPrecision)
            }
            return DailyUsageSummary(
                dateKey: day,
                totalTokens: totalTokens,
                totalCredits: tasks.allSatisfy { $0.credits != nil }
                    ? tasks.compactMap(\.credits).reduce(0, +)
                    : nil,
                creditPrecision: tasks.compactMap(\.creditPrecision).reduce(nil) {
                    Self.mergedPrecision($0, $1)
                },
                totalCostUSD: tasks.compactMap(\.costUSD).isEmpty
                    ? nil
                    : tasks.compactMap(\.costUSD).reduce(0, +),
                costPrecision: pricedTokens < totalTokens && pricedTokens > 0
                    ? .lowerBound
                    : mergedCostPrecision,
                pricedTokens: pricedTokens,
                costBreakdown: tasks.compactMap(\.costBreakdown).reduce(nil) { partial, value in
                    Self.adding(partial, value)
                },
                tasks: tasks,
                isComplete: roots.values.allSatisfy(\.complete)
            )
        }
        quotaObservations.append(
            contentsOf: ledger.accountObservations.map {
                LocalQuotaUsageObservation(
                    timestamp: $0.timestamp,
                    rootTaskID: "__account__",
                    tokenIncrement: 0,
                    accountKey: $0.accountKey,
                    executionContext: $0.executionContext,
                    isAccountSnapshot: true,
                    windows: $0.windows
                )
            }
        )
        return UsageHistory(
            generatedAt: now,
            timezoneIdentifier: ledger.timezoneIdentifier,
            days: days,
            warnings: ledger.warnings,
            quotaObservations: quotaObservations
        )
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func mergedPrecision(
        _ lhs: CreditEstimatePrecision?,
        _ rhs: CreditEstimatePrecision
    ) -> CreditEstimatePrecision {
        guard let lhs else { return rhs }
        if lhs == .approximate || rhs == .approximate { return .approximate }
        if lhs != rhs, lhs != .exact, rhs != .exact { return .approximate }
        if lhs == .upperBound || rhs == .upperBound { return .upperBound }
        if lhs == .lowerBound || rhs == .lowerBound { return .lowerBound }
        return .exact
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
        if let exact = fallbackIndex[thread.id] { return exact }
        return fallbackIndex.first { $0.key.contains(thread.id) }?.value
    }

    private func buildRolloutIndex() -> [String: URL] {
        if let rolloutIndex, rolloutDirectories.allSatisfy({ fileSignature($0.key) == $0.value }) { return rolloutIndex }
        var directories: [URL: String] = [:]
        var result: [String: URL] = [:]
        let roots = [
            codexHome.appendingPathComponent("archived_sessions", isDirectory: true),
            codexHome.appendingPathComponent("sessions", isDirectory: true)
        ]
        for root in roots {
            directories[root] = fileSignature(root)
            guard let enumerator = fileManager.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in enumerator {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    directories[url] = fileSignature(url); continue
                }
                guard url.pathExtension == "jsonl" else { continue }
                let filename = url.lastPathComponent
                result[filename] = url
                let stem = url.deletingPathExtension().lastPathComponent
                if stem.count >= 36 {
                    let possibleID = String(stem.suffix(36))
                    if UUID(uuidString: possibleID) != nil {
                        result[possibleID] = url
                    }
                }
            }
        }
        rolloutIndex = result; rolloutDirectories = directories
        return result
    }

    private static func mergedCostPrecision(
        _ lhs: CostEstimatePrecision?,
        _ rhs: CostEstimatePrecision?
    ) -> CostEstimatePrecision? {
        guard let rhs else { return lhs }
        guard let lhs else { return rhs }
        if lhs == .lowerBound || rhs == .lowerBound { return .lowerBound }
        if lhs == .approximate || rhs == .approximate { return .approximate }
        return .exact
    }

    private static func adding(
        _ lhs: APICostBreakdown?,
        _ rhs: APICostBreakdown
    ) -> APICostBreakdown {
        guard let lhs else { return rhs }
        return APICostBreakdown(
            freshInputUSD: lhs.freshInputUSD + rhs.freshInputUSD,
            cachedInputUSD: lhs.cachedInputUSD + rhs.cachedInputUSD,
            cacheWriteUSD: lhs.cacheWriteUSD + rhs.cacheWriteUSD,
            outputUSD: lhs.outputUSD + rhs.outputUSD
        )
    }
}
