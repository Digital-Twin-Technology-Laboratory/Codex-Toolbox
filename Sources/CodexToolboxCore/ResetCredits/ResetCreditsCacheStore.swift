import Foundation

public actor ResetCreditsCacheStore {
    private struct Envelope: Codable, Sendable {
        let schemaVersion: Int
        let snapshot: ResetCreditsSnapshot
    }

    private let fileURL: URL

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ApplicationSupportLayout().resetCreditsCacheURL
    }

    public func load() throws -> ResetCreditsSnapshot? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(Envelope.self, from: Data(contentsOf: fileURL))
        guard envelope.schemaVersion == 1 else {
            throw ResetCreditsError.protocolIncompatible(
                "重置卡缓存 schemaVersion \(envelope.schemaVersion) 不受支持"
            )
        }
        return envelope.snapshot
    }

    public func save(_ snapshot: ResetCreditsSnapshot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(Envelope(schemaVersion: 1, snapshot: snapshot))
            .write(to: fileURL, options: .atomic)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
