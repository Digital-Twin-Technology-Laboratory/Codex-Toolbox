import CodexToolboxCore
import Foundation
import XCTest

final class NativeQuotaLifecycleTests: XCTestCase, @unchecked Sendable {
    @MainActor
    private func fixture(ids: [String], firstCatalogueIDs: [String]? = nil) async throws -> NativeFixture {
        let suite = "ToolboxNativeTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults)
        settings.experimentalLocalCostEstimatesEnabled = false
        settings.automaticRateCardUpdatesEnabled = false
        settings.showsStationRecommendations = false
        settings.automaticRefreshEnabled = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let now = Date(), calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: now)
        let key = String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!)
        let birth = calendar.startOfDay(for: now).ISO8601Format()
        func threads(_ values: [String]) -> [NativeThread] {
            values.map { id in NativeThread(id: id, title: id, createdAt: birth,
                descendantIDs: (0..<600).map { "\(id)-child-\($0)" }, earliestCreatedAt: birth) }
        }
        let history = UsageHistory(generatedAt: now, timezoneIdentifier: calendar.timeZone.identifier,
            days: [DailyUsageSummary(dateKey: key, totalTokens: Int64(ids.count),
                tasks: ids.map { DailyTaskUsage(dateKey: key, rootTaskID: $0, title: $0, tokens: 1, descendantCount: 600) }, isComplete: true)])
        let reader = NativeFixtureReader(history: history, threads: threads(ids),
            firstThreads: firstCatalogueIDs.map(threads))
        let client = GatedNativeFixtureClient()
        let store = NativeTaskQuotaStore(fileURL: folder.appendingPathComponent("native.json"))
        let bundle = Bundle(for: Self.self)
        let rates = try JSONDecoder().decode(RateCardManifest.self, from: Data(contentsOf: XCTUnwrap(bundle.url(forResource: "codex-rate-card-v1", withExtension: "json"))))
        let prices = try JSONDecoder().decode(APIPriceManifest.self, from: Data(contentsOf: XCTUnwrap(bundle.url(forResource: "api-price-card-v1", withExtension: "json"))))
        let model = AppModel(settings: settings, usageReader: reader, resetCreditsReader: NativeFixtureCredits(),
            resetCreditsCache: ResetCreditsCacheStore(fileURL: folder.appendingPathComponent("credits.json")),
            updateManager: AppUpdateManager(defaults: defaults, isEnabled: false),
            identityRepository: AccountIdentityRepository(client: client, directory: folder.appendingPathComponent("identity")),
            nativeTaskQuotaStore: store, bundledRateCard: rates, bundledAPIPriceCard: prices)
        model.usageHistory = history
        await model.refreshResetCredits()
        model.setDashboardVisible(true)
        addTeardownBlock {
            await model.suspendBackgroundWork()
            await reader.releaseFirstCatalogue()
            await client.failAll()
            await store.close()
            try? FileManager.default.removeItem(at: folder)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        return NativeFixture(model: model, reader: reader, client: client, store: store, dayKey: key)
    }

    @MainActor
    func testVisibleFirstBatchPublishesBeforeSlowLaterBatchAndSurvivesItsFailure() async throws {
        let f = try await fixture(ids: ["a", "b", "c"])
        f.model.prioritizeNativeQuotaTasks(["a"], refresh: false)
        let operation = Task { await f.model.refreshNativeTaskQuota(force: true) }
        try await eventually { await f.client.requests.count == 1 }
        try await f.client.completeFirst(percent: 12)
        try await eventually { await f.client.requests.count == 2 }
        try await eventually { f.model.dailyTaskQuotas[10080]?[f.dayKey + "|a"]?.percent == 12 }
        XCTAssertTrue(f.model.isRefreshingNativeTaskQuota)
        await f.client.failFirst()
        await operation.value
        try await eventually { f.model.dailyTaskQuotas[10080]?[f.dayKey + "|a"]?.percent == 12 }
        XCTAssertNotNil(f.model.nativeTaskQuotaError)
        let requested = await f.client.requests
        XCTAssertEqual(requested, [["a"], ["b"]])
        let stored = try await f.store.snapshots(accountKey: GatedNativeFixtureClient.accountA)
        XCTAssertEqual(stored.map(\.thread.id), ["a"])
    }

    @MainActor
    func testSelectionReordersPendingWorkAndOnlyFetchesNewlySelectedTasks() async throws {
        let f = try await fixture(ids: ["a", "b", "c"])
        f.model.prioritizeNativeQuotaTasks(["a"], refresh: false)
        let operation = Task { await f.model.refreshNativeTaskQuota(priorityOnly: true) }
        try await eventually { await f.client.requests.count == 1 }
        f.model.prioritizeNativeQuotaTasks(["a", "c"])
        try await f.client.completeFirst(percent: 1)
        try await eventually { await f.client.requests.count == 2 }
        var requested = await f.client.requests
        XCTAssertEqual(requested, [["a"], ["c"]])
        try await f.client.completeFirst(percent: 3)
        await operation.value
        f.model.prioritizeNativeQuotaTasks(["b", "c"])
        try await eventually { await f.client.requests.count == 3 }
        requested = await f.client.requests
        XCTAssertEqual(requested, [["a"], ["c"], ["b"]])
        try await f.client.completeFirst(percent: 2)
        try await eventually { !f.model.isRefreshingNativeTaskQuota }
        try await eventually { f.model.dailyTaskQuotas[10080]?.count == 3 }
        let catalogueCalls = await f.reader.catalogueCalls
        XCTAssertEqual(catalogueCalls, 2)
    }

    @MainActor
    func testLateCatalogueWhileAsleepCannotStartNativeRequestOrPublish() async throws {
        let f = try await fixture(ids: ["a"], firstCatalogueIDs: ["a"])
        f.model.prioritizeNativeQuotaTasks(["a"], refresh: false)
        let operation = Task { await f.model.refreshNativeTaskQuota(force: true) }
        try await eventually { await f.reader.catalogueCalls == 1 }
        await f.model.suspendBackgroundWork()
        await f.reader.releaseFirstCatalogue()
        await operation.value
        let requests = await f.client.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertTrue(f.model.dailyTaskQuotas.isEmpty)
        let stored = try await f.store.snapshots(accountKey: GatedNativeFixtureClient.accountA)
        XCTAssertTrue(stored.isEmpty)
    }

    @MainActor
    func testAccountABADiscardsLateCatalogueAndRetriesUsingCurrentCatalogue() async throws {
        let f = try await fixture(ids: ["fresh"], firstCatalogueIDs: ["stale"])
        f.model.prioritizeNativeQuotaTasks(["stale", "fresh"], refresh: false)
        let operation = Task { await f.model.refreshNativeTaskQuota(force: true) }
        try await eventually { await f.reader.catalogueCalls == 1 }
        await f.client.setAccount(GatedNativeFixtureClient.accountB)
        await f.model.checkAccountIdentity()
        await f.client.setAccount(GatedNativeFixtureClient.accountA)
        await f.model.checkAccountIdentity()
        await f.reader.releaseFirstCatalogue()
        await operation.value
        try await eventually { await f.client.requests.count == 1 }
        let requested = await f.client.requests
        XCTAssertEqual(requested, [["fresh"]])
        let catalogueCalls = await f.reader.catalogueCalls
        XCTAssertEqual(catalogueCalls, 2)
        try await f.client.completeFirst(percent: 22)
        try await eventually { !f.model.isRefreshingNativeTaskQuota }
        let stored = try await f.store.snapshots(accountKey: GatedNativeFixtureClient.accountA)
        XCTAssertEqual(stored.map(\.thread.id), ["fresh"])
    }

    @MainActor
    private func eventually(_ condition: @escaping @MainActor () async -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !(await condition()) {
            guard ContinuousClock.now < deadline else {
                XCTFail("Expected AppModel state did not arrive before the deadline")
                throw NativeAnalyticsError.timeout
            }
            try await Task.sleep(for: .milliseconds(5))
        }
    }
}

