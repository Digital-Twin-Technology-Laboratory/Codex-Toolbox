import CryptoKit
import Foundation

/// Keeps frequent check timestamps separate from the validated payload.
struct PublicCachePersistence {
    struct Check: Codable {
        let payloadDigest: String
        let fetchedAt: Date
        let validators: CacheValidators
    }
    let fileURL: URL
    private var payloadDigest: String?
    private var metadataURL: URL { fileURL.appendingPathExtension("check.json") }

    init(fileURL: URL) { self.fileURL = fileURL }

    mutating func didLoad(_ data: Data) -> Check? {
        let digest = Self.digest(data)
        payloadDigest = digest
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: metadataURL.path),
              ((attributes[.size] as? NSNumber)?.intValue ?? .max) <= 16_384,
              let metadata = try? Data(contentsOf: metadataURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let check = try? decoder.decode(Check.self, from: metadata), check.payloadDigest == digest else { return nil }
        return check
    }

    mutating func save(_ data: Data) throws {
        try Task.checkCancellation()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        payloadDigest = Self.digest(data)
        try? FileManager.default.removeItem(at: metadataURL)
    }

    mutating func saveCheck(fetchedAt: Date, validators: CacheValidators) throws -> Bool {
        try Task.checkCancellation()
        if payloadDigest == nil, let data = try? Data(contentsOf: fileURL) { _ = didLoad(data) }
        guard let payloadDigest else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(Check(payloadDigest: payloadDigest, fetchedAt: fetchedAt, validators: validators))
            .write(to: metadataURL, options: .atomic)
        return true
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension RadarSnapshot {
    func hasSamePayload(as other: Self) -> Bool {
        schemaVersion == other.schemaVersion && sourceMonitoredAt == other.sourceMonitoredAt
            && benchmarks == other.benchmarks && benchmarkID == other.benchmarkID
            && aggregationMode == other.aggregationMode && scoringMode == other.scoringMode
            && priceRollingWindow == other.priceRollingWindow && managed == other.managed
    }

    func withCheck(_ check: PublicCachePersistence.Check) -> Self {
        Self(schemaVersion: schemaVersion, sourceMonitoredAt: sourceMonitoredAt,
             fetchedAt: check.fetchedAt, benchmarks: benchmarks, validators: check.validators,
             benchmarkID: benchmarkID, aggregationMode: aggregationMode, scoringMode: scoringMode,
             priceRollingWindow: priceRollingWindow, managed: managed)
    }
}

extension StationRecommendationSnapshot {
    func hasSamePayload(as other: Self) -> Bool {
        schema == other.schema && mode == other.mode && generatedAt == other.generatedAt
            && sourceUpdatedAt == other.sourceUpdatedAt && scenarios == other.scenarios && managed == other.managed
    }

    func withCheck(_ check: PublicCachePersistence.Check) -> Self {
        Self(schema: schema, mode: mode, generatedAt: generatedAt, sourceUpdatedAt: sourceUpdatedAt,
             fetchedAt: check.fetchedAt, scenarios: scenarios, validators: check.validators, managed: managed)
    }
}
