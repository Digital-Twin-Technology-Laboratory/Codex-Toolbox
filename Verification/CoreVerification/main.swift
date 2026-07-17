import Foundation
import CodexToolboxCore

actor VerificationRadarClient: RadarClient {
    private let result: RadarFetchResult
    private(set) var calls = 0

    init(result: RadarFetchResult) {
        self.result = result
    }

    func fetch(cacheValidators: CacheValidators?) async throws -> RadarFetchResult {
        calls += 1
        try await Task.sleep(for: .milliseconds(25))
        return result
    }

    func callCount() -> Int { calls }
}

actor VerificationSnapshotStore: SnapshotStoring {
    private var state: StoredRadarState?

    func load() async throws -> StoredRadarState? { state }
    func save(_ state: StoredRadarState) async throws { self.state = state }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fatalError("Verification failed: \(message)")
    }
}

require(AppMetadata.displayName == "Codex Toolbox", "display name")
require(AppMetadata.bundleIdentifier == "io.github.zzzzzzjw.ShowCodexIQ", "bundle identifier")
require(!AppMetadata.version.isEmpty && !AppMetadata.version.contains("$("), "version")

let fixtureURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Tests/CodexToolboxTests/Fixtures/current-v2.json")
let fixture = try Data(contentsOf: fixtureURL)
let response = try JSONDecoder().decode(RadarResponse.self, from: fixture)
require(response.benchmarks.count == 3, "fixture benchmark count")
require(RankingEngine.rank(response.benchmarks, by: .iq).first?.id == "gpt_56_sol_xhigh", "IQ ranking")
require(RankingEngine.rank(response.benchmarks, by: .cost).first?.id == "gpt_56_luna_medium", "cost ranking")

let qualityWeights = RankingWeights(iq: 100, cost: 0, duration: 0)
require(qualityWeights.isValid, "custom weights")
require(
    RankingEngine.rank(response.benchmarks, by: .overall, weights: qualityWeights).first?.id == "gpt_56_sol_xhigh",
    "weighted overall ranking"
)

require(MetricFormatter.detailValue(2.429979, metric: .cost) == "$2.43", "cost formatting")
require(MetricFormatter.detailValue(82.25, metric: .overall) == "82.3", "stable half-up formatting")
require(MetricFormatter.menuBarValue(5_103, metric: .duration) == "1.4h", "duration formatting")
require(MetricFormatter.compactModelName("GPT-5.6 Sol xhigh") == "5.6 Sol xh", "compact model name")
require(
    MetricFormatter.benchmarkDateLabel("2026-07-17T13:03:49+08:00") == "2026-07-17 · 13:03:49",
    "ISO benchmark date"
)
require(
    MetricFormatter.benchmarkDateLabel(
        "2026-07-17T13:03:49+08:00",
        includesDetailedTime: false
    ) == "2026-07-17 · PM",
    "compact benchmark date"
)

let settingsVerified = await MainActor.run {
    let suite = "CoreVerification.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = AppSettings(defaults: defaults)
    let compactMenuBarDefaults = settings.menuBarRankStyle == .hidden
        && !settings.showsMenuBarDetails
        && settings.showsDetailedBenchmarkTime
    settings.menuBarRankStyle = .period
    settings.showsMenuBarDetails = true
    settings.showsDetailedBenchmarkTime = false
    let menuBarPreferencesPersist = AppSettings(defaults: defaults).menuBarRankStyle == .period
        && AppSettings(defaults: defaults).showsMenuBarDetails
        && !AppSettings(defaults: defaults).showsDetailedBenchmarkTime
    let rejectedInvalid = !settings.apply(weights: RankingWeights(iq: 80, cost: 20, duration: 20))
    let acceptedValid = settings.apply(weights: RankingWeights(iq: 70, cost: 20, duration: 10))
    return compactMenuBarDefaults
        && menuBarPreferencesPersist
        && rejectedInvalid
        && acceptedValid
        && settings.rankingWeights.iq == 70
}
require(settingsVerified, "settings validation")

let trendModelIDs = RankingEngine.rank(response.benchmarks, by: .iq).prefix(3).map(\.id)
let iqTrend = TrendPointBuilder.points(
    benchmarks: response.benchmarks,
    costHistory: [],
    metric: .iq,
    modelIDs: trendModelIDs
)
require(TrendPointBuilder.hasDrawableSeries(iqTrend), "remote IQ trend")
require(TrendPointBuilder.shortDateLabel("2026-07-13-pm_2") == "07/13 PM", "trend date label")

let fetchedAt = Date(timeIntervalSince1970: 1_700_000_000)
let snapshot = RadarSnapshot(
    schemaVersion: response.schemaVersion,
    sourceMonitoredAt: response.monitoredAt,
    fetchedAt: fetchedAt,
    benchmarks: response.benchmarks,
    validators: CacheValidators(etag: "fixture-etag", lastModified: "fixture-date")
)
let temporaryDirectory = FileManager.default.temporaryDirectory
    .appendingPathComponent("CodexToolbox-\(UUID().uuidString)", isDirectory: true)
let diskStore = SnapshotStore(fileURL: temporaryDirectory.appendingPathComponent("latest.json"))
let stored = StoredRadarState(
    snapshot: snapshot,
    costHistory: CostHistoryBuilder.merging([], benchmarks: snapshot.benchmarks, recordedAt: fetchedAt)
)
try await diskStore.save(stored)
let loadedState = try await diskStore.load()
require(loadedState == stored, "snapshot round trip")
try? FileManager.default.removeItem(at: temporaryDirectory)

let client = VerificationRadarClient(result: .modified(snapshot))
let memoryStore = VerificationSnapshotStore()
let repository = RadarRepository(client: client, store: memoryStore)
async let firstRefresh = repository.refresh()
async let secondRefresh = repository.refresh()
let refreshStates = await [firstRefresh, secondRefresh]
require(refreshStates.allSatisfy { $0.snapshot?.benchmarks.count == 3 }, "repository refresh")
let clientCalls = await client.callCount()
require(clientCalls == 1, "single-flight refresh")

print("✓ Core model, ranking, cache, settings, and repository verification passed")
