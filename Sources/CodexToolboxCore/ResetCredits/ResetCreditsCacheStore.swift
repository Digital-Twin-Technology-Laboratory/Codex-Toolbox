import Foundation

public actor ResetCreditsCacheStore {
    private struct Header: Decodable {
        let schemaVersion: Int
    }

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
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header = try decoder.decode(Header.self, from: data)
        guard (2...3).contains(header.schemaVersion) else {
            throw ResetCreditsError.protocolIncompatible(
                "重置卡缓存 schemaVersion \(header.schemaVersion) 不受支持"
            )
        }
        let envelope = try decoder.decode(Envelope.self, from: data)
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
        try encoder.encode(Envelope(schemaVersion: 3, snapshot: snapshot))
            .write(to: fileURL, options: .atomic)
    }

    public func clear() throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        try FileManager.default.removeItem(at: fileURL)
    }
}
