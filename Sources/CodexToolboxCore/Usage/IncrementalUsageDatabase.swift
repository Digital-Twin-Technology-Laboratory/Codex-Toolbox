import Foundation
import SQLite3
import CryptoKit

/// Confined to its owning store's actor. Transactions never suspend.
final class IncrementalUsageDatabase: @unchecked Sendable {
    struct Record {
        var key: String
        var ordinal: Int64
        var account: String?
        var observed: Double?
        var payload: Data
    }
    struct Failure: LocalizedError {
        let code: Int32
        var errorDescription: String? { "本地历史数据库操作失败（SQLite \(code)）。" }
    }
    let url: URL
    private var handle: OpaquePointer?
    private let lock = NSRecursiveLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let result = sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard result == SQLITE_OK else {
            if let handle { sqlite3_close(handle) }; handle = nil
            throw Failure(code: result)
        }
        do {
            sqlite3_busy_timeout(handle, 1_000)
            try execute("PRAGMA journal_mode=DELETE")
            try execute("PRAGMA synchronous=EXTRA")
            let version = try scalar("PRAGMA user_version")
            guard version == 0 || version == 1 else { throw Failure(code: SQLITE_SCHEMA) }
            try transaction {
                try execute("CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value BLOB NOT NULL) WITHOUT ROWID")
                try execute("CREATE TABLE IF NOT EXISTS records (namespace TEXT NOT NULL, key TEXT NOT NULL, ordinal INTEGER NOT NULL, account TEXT, observed REAL, payload BLOB NOT NULL, PRIMARY KEY(namespace,key)) WITHOUT ROWID")
                try execute("CREATE INDEX IF NOT EXISTS records_account ON records(namespace,account,ordinal)")
                try execute("CREATE INDEX IF NOT EXISTS records_observed ON records(namespace,observed)")
                if version == 0 { try execute("PRAGMA user_version=1") }
            }
        } catch {
            sqlite3_close(handle); handle = nil; throw error
        }
    }
    deinit { if let handle { sqlite3_close(handle) } }

    func transaction<T>(_ body: () throws -> T) throws -> T {
        lock.lock(); defer { lock.unlock() }
        try Task.checkCancellation()
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try body()
            try Task.checkCancellation()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }
    func execute(_ sql: String) throws {
        lock.lock(); defer { lock.unlock() }
        let result = sqlite3_exec(handle, sql, nil, nil, nil)
        guard result == SQLITE_OK else { throw Failure(code: result) }
    }
    func scalar(_ sql: String) throws -> Int64 {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare(sql); defer { sqlite3_finalize(statement) }
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW else { throw Failure(code: result) }
        return sqlite3_column_int64(statement, 0)
    }
    func metadata(_ key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare("SELECT value FROM metadata WHERE key=?")
        defer { sqlite3_finalize(statement) }; bind(key, to: statement, at: 1)
        let result = sqlite3_step(statement)
        if result == SQLITE_DONE { return nil }
        guard result == SQLITE_ROW else { throw Failure(code: result) }
        return data(statement, column: 0)
    }
    func setMetadata(_ key: String, _ value: Data) throws {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare("INSERT INTO metadata(key,value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value WHERE value<>excluded.value")
        defer { sqlite3_finalize(statement) }; bind(key, to: statement, at: 1); bind(value, to: statement, at: 2)
        try finish(statement)
    }
    func removeMetadata(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare("DELETE FROM metadata WHERE key=?")
        defer { sqlite3_finalize(statement) }; bind(key, to: statement, at: 1); try finish(statement)
    }
    func records(_ namespace: String) throws -> [Record] {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare("SELECT key,ordinal,account,observed,payload FROM records WHERE namespace=? ORDER BY ordinal,key")
        defer { sqlite3_finalize(statement) }; bind(namespace, to: statement, at: 1)
        var result: [Record] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW else { throw Failure(code: code) }
            result.append(Record(key: String(cString: sqlite3_column_text(statement, 0)),
                ordinal: sqlite3_column_int64(statement, 1),
                account: sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : String(cString: sqlite3_column_text(statement, 2)),
                observed: sqlite3_column_type(statement, 3) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 3),
                payload: data(statement, column: 4)))
        }
    }
    func put(_ namespace: String, _ record: Record) throws {
        try Task.checkCancellation()
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare("INSERT INTO records(namespace,key,ordinal,account,observed,payload) VALUES(?,?,?,?,?,?) ON CONFLICT(namespace,key) DO UPDATE SET ordinal=excluded.ordinal,account=excluded.account,observed=excluded.observed,payload=excluded.payload WHERE payload<>excluded.payload OR ordinal<>excluded.ordinal OR account IS NOT excluded.account OR observed IS NOT excluded.observed")
        defer { sqlite3_finalize(statement) }
        bind(namespace, to: statement, at: 1); bind(record.key, to: statement, at: 2)
        sqlite3_bind_int64(statement, 3, record.ordinal)
        if let account = record.account { bind(account, to: statement, at: 4) } else { sqlite3_bind_null(statement, 4) }
        if let observed = record.observed { sqlite3_bind_double(statement, 5, observed) } else { sqlite3_bind_null(statement, 5) }
        bind(record.payload, to: statement, at: 6); try finish(statement)
    }
    func delete(_ namespace: String, key: String? = nil) throws {
        lock.lock(); defer { lock.unlock() }
        let statement = try prepare(key == nil ? "DELETE FROM records WHERE namespace=?" : "DELETE FROM records WHERE namespace=? AND key=?")
        defer { sqlite3_finalize(statement) }; bind(namespace, to: statement, at: 1)
        if let key { bind(key, to: statement, at: 2) }; try finish(statement)
    }
    func deleteAllRecords() throws { try execute("DELETE FROM records") }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else { throw Failure(code: code) }
        return statement
    }
    private func finish(_ statement: OpaquePointer) throws {
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else { throw Failure(code: code) }
    }
    private func bind(_ string: String, to statement: OpaquePointer, at index: Int32) {
        _ = string.withCString { sqlite3_bind_text(statement, index, $0, -1, transient) }
    }
    private func bind(_ value: Data, to statement: OpaquePointer, at index: Int32) {
        _ = value.withUnsafeBytes { sqlite3_bind_blob(statement, index, $0.baseAddress, Int32($0.count), transient) }
    }
    private func data(_ statement: OpaquePointer, column: Int32) -> Data {
        guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
    }
    func exportLegacy(_ payload: Data, to source: URL) throws {
        let previous = FileManager.default.fileExists(atPath: source.path) ? try Data(contentsOf: source) : nil
        try transaction {
            try setMetadata("exportPending", payload)
            try setMetadata("exportPrevious", previous.map(Self.fingerprint) ?? Data())
        }
        try payload.write(to: source, options: .atomic)
        try transaction {
            try setMetadata("exported", Self.fingerprint(payload))
            try removeMetadata("exportPending"); try removeMetadata("exportPrevious")
        }
    }
    func recoverLegacyExport(at source: URL) throws {
        guard let pending = try metadata("exportPending") else { return }
        let previous = try metadata("exportPrevious") ?? Data()
        let current = FileManager.default.fileExists(atPath: source.path) ? try Data(contentsOf: source) : nil
        let currentDigest = current.map(Self.fingerprint) ?? Data()
        let pendingDigest = Self.fingerprint(pending)
        if currentDigest == previous { try pending.write(to: source, options: .atomic) }
        // A different current file can be the old version's writes after the export.
        // Keep it and let the import transaction reconcile it against the exported digest.
        try transaction {
            try setMetadata("exported", pendingDigest)
            try removeMetadata("exportPending"); try removeMetadata("exportPrevious")
        }
    }
    static func fingerprint(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
    static func backup(_ data: Data, source: URL) throws {
        let backup = source.appendingPathExtension("pre-1.4.2-backup")
        if !FileManager.default.fileExists(atPath: backup.path) {
            let temporary = source.deletingLastPathComponent().appendingPathComponent(".history-backup-" + UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: temporary) }
            try data.write(to: temporary, options: .atomic)
            do { try FileManager.default.linkItem(at: temporary, to: backup) }
            catch { if !FileManager.default.fileExists(atPath: backup.path) { throw error } }
        }
    }
}
