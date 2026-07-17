import Foundation

struct UsageRolloutCheckpoint: Codable, Hashable, Sendable {
    var path: String
    var fileSize: Int64
    var parsedOffset: UInt64
    var seenCumulativeTotals: [Int64]
}

struct ThreadUsageLedgerEntry: Codable, Hashable, Sendable {
    var threadID: String
    var rootTaskID: String
    var title: String
    var dailyTokens: [String: Int64]
    var checkpoint: UsageRolloutCheckpoint?
    var isComplete: Bool
}

struct VersionedUsageLedger: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var generatedAt: Date
    var timezoneIdentifier: String
    var threads: [String: ThreadUsageLedgerEntry]
    var warnings: [String]

    static func empty(timezoneIdentifier: String) -> VersionedUsageLedger {
        VersionedUsageLedger(
            schemaVersion: currentSchemaVersion,
            generatedAt: .distantPast,
            timezoneIdentifier: timezoneIdentifier,
            threads: [:],
            warnings: []
        )
    }
}

struct UsageLedgerStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(timezoneIdentifier: String) throws -> VersionedUsageLedger {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return .empty(timezoneIdentifier: timezoneIdentifier)
        }
        let data = try Data(contentsOf: fileURL)
        let ledger = try decoder.decode(VersionedUsageLedger.self, from: data)
        guard ledger.schemaVersion == VersionedUsageLedger.currentSchemaVersion else {
            throw LocalCodexUsageError.unsupportedLedgerSchema(ledger.schemaVersion)
        }
        guard ledger.timezoneIdentifier == timezoneIdentifier else {
            // Day boundaries depend on the system time zone, so a change requires a
            // deterministic rebuild from still-readable rollout files.
            return .empty(timezoneIdentifier: timezoneIdentifier)
        }
        return ledger
    }

    func save(_ ledger: VersionedUsageLedger) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(ledger).write(to: fileURL, options: .atomic)
    }

    func clear() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}

public actor JSONUsageHistoryStore: UsageHistoryStoring {
    private struct Envelope: Codable, Sendable {
        let schemaVersion: Int
        let history: UsageHistory
    }

    private let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> UsageHistory? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: Data(contentsOf: fileURL))
        guard envelope.schemaVersion == 1 else {
            throw LocalCodexUsageError.unsupportedLedgerSchema(envelope.schemaVersion)
        }
        return envelope.history
    }

    public func save(_ history: UsageHistory) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(Envelope(schemaVersion: 1, history: history))
            .write(to: fileURL, options: .atomic)
    }

    public func clear() throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }
}
