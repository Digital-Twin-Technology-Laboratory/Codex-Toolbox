import Foundation

public struct ApplicationSupportLayout: Sendable {
    public let currentDirectory: URL
    public let legacyDirectory: URL

    public init(baseDirectory: URL? = nil, fileManager: FileManager = .default) {
        let base = baseDirectory
            ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        currentDirectory = base.appendingPathComponent("CodexToolbox", isDirectory: true)
        legacyDirectory = base.appendingPathComponent("ShowCodexIQ", isDirectory: true)
    }

    public var radarStateURL: URL { currentDirectory.appendingPathComponent("radar-latest.json") }
    public var legacyRadarStateURL: URL { legacyDirectory.appendingPathComponent("latest.json") }
    public var usageLedgerURL: URL { currentDirectory.appendingPathComponent("usage-ledger.json") }
    public var resetCreditsCacheURL: URL { currentDirectory.appendingPathComponent("reset-credits.json") }
}
