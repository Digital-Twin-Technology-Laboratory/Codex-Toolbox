import CodexToolboxCore
import Foundation
import XCTest

final class AppModelLifecycleTests: XCTestCase, @unchecked Sendable {
    @MainActor
    private func model(reader: GatedUsageReader, identity: TestIdentity = TestIdentity(), credits: TestCredits = TestCredits()) throws -> AppModel {
        let suite = "ToolboxAppTests-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let settings = AppSettings(defaults: defaults)
        settings.experimentalLocalCostEstimatesEnabled = true
        settings.automaticRateCardUpdatesEnabled = false
        settings.showsStationRecommendations = false
        settings.automaticRefreshEnabled = false
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        let bundle = Bundle(for: Self.self)
        let rates = try JSONDecoder().decode(RateCardManifest.self, from: Data(contentsOf: XCTUnwrap(bundle.url(forResource: "codex-rate-card-v1", withExtension: "json"))))
        let prices = try JSONDecoder().decode(APIPriceManifest.self, from: Data(contentsOf: XCTUnwrap(bundle.url(forResource: "api-price-card-v1", withExtension: "json"))))
        let model = AppModel(settings: settings, usageReader: reader, resetCreditsReader: credits,
            resetCreditsCache: ResetCreditsCacheStore(fileURL: folder.appendingPathComponent("credits.json")),
            updateManager: AppUpdateManager(defaults: defaults, isEnabled: false),
            identityRepository: AccountIdentityRepository(client: identity, directory: folder.appendingPathComponent("identity")),
            nativeTaskQuotaStore: NativeTaskQuotaStore(fileURL: folder.appendingPathComponent("native.json")),
            bundledRateCard: rates, bundledAPIPriceCard: prices)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: folder)
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        return model
    }

    @MainActor
    func testNewCostModeDuringReadDiscardsOldResultAndRunsLatestRequest() async throws {
        let reader = GatedUsageReader()
        let model = try model(reader: reader)
        let operation = Task { await model.refreshUsage() }
        await reader.waitForCalls(1)
        model.settings.rateCardMode = .legacy
        // A second caller while reading must request one latest read, not lose it.
        await model.refreshUsage()
        await reader.completeFirst(tokens: 11)
        await reader.waitForCalls(2)
        XCTAssertNil(model.usageHistory)
        await reader.completeFirst(tokens: 22)
        await operation.value
        XCTAssertEqual(model.usageHistory?.days.first?.totalTokens, 22)
        let modes = await reader.modes
        XCTAssertEqual(modes, [.automatic, .legacy])
        await model.suspendBackgroundWork()
    }

    @MainActor
    func testSleepRejectsLateReaderAndSettingsCannotRestartReadsWhileAsleep() async throws {
        let reader = GatedUsageReader()
        let model = try model(reader: reader)
        let operation = Task { await model.refreshUsage() }
        await reader.waitForCalls(1)
        await model.suspendBackgroundWork()
        model.settings.rateCardMode = .legacy
        model.settingsDidChange()
        await reader.completeFirst(tokens: 11)
        await operation.value
        await model.refreshUsage()
        XCTAssertNil(model.usageHistory)
        let count = await reader.modes.count
        XCTAssertEqual(count, 1)
        await model.suspendBackgroundWork()
    }

    @MainActor
    func testAccountABARejectsOldQuotaAndRetriesCurrentSession() async throws {
        let reader = GatedUsageReader(), identity = TestIdentity(), credits = TestCredits(gateFirst: true)
        await identity.set(.chatGPT(accountKey: "a"))
        let model = try model(reader: reader, identity: identity, credits: credits)
        let operation = Task { await model.refreshResetCredits() }
        await credits.waitForFirst()
        await identity.set(.chatGPT(accountKey: "b")); await model.checkAccountIdentity()
        await identity.set(.chatGPT(accountKey: "a")); await model.checkAccountIdentity()
        await credits.completeFirst()
        await operation.value
        // Drain the scheduled current-session retry through its real entry point.
        await model.refreshResetCredits()
        for _ in 0..<100 where model.isRefreshingResetCredits { await Task.yield() }
        XCTAssertNotEqual(model.resetCreditsSnapshot?.availableCount, 99)
        XCTAssertEqual(model.resetCreditsSnapshot?.availableCount, 2)
        await model.suspendBackgroundWork()
    }

    @MainActor
    func testRadarIntervalChangeDoesNotStartUnrelatedUsageRead() async throws {
        let reader = GatedUsageReader()
        let model = try model(reader: reader)
        model.settings.refreshInterval = .fourHours
        model.settingsDidChange()
        // Let the reconfiguration complete; the configured operations are minutes away.
        try await Task.sleep(for: .milliseconds(100))
        let count = await reader.modes.count
        XCTAssertEqual(count, 0)
        await model.suspendBackgroundWork()
    }
}

private actor GatedUsageReader: CodexUsageReading, UsageHistoryClearing, AccountQuotaSnapshotRecording {
    private(set) var modes: [RateCardMode] = []
    private var reads: [CheckedContinuation<UsageHistory, Error>] = []
    private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
    func readUsage(now: Date, calendar: Calendar, rateCard: RateCardManifest?, rateCardMode: RateCardMode, apiPriceCard: APIPriceManifest?) async throws -> UsageHistory {
        modes.append(rateCardMode)
        return try await withCheckedThrowingContinuation { continuation in
            reads.append(continuation)
            let ready = observers.filter { $0.0 <= modes.count }; observers.removeAll { $0.0 <= modes.count }
            ready.forEach { $0.1.resume() }
        }
    }
    func waitForCalls(_ count: Int) async {
        guard modes.count < count else { return }
        await withCheckedContinuation { observers.append((count, $0)) }
    }
    func completeFirst(tokens: Int64) {
        reads.removeFirst().resume(returning: UsageHistory(generatedAt: Date(), timezoneIdentifier: Calendar.current.timeZone.identifier,
            days: [DailyUsageSummary(dateKey: "2026-10-23", totalTokens: tokens, tasks: [], isComplete: true)]))
    }
    func clearHistory() async throws {}
    func recordAccountQuotaSnapshot(windows: [AccountQuotaWindow], planType: String?, timestamp: Date, accountKey: String?) async throws {}
}

private actor TestIdentity: NativeAuthenticationReading {
    private var value: AccountAuthentication = .signedOut
    func set(_ value: AccountAuthentication) { self.value = value }
    func authentication(salt: String) async throws -> AccountAuthentication { value }
}

private actor TestCredits: AccountRateLimitsReading {
    private let gateFirst: Bool
    private var calls = 0
    private var pending: CheckedContinuation<ResetCreditsSnapshot, Error>?
    private var observer: CheckedContinuation<Void, Never>?
    init(gateFirst: Bool = false) { self.gateFirst = gateFirst }
    func readResetCredits() async throws -> ResetCreditsSnapshot {
        calls += 1
        if gateFirst && calls == 1 {
            return try await withCheckedThrowingContinuation {
                pending = $0; observer?.resume(); observer = nil
            }
        }
        return ResetCreditsSnapshot(availableCount: 2, credits: [], fetchedAt: Date())
    }
    func waitForFirst() async {
        guard pending == nil else { return }
        await withCheckedContinuation { observer = $0 }
    }
    func completeFirst() {
        pending?.resume(returning: ResetCreditsSnapshot(availableCount: 99, credits: [], fetchedAt: Date()))
        pending = nil
    }
}
