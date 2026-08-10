import Foundation

struct UsageRolloutCheckpoint: Codable, Hashable, Sendable {
    var path: String
    var fileSize: Int64
    var parsedOffset: UInt64
    var seenCumulativeTotals: [Int64]
    var lastModelID: String?
    var lastExecutionContext: UsageExecutionContext?

    init(
        path: String,
        fileSize: Int64,
        parsedOffset: UInt64,
        seenCumulativeTotals: [Int64],
        lastModelID: String?,
        lastExecutionContext: UsageExecutionContext? = nil
    ) {
        self.path = path
        self.fileSize = fileSize
        self.parsedOffset = parsedOffset
        self.seenCumulativeTotals = seenCumulativeTotals
        self.lastModelID = lastModelID
        self.lastExecutionContext = lastExecutionContext
    }
}

struct ThreadQuotaUsageObservation: Codable, Hashable, Sendable {
    var timestamp: Date
    var tokenIncrement: Int64
    var quotaUsageWeight: Double?
    var tokenBreakdown: UsageTokenBreakdown?
    var executionContext: UsageExecutionContext?
    var creditEstimate: TokenCreditEstimate?
    var windows: [AccountQuotaWindow]

    init(
        timestamp: Date,
        tokenIncrement: Int64,
        quotaUsageWeight: Double? = nil,
        tokenBreakdown: UsageTokenBreakdown? = nil,
        executionContext: UsageExecutionContext? = nil,
        creditEstimate: TokenCreditEstimate? = nil,
        windows: [AccountQuotaWindow]
    ) {
        self.timestamp = timestamp
        self.tokenIncrement = max(0, tokenIncrement)
        self.quotaUsageWeight = quotaUsageWeight
        self.tokenBreakdown = tokenBreakdown
        self.executionContext = executionContext
        self.creditEstimate = creditEstimate
        self.windows = windows
    }
}

struct ThreadUsageLedgerEntry: Codable, Hashable, Sendable {
    var threadID: String
    var rootTaskID: String
    var title: String
    var dailyTokens: [String: Int64]
    var quotaObservations: [ThreadQuotaUsageObservation]
    var checkpoint: UsageRolloutCheckpoint?
    var isComplete: Bool

    init(
        threadID: String,
        rootTaskID: String,
        title: String,
        dailyTokens: [String: Int64],
        quotaObservations: [ThreadQuotaUsageObservation] = [],
        checkpoint: UsageRolloutCheckpoint?,
        isComplete: Bool
    ) {
        self.threadID = threadID
        self.rootTaskID = rootTaskID
        self.title = title
        self.dailyTokens = dailyTokens
        self.quotaObservations = quotaObservations
        self.checkpoint = checkpoint
        self.isComplete = isComplete
    }

    private enum CodingKeys: String, CodingKey {
        case threadID
        case rootTaskID
        case title
        case dailyTokens
        case quotaObservations
        case checkpoint
        case isComplete
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            threadID: try container.decode(String.self, forKey: .threadID),
            rootTaskID: try container.decode(String.self, forKey: .rootTaskID),
            title: try container.decode(String.self, forKey: .title),
            dailyTokens: try container.decode([String: Int64].self, forKey: .dailyTokens),
            quotaObservations: try container.decodeIfPresent(
                [ThreadQuotaUsageObservation].self,
                forKey: .quotaObservations
            ) ?? [],
            checkpoint: try container.decodeIfPresent(
                UsageRolloutCheckpoint.self,
                forKey: .checkpoint
            ),
            isComplete: try container.decode(Bool.self, forKey: .isComplete)
        )
    }
}

struct VersionedUsageLedger: Codable, Hashable, Sendable {
    static let currentSchemaVersion = 7

    var schemaVersion: Int
    var generatedAt: Date
    var timezoneIdentifier: String
    var threads: [String: ThreadUsageLedgerEntry]
    var accountObservations: [ThreadQuotaUsageObservation]
    var warnings: [String]

