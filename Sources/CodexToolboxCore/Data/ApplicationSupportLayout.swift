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

    public var radarEfficiencyStateURL: URL {
        currentDirectory.appendingPathComponent("radar-intelligence-efficiency-v2.json")
    }
    public var stationRecommendationsStateURL: URL {
        currentDirectory.appendingPathComponent("radar-station-recommendations-v1.json")
    }
    public var radarStateURL: URL { currentDirectory.appendingPathComponent("radar-latest.json") }
    public var legacyRadarStateURL: URL { legacyDirectory.appendingPathComponent("latest.json") }
    public var usageLedgerURL: URL { currentDirectory.appendingPathComponent("usage-ledger.json") }
    public var rateCardCacheURL: URL { currentDirectory.appendingPathComponent("codex-rate-card-v1.json") }
    public var apiPriceCardCacheURL: URL { currentDirectory.appendingPathComponent("api-price-card-v1.json") }
    public var resetCreditsCacheURL: URL { currentDirectory.appendingPathComponent("reset-credits.json") }
}
