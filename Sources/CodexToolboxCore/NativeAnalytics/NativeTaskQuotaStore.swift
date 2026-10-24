import Foundation

public actor NativeTaskQuotaStore {
    private struct Envelope: Codable { var schemaVersion = 1; var snapshots: [NativeTaskQuotaSnapshot] }
    private let fileURL: URL
    private var database: IncrementalUsageDatabase?
    private var cached: [NativeTaskQuotaSnapshot]?
    private var identifiers = Set<Data>()
    private var storedKeys: [String] = []
    private var nextOrdinal: Int64 = 0
    private var earliestCollectedAt: Date?
    private let encoder: JSONEncoder = {
        let value = JSONEncoder(); value.outputFormatting = [.sortedKeys]; return value
    }()
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ApplicationSupportLayout().currentDirectory.appendingPathComponent("native-task-quota-v1.json")
    }
    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let field = try value.singleValueContainer()
            if let seconds = try? field.decode(Double.self) { return Date(timeIntervalSinceReferenceDate: seconds) }
            guard let date = MetricFormatter.sourceDate(try field.decode(String.self)) else { throw NativeAnalyticsError.invalidResponse }
            return date
        }
        return decoder
    }
    private func prepare() throws -> IncrementalUsageDatabase {
        if let database { return database }
        let db = try IncrementalUsageDatabase(url: fileURL.appendingPathExtension("sqlite"))
        try db.recoverLegacyExport(at: fileURL)
        let source = FileManager.default.fileExists(atPath: fileURL.path) ? try Data(contentsOf: fileURL) : nil
        let initialized = try db.metadata("initialized") != nil
        let exported = try db.metadata("exported")
        let changedAfterExport = exported != nil && source.map(IncrementalUsageDatabase.fingerprint) != exported
        if !initialized || changedAfterExport {
            let snapshots: [NativeTaskQuotaSnapshot]
            if let source {
                try IncrementalUsageDatabase.backup(source, source: fileURL)
                let envelope = try Self.decoder().decode(Envelope.self, from: source)
                guard envelope.schemaVersion == 1 else { throw NativeAnalyticsError.invalidResponse }
                snapshots = envelope.snapshots
            } else { snapshots = [] }
            try db.transaction {
                try db.deleteAllRecords()
                for (index, snapshot) in snapshots.enumerated() {
                    let payload = try encoder.encode(snapshot)
                    let key = IncrementalUsageDatabase.fingerprint(payload).base64EncodedString() + ":legacy:\(index)"
                    try db.put("native", .init(key: key, ordinal: Int64(index), account: snapshot.accountKey,
                        observed: snapshot.collectedAt.timeIntervalSinceReferenceDate, payload: payload))
                }
                let restored = try db.records("native").map { try Self.decoder().decode(NativeTaskQuotaSnapshot.self, from: $0.payload) }
                guard restored == snapshots else { throw NativeAnalyticsError.invalidResponse }
                try db.setMetadata("initialized", Data([1]))
                try db.removeMetadata("exported")
            }
        }
        let rows = try db.records("native")
        let values = try rows.map { try Self.decoder().decode(NativeTaskQuotaSnapshot.self, from: $0.payload) }
        storedKeys = rows.map(\.key)
        identifiers = Set(rows.map { IncrementalUsageDatabase.fingerprint($0.payload) })
        nextOrdinal = (rows.map(\.ordinal).max() ?? -1) + 1
        cached = values; earliestCollectedAt = values.map(\.collectedAt).min(); database = db
        return db
    }
    public func snapshots(accountKey: String) throws -> [NativeTaskQuotaSnapshot] {
        _ = try prepare()
        return (cached ?? []).filter { $0.accountKey == accountKey }
    }
    public func append(_ additions: [NativeTaskQuotaSnapshot], now: Date) throws {
        guard !additions.isEmpty else { return }
        let db = try prepare()
        let cutoff = now.addingTimeInterval(-90 * 86400)
        let expired = earliestCollectedAt.map({ $0 < cutoff }) == true ? (cached ?? []).filter { $0.collectedAt < cutoff } : []
        let expiredKeys = expired.isEmpty ? [] : zip(cached ?? [], storedKeys).filter { $0.0.collectedAt < cutoff }.map { $0.1 }
        let expiredIDs = try expired.map { IncrementalUsageDatabase.fingerprint(try encoder.encode($0)) }
        let expiredSet = Set(expiredIDs)
        var pendingIDs = Set<Data>()
        var newRows: [(NativeTaskQuotaSnapshot, Data, Data)] = []
        for snapshot in additions {
            let payload = try encoder.encode(snapshot)
            let key = IncrementalUsageDatabase.fingerprint(payload)
            if (!identifiers.contains(key) || expiredSet.contains(key)) && pendingIDs.insert(key).inserted { newRows.append((snapshot, payload, key)) }
        }
        guard !expired.isEmpty || !newRows.isEmpty else { return }
        try db.transaction {
            for key in expiredKeys { try db.delete("native", key: key) }
            for (index, row) in newRows.enumerated() {
                try db.put("native", .init(key: row.2.base64EncodedString(), ordinal: nextOrdinal + Int64(index),
                    account: row.0.accountKey, observed: row.0.collectedAt.timeIntervalSinceReferenceDate, payload: row.1))
            }
        }
        if !expired.isEmpty {
            storedKeys = zip(cached ?? [], storedKeys).filter { $0.0.collectedAt >= cutoff }.map { $0.1 }
            cached?.removeAll { $0.collectedAt < cutoff }
        }
        storedKeys.append(contentsOf: newRows.map { $0.2.base64EncodedString() })
        cached?.append(contentsOf: newRows.map(\.0))
        identifiers.subtract(expiredIDs); identifiers.formUnion(pendingIDs)
        if !expired.isEmpty { earliestCollectedAt = cached?.map(\.collectedAt).min() }
        else if let addedEarliest = newRows.map({ $0.0.collectedAt }).min() {
            earliestCollectedAt = min(earliestCollectedAt ?? addedEarliest, addedEarliest)
        }
        nextOrdinal += Int64(newRows.count)
    }
    public func append(_ additions: [NativeTaskQuotaSnapshot], now: Date, accountKey: String) throws -> [NativeTaskQuotaSnapshot] {
        try append(additions, now: now)
        return try snapshots(accountKey: accountKey)
    }
    /// Release the connection after refresh has stopped, before moving or deleting storage.
    public func close() { database = nil; cached = nil; identifiers = []; storedKeys = []; earliestCollectedAt = nil; nextOrdinal = 0 }

    /// Call only while preparing a downgrade and after background refresh has stopped.
    public func exportLegacyHistory() throws {
        let db = try prepare()
        let payload = try encoder.encode(Envelope(snapshots: cached ?? []))
        try db.exportLegacy(payload, to: fileURL)
    }
}
