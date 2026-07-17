import Foundation

public struct CostHistoryPoint: Codable, Hashable, Identifiable, Sendable {
    public let modelID: String
    public let dateKey: String
    public let costUSD: Double
    public let recordedAt: Date

    public var id: String { "\(modelID)|\(dateKey)" }

    public init(modelID: String, dateKey: String, costUSD: Double, recordedAt: Date) {
        self.modelID = modelID
        self.dateKey = dateKey
        self.costUSD = costUSD
        self.recordedAt = recordedAt
    }
}

public enum CostHistoryBuilder {
    public static func merging(
        _ existing: [CostHistoryPoint],
        benchmarks: [ModelBenchmark],
        recordedAt: Date,
        limitPerModel: Int = 90
    ) -> [CostHistoryPoint] {
        var points = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        for benchmark in benchmarks {
            guard
                let latest = benchmark.latest,
                let cost = latest.costUSD,
                cost.isFinite
            else { continue }
            let point = CostHistoryPoint(
                modelID: benchmark.id,
                dateKey: latest.date,
                costUSD: cost,
                recordedAt: recordedAt
            )
            points[point.id] = point
        }

        return Dictionary(grouping: points.values, by: \.modelID)
            .values
            .flatMap { group in
                group.sorted {
                    if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
                    return $0.dateKey < $1.dateKey
                }
                .suffix(max(1, limitPerModel))
            }
            .sorted {
                if $0.modelID != $1.modelID { return $0.modelID < $1.modelID }
                if $0.recordedAt != $1.recordedAt { return $0.recordedAt < $1.recordedAt }
                return $0.dateKey < $1.dateKey
            }
    }
}

public struct StoredRadarState: Codable, Hashable, Sendable {
    public let snapshot: RadarSnapshot
    public let costHistory: [CostHistoryPoint]

    public init(snapshot: RadarSnapshot, costHistory: [CostHistoryPoint]) {
        self.snapshot = snapshot
        self.costHistory = costHistory
    }
}

public protocol SnapshotStoring: Sendable {
    func load() async throws -> StoredRadarState?
    func save(_ state: StoredRadarState) async throws
}

public actor SnapshotStore: SnapshotStoring {
    private let fileURL: URL
    private let legacyFileURL: URL?
    private let fileManager: FileManager

    public init(
        fileURL: URL? = nil,
        legacyFileURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        if let fileURL {
            self.fileURL = fileURL
            self.legacyFileURL = legacyFileURL
        } else {
            let layout = ApplicationSupportLayout(fileManager: fileManager)
            self.fileURL = layout.radarStateURL
            self.legacyFileURL = legacyFileURL ?? layout.legacyRadarStateURL
        }
    }

    public func load() async throws -> StoredRadarState? {
        if fileManager.fileExists(atPath: fileURL.path) {
            let data = try Data(contentsOf: fileURL)
            return try Self.decoder.decode(StoredRadarState.self, from: data)
        }
        guard
            let legacyFileURL,
            fileManager.fileExists(atPath: legacyFileURL.path)
        else { return nil }

        let data = try Data(contentsOf: legacyFileURL)
        let state = try Self.decoder.decode(StoredRadarState.self, from: data)
        try fileManager.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        return state
    }

    public func save(_ state: StoredRadarState) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