private struct NativeFixture {
    let model: AppModel
    let reader: NativeFixtureReader
    let client: GatedNativeFixtureClient
    let store: NativeTaskQuotaStore
    let dayKey: String
}

private actor NativeFixtureReader: CodexUsageReading, UsageHistoryClearing, AccountQuotaSnapshotRecording, NativeThreadReading {
    let history: UsageHistory
    let threads: [NativeThread]
    let firstThreads: [NativeThread]?
    private(set) var catalogueCalls = 0
    private var firstWaiter: CheckedContinuation<Void, Never>?
    private var firstReleased = false
    init(history: UsageHistory, threads: [NativeThread], firstThreads: [NativeThread]?) {
        self.history = history; self.threads = threads; self.firstThreads = firstThreads
    }
    func readUsage(now: Date, calendar: Calendar, rateCard: RateCardManifest?, rateCardMode: RateCardMode, apiPriceCard: APIPriceManifest?) async throws -> UsageHistory { history }
    func clearHistory() async throws {}
    func recordAccountQuotaSnapshot(windows: [AccountQuotaWindow], planType: String?, timestamp: Date, accountKey: String?) async throws {}
    func nativeCatalogue(now: Date) async throws -> NativeCatalogue {
        catalogueCalls += 1
        let isFirst = catalogueCalls == 1
        if isFirst && firstThreads != nil && !firstReleased {
            await withCheckedContinuation { firstWaiter = $0 }
        }
        let selected = isFirst ? (firstThreads ?? threads) : threads
        return NativeCatalogue(threads: selected, eligibleCount: selected.count, excludedCount: 0, since: now.ISO8601Format())
    }
    func releaseFirstCatalogue() { firstReleased = true; firstWaiter?.resume(); firstWaiter = nil }
}