    static func empty(timezoneIdentifier: String) -> VersionedUsageLedger {
        VersionedUsageLedger(
            schemaVersion: currentSchemaVersion,
            generatedAt: .distantPast,
            timezoneIdentifier: timezoneIdentifier,
            threads: [:],
            accountObservations: [],
            warnings: []
        )
    }

    init(
        schemaVersion: Int,
        generatedAt: Date,
        timezoneIdentifier: String,
        threads: [String: ThreadUsageLedgerEntry],
        accountObservations: [ThreadQuotaUsageObservation] = [],
        warnings: [String]
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.timezoneIdentifier = timezoneIdentifier
        self.threads = threads
        self.accountObservations = accountObservations
        self.warnings = warnings
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case generatedAt
        case timezoneIdentifier
        case threads
        case accountObservations
        case warnings
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            schemaVersion: try container.decode(Int.self, forKey: .schemaVersion),
            generatedAt: try container.decode(Date.self, forKey: .generatedAt),
            timezoneIdentifier: try container.decode(String.self, forKey: .timezoneIdentifier),
            threads: try container.decode([String: ThreadUsageLedgerEntry].self, forKey: .threads),
            accountObservations: try container.decodeIfPresent(
                [ThreadQuotaUsageObservation].self,
                forKey: .accountObservations
            ) ?? [],
            warnings: try container.decodeIfPresent([String].self, forKey: .warnings) ?? []
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
        var ledger = try decoder.decode(VersionedUsageLedger.self, from: data)
        guard (1...VersionedUsageLedger.currentSchemaVersion).contains(ledger.schemaVersion) else {
            throw LocalCodexUsageError.unsupportedLedgerSchema(ledger.schemaVersion)
        }
        guard ledger.timezoneIdentifier == timezoneIdentifier else {
            // Day boundaries depend on the system time zone, so a change requires a
            // deterministic rebuild from still-readable rollout files.
            return .empty(timezoneIdentifier: timezoneIdentifier)
        }
        let sourceSchemaVersion = ledger.schemaVersion
        if sourceSchemaVersion < VersionedUsageLedger.currentSchemaVersion {
            ledger.schemaVersion = VersionedUsageLedger.currentSchemaVersion
        }
        if sourceSchemaVersion == 1 {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
            let components = calendar.dateComponents([.year, .month, .day], from: Date())
            let todayKey = String(
                format: "%04d-%02d-%02d",
                components.year ?? 0,
                components.month ?? 0,
                components.day ?? 0
            )
            for threadID in ledger.threads.keys {
                ledger.threads[threadID]?.quotaObservations = []
                // The dashboard estimates today's tasks. Reparse only threads that
                // already contributed today; older threads retain their offsets and
                // begin collecting observations if they receive a future event.
                if ledger.threads[threadID]?.dailyTokens[todayKey] != nil {
                    ledger.threads[threadID]?.checkpoint = nil
                }
            }
        } else if sourceSchemaVersion < VersionedUsageLedger.currentSchemaVersion {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: timezoneIdentifier) ?? .current
            let rebuildStart = calendar.date(byAdding: .day, value: -8, to: Date()) ?? .distantPast
            let rebuildStartComponents = calendar.dateComponents(
                [.year, .month, .day],
                from: rebuildStart
            )
            let rebuildStartKey = String(
                format: "%04d-%02d-%02d",
                rebuildStartComponents.year ?? 0,
                rebuildStartComponents.month ?? 0,
                rebuildStartComponents.day ?? 0
            )
            for threadID in ledger.threads.keys {
                let hasActiveQuotaWindow = ledger.threads[threadID]?.quotaObservations.contains {
                    $0.windows.contains { $0.resetsAt > Date() }
                } == true
                // Schema 6 and earlier persisted derived weights. Schema 7
                // keeps raw token/context evidence so historical rates can be
                // selected by event time and recalculated safely.
                ledger.threads[threadID]?.quotaObservations = []
                let needsBoundedRebuild = ledger.threads[threadID]?.dailyTokens.keys.contains {
                    $0 >= rebuildStartKey
                } == true || hasActiveQuotaWindow
                if needsBoundedRebuild {
                    ledger.threads[threadID]?.checkpoint = nil
                }
            }
            ledger.accountObservations = []
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
