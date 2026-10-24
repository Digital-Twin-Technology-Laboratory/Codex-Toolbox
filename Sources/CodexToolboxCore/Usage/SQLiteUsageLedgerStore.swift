import Foundation

/// The reader actor owns this store and its in-memory snapshot.
final class SQLiteUsageLedgerStore {
    private let fileURL: URL
    private var database: IncrementalUsageDatabase?
    private var cached: VersionedUsageLedger?
    private var accountsAreSorted = false
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder
    }()
    private let decoder = JSONDecoder()

    init(fileURL: URL) { self.fileURL = fileURL }
    func load(timezoneIdentifier: String) throws -> VersionedUsageLedger {
        if let cached { return cached }
        let db = try IncrementalUsageDatabase(url: fileURL.appendingPathExtension("sqlite"))
        try db.recoverLegacyExport(at: fileURL)
        let initialized = try db.metadata("initialized") != nil
        let exported = try db.metadata("exported")
        let source = FileManager.default.fileExists(atPath: fileURL.path) ? try Data(contentsOf: fileURL) : nil
        let changedAfterExport = exported != nil && source.map(IncrementalUsageDatabase.fingerprint) != exported
        if !initialized || changedAfterExport {
            var ledger = VersionedUsageLedger.empty(timezoneIdentifier: timezoneIdentifier)
            if let source {
                try IncrementalUsageDatabase.backup(source, source: fileURL)
                let legacyDecoder = JSONDecoder(); legacyDecoder.dateDecodingStrategy = .iso8601
                ledger = try legacyDecoder.decode(VersionedUsageLedger.self, from: source)
                guard (1...VersionedUsageLedger.currentSchemaVersion).contains(ledger.schemaVersion) else {
                    throw LocalCodexUsageError.unsupportedLedgerSchema(ledger.schemaVersion)
                }
            }
            try db.transaction {
                if changedAfterExport {
                    try restoreRetainedBucketTimezones(in: &ledger, database: db)
                }
                try db.deleteAllRecords()
                try persist(ledger, previous: nil, database: db)
                try verifyImported(ledger, database: db)
                if let source { try db.setMetadata("sourceSchema", Data(String(ledger.schemaVersion).utf8)); try db.setMetadata("sourceDigest", IncrementalUsageDatabase.fingerprint(source)) }
                try db.setMetadata("initialized", Data([1]))
                try db.removeMetadata("exported")
            }
            cached = ledger
        } else {
            guard let metadata = try db.metadata("ledger") else { throw IncrementalUsageDatabase.Failure(code: 11) }
            var ledger = try decoder.decode(VersionedUsageLedger.self, from: metadata)
            for row in try db.records("threads") {
                var entry = try decoder.decode(ThreadUsageLedgerEntry.self, from: row.payload)
                entry.dailyTokens = try Dictionary(uniqueKeysWithValues: db.records("days/" + entry.threadID).map { ($0.key, try decoder.decode(Int64.self, from: $0.payload)) })
                entry.quotaObservations = try db.records("quota/" + entry.threadID).map { try decoder.decode(ThreadQuotaUsageObservation.self, from: $0.payload) }
                if entry.checkpoint != nil {
                    entry.checkpoint?.seenCumulativeTotals = try db.records("seen/" + entry.threadID).map { try decoder.decode(Int64.self, from: $0.payload) }.sorted()
                }
                ledger.threads[entry.threadID] = entry
            }
            ledger.accountObservations = try db.records("account").map { try decoder.decode(ThreadQuotaUsageObservation.self, from: $0.payload) }
            cached = ledger
        }
        database = db
        return cached!
    }

    private func restoreRetainedBucketTimezones(in ledger: inout VersionedUsageLedger, database db: IncrementalUsageDatabase) throws {
        guard let metadata = try db.metadata("ledger") else { return }
        let previous = try decoder.decode(VersionedUsageLedger.self, from: metadata)
        for row in try db.records("threads") {
            let old = try decoder.decode(ThreadUsageLedgerEntry.self, from: row.payload)
            guard let incoming = ledger.threads[old.threadID], incoming.sourceTimezoneIdentifier == nil else { continue }
            let days = try Dictionary(uniqueKeysWithValues: db.records("days/" + old.threadID).map {
                ($0.key, try decoder.decode(Int64.self, from: $0.payload))
            })
            let oldTimezone = old.sourceTimezoneIdentifier ?? previous.timezoneIdentifier
            // Recover provenance only for retained buckets; never restore deleted rows or amounts.
            if incoming.dailyTokens == days {
                ledger.threads[old.threadID]?.sourceTimezoneIdentifier = oldTimezone
                ledger.threads[old.threadID]?.dayBucketTimezones = old.dayBucketTimezones
            } else {
                var origins: [String: [String]] = [:]
                for (day, value) in incoming.dailyTokens where days[day] != nil {
                    var zones = Set(old.dayBucketTimezones[day] ?? [oldTimezone])
                    if days[day] != value { zones.insert(ledger.timezoneIdentifier) }
                    if zones != Set([ledger.timezoneIdentifier]) { origins[day] = zones.sorted() }
                }
                ledger.threads[old.threadID]?.sourceTimezoneIdentifier = ledger.timezoneIdentifier
                ledger.threads[old.threadID]?.dayBucketTimezones = origins
                if !origins.isEmpty { ledger.threads[old.threadID]?.isComplete = false }
            }
        }
    }
    func recordAccountObservation(_ observation: ThreadQuotaUsageObservation, timezoneIdentifier: String) throws {
        _ = try load(timezoneIdentifier: timezoneIdentifier)
        guard let db = database else { return }
        let timestamp = observation.timestamp
        let minuteStart = Date(timeIntervalSince1970: floor(timestamp.timeIntervalSince1970 / 60) * 60)
        let minuteEnd = minuteStart.addingTimeInterval(60)
        let cutoff = timestamp.addingTimeInterval(-90 * 86400)
        // Snapshot copying only shares array storage; mutation happens after the transaction commits.
        var values = accountsAreSorted ? cached!.accountObservations : cached!.accountObservations.sorted { $0.timestamp < $1.timestamp }
        let expiredEnd = SortedSearch.firstIndex(in: values) { $0.timestamp >= cutoff }
        let minuteFirst = SortedSearch.firstIndex(in: values) { $0.timestamp >= minuteStart }
        let minuteLast = SortedSearch.firstIndex(in: values) { $0.timestamp >= minuteEnd }
        let replacedIndices = (minuteFirst..<minuteLast).filter { values[$0].accountKey == observation.accountKey }
        let removed = Array(values.prefix(expiredEnd)) + replacedIndices.filter { $0 >= expiredEnd }.map { values[$0] }
        if expiredEnd == 0 && removed == [observation] { return }
        try db.transaction {
            let groups = Dictionary(removed.map { ($0, 1) }, uniquingKeysWith: +)
            for (value, count) in groups {
                let digest = IncrementalUsageDatabase.fingerprint(try encoder.encode(value)).base64EncodedString()
                for index in 0..<count { try db.delete("account", key: index == 0 ? digest : digest + ":\(index)") }
            }
            let payload = try encoder.encode(observation)
            try db.put("account", .init(key: IncrementalUsageDatabase.fingerprint(payload).base64EncodedString(),
                ordinal: Int64(timestamp.timeIntervalSince1970 * 1_000_000), account: observation.accountKey,
                observed: timestamp.timeIntervalSinceReferenceDate, payload: payload))
        }
        if !accountsAreSorted { cached?.accountObservations = values; accountsAreSorted = true }
        values = []
        for index in replacedIndices.reversed() where index >= expiredEnd { cached?.accountObservations.remove(at: index) }
        cached?.accountObservations.removeFirst(expiredEnd)
        let insertion = SortedSearch.firstIndex(in: cached!.accountObservations) { $0.timestamp >= timestamp }
        cached?.accountObservations.insert(observation, at: insertion)
    }

    func save(_ ledger: VersionedUsageLedger) throws {
        _ = try load(timezoneIdentifier: ledger.timezoneIdentifier)
        guard let db = database else { return }
        let previous = cached
        var comparison = ledger; comparison.generatedAt = previous?.generatedAt ?? ledger.generatedAt
        if comparison == previous { cached = ledger; return }
        try db.transaction { try persist(ledger, previous: previous, database: db) }
        cached = ledger; accountsAreSorted = false
    }
    private func persist(_ ledger: VersionedUsageLedger, previous: VersionedUsageLedger?, database db: IncrementalUsageDatabase) throws {
        var metadata = ledger; metadata.threads = [:]; metadata.accountObservations = []
        try db.setMetadata("ledger", encoder.encode(metadata))
        for (id, entry) in ledger.threads where previous?.threads[id] != entry {
            let old = previous?.threads[id]
            var header = entry; header.quotaObservations = []; header.dailyTokens = [:]
            if header.checkpoint != nil { header.checkpoint?.seenCumulativeTotals = [] }
            try db.put("threads", .init(key: id, ordinal: 0, account: nil, observed: nil, payload: encoder.encode(header)))
            for day in Set(old?.dailyTokens.keys.map { $0 } ?? []).subtracting(entry.dailyTokens.keys) { try db.delete("days/" + id, key: day) }
            for (day, tokens) in entry.dailyTokens where old?.dailyTokens[day] != tokens {
                try db.put("days/" + id, .init(key: day, ordinal: 0, account: nil, observed: nil, payload: encoder.encode(tokens)))
            }
            let oldRows = old?.quotaObservations ?? []
            let appended = entry.quotaObservations.count >= oldRows.count && entry.quotaObservations.prefix(oldRows.count).elementsEqual(oldRows)
            if !appended { try db.delete("quota/" + id) }
            for index in (appended ? oldRows.count : 0)..<entry.quotaObservations.count {
                let row = entry.quotaObservations[index]
                try db.put("quota/" + id, .init(key: String(index), ordinal: Int64(index), account: row.accountKey,
                    observed: row.timestamp.timeIntervalSinceReferenceDate, payload: encoder.encode(row)))
            }
            let oldSeen = Set(old?.checkpoint?.seenCumulativeTotals ?? [])
            let seen = Set(entry.checkpoint?.seenCumulativeTotals ?? [])
            for value in oldSeen.subtracting(seen) { try db.delete("seen/" + id, key: String(value)) }
            for value in seen.subtracting(oldSeen) {
                try db.put("seen/" + id, .init(key: String(value), ordinal: value, account: nil, observed: nil, payload: encoder.encode(value)))
            }
        }
        for id in Set(previous?.threads.keys.map { $0 } ?? []).subtracting(ledger.threads.keys) {
            try db.delete("threads", key: id); try db.delete("days/" + id); try db.delete("quota/" + id); try db.delete("seen/" + id)
        }
        let oldAccounts = Dictionary((previous?.accountObservations ?? []).map { ($0, 1) }, uniquingKeysWith: +)
        let accounts = Dictionary(ledger.accountObservations.map { ($0, 1) }, uniquingKeysWith: +)
        for observation in Set(oldAccounts.keys).union(accounts.keys) {
            let oldCount = oldAccounts[observation] ?? 0, count = accounts[observation] ?? 0
            guard oldCount != count else { continue }
            let payload = try encoder.encode(observation)
            let digest = IncrementalUsageDatabase.fingerprint(payload).base64EncodedString()
            func key(_ index: Int) -> String { index == 0 ? digest : digest + ":\(index)" }
            if oldCount > count {
                for index in count..<oldCount { try db.delete("account", key: key(index)) }
            } else {
                for index in oldCount..<count {
                    try db.put("account", .init(key: key(index),
                        ordinal: Int64(observation.timestamp.timeIntervalSince1970 * 1_000_000), account: observation.accountKey,
                        observed: observation.timestamp.timeIntervalSinceReferenceDate, payload: payload))
                }
            }
        }
    }
    func close() { database = nil; cached = nil; accountsAreSorted = false }

    private func verifyImported(_ ledger: VersionedUsageLedger, database db: IncrementalUsageDatabase) throws {
        let headers = try db.records("threads")
        guard headers.count == ledger.threads.count else { throw IncrementalUsageDatabase.Failure(code: 11) }
        for header in headers {
            let entry = try decoder.decode(ThreadUsageLedgerEntry.self, from: header.payload)
            let days = try Dictionary(uniqueKeysWithValues: db.records("days/" + entry.threadID).map { ($0.key, try decoder.decode(Int64.self, from: $0.payload)) })
            guard let expected = ledger.threads[entry.threadID], days == expected.dailyTokens,
                  entry.rootTaskID == expected.rootTaskID, entry.title == expected.title else {
                throw IncrementalUsageDatabase.Failure(code: 11)
            }
            let observations = try db.records("quota/" + entry.threadID).map { try decoder.decode(ThreadQuotaUsageObservation.self, from: $0.payload) }
            let seen = try db.records("seen/" + entry.threadID).map { try decoder.decode(Int64.self, from: $0.payload) }
            guard observations == expected.quotaObservations,
                  seen.sorted() == (expected.checkpoint?.seenCumulativeTotals ?? []).sorted() else {
                throw IncrementalUsageDatabase.Failure(code: 11)
            }
        }
        let accounts = try db.records("account").map { try decoder.decode(ThreadQuotaUsageObservation.self, from: $0.payload) }
        guard accounts.count == ledger.accountObservations.count,
              Set(accounts) == Set(ledger.accountObservations) else { throw IncrementalUsageDatabase.Failure(code: 11) }
    }
    func clear() throws {
        let db = try database ?? IncrementalUsageDatabase(url: fileURL.appendingPathExtension("sqlite"))
        let ledger = VersionedUsageLedger.empty(timezoneIdentifier: cached?.timezoneIdentifier ?? Calendar.current.timeZone.identifier)
        try db.transaction {
            try db.deleteAllRecords(); try db.setMetadata("ledger", encoder.encode(ledger))
            try db.setMetadata("initialized", Data([1])); try db.removeMetadata("exported")
            try db.removeMetadata("exportPending"); try db.removeMetadata("exportPrevious")
        }
        database = db; cached = ledger
        if FileManager.default.fileExists(atPath: fileURL.path) { try FileManager.default.removeItem(at: fileURL) }
    }
    func exportLegacyHistory() throws {
        var ledger = try load(timezoneIdentifier: Calendar.current.timeZone.identifier)
        ledger.schemaVersion = VersionedUsageLedger.currentSchemaVersion
        let legacyEncoder = JSONEncoder(); legacyEncoder.dateEncodingStrategy = .iso8601
        legacyEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payload = try legacyEncoder.encode(ledger)
        if let database { try database.exportLegacy(payload, to: fileURL) }
    }
}