private actor GatedNativeFixtureClient: NativeAuthenticationReading, NativeTaskUsageReading {
    static let accountA = String(repeating: "a", count: 64)
    static let accountB = String(repeating: "b", count: 64)
    private var account = accountA
    private(set) var requests: [[String]] = []
    private var pending: [([String], String, CheckedContinuation<NativeTaskUsageReport, Error>)] = []
    func setAccount(_ account: String) { self.account = account }
    func authentication(salt: String) async throws -> AccountAuthentication { .chatGPT(accountKey: account) }
    func taskUsage(salt: String, threads: [NativeThread]) async throws -> NativeTaskUsageReport {
        let ids = threads.map(\.id)
        requests.append(ids)
        return try await withCheckedThrowingContinuation { pending.append((ids, account, $0)) }
    }
    func completeFirst(percent: Double) throws {
        let (ids, account, continuation) = pending.removeFirst()
        let rows: [[String: Any]] = ids.map { ["id": $0, "status": "available", "usageSource": "native",
            "weeklyPercent": percent, "fiveHourPercent": percent, "groups": []] }
        let data = try JSONSerialization.data(withJSONObject: ["schemaVersion": 3, "accountKey": account,
            "planType": "pro", "collectedAt": Date().ISO8601Format(), "threads": rows])
        continuation.resume(returning: try NativeTaskUsageReport.decode(data))
    }
    func failFirst() { pending.removeFirst().2.resume(throwing: NativeAnalyticsError.timeout) }
    func failAll() { let values = pending; pending = []; for value in values { value.2.resume(throwing: CancellationError()) } }
}

private struct NativeFixtureCredits: AccountRateLimitsReading {
    func readResetCredits() async throws -> ResetCreditsSnapshot {
        ResetCreditsSnapshot(availableCount: 2, credits: [],
            quotaWindows: [AccountQuotaWindow(durationMinutes: 10080, usedPercent: 50, resetsAt: Date().addingTimeInterval(86400))], fetchedAt: Date())
    }
}
