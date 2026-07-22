import CodexToolboxCore
import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let isDemoMode: Bool
    let updateManager: AppUpdateManager

    private let repository: RadarRepository
    private let radarScheduler: RefreshScheduler
    private let usageScheduler: RefreshScheduler
    private let resetCreditsScheduler: RefreshScheduler
    private let usageReader: any CodexUsageReading & UsageHistoryClearing
    private let resetCreditsReader: any AccountRateLimitsReading
    private let resetCreditsCache: ResetCreditsCacheStore
    private var didStart = false

    var repositoryState: RadarRepositoryState = .empty
    var isRefreshing = false
    var hasLoadedCache = false
    var usageHistory: UsageHistory?
    var taskQuotaEstimatesByDuration: [Int: [String: TaskQuotaEstimate]] = [:]
    var usageErrorMessage: String?
    var isRefreshingUsage = false
    var resetCreditsSnapshot: ResetCreditsSnapshot?
    var resetCreditsErrorMessage: String?
    var isRefreshingResetCredits = false

    init(
        settings: AppSettings = AppSettings(),
        repository: RadarRepository = RadarRepository(
            client: URLSessionRadarClient(),
            store: SnapshotStore()
        ),
        radarScheduler: RefreshScheduler = RefreshScheduler(),
        usageScheduler: RefreshScheduler = RefreshScheduler(),
        resetCreditsScheduler: RefreshScheduler = RefreshScheduler(),
        usageReader: any CodexUsageReading & UsageHistoryClearing = LocalCodexUsageReader(),
        resetCreditsReader: any AccountRateLimitsReading = ResetCreditsClient(),
        resetCreditsCache: ResetCreditsCacheStore = ResetCreditsCacheStore(),
        updateManager: AppUpdateManager = AppUpdateManager(),
        isDemoMode: Bool = false
    ) {
        self.settings = settings
        self.isDemoMode = isDemoMode
        self.repository = repository
        self.radarScheduler = radarScheduler
        self.usageScheduler = usageScheduler
        self.resetCreditsScheduler = resetCreditsScheduler
        self.usageReader = usageReader
        self.resetCreditsReader = resetCreditsReader
        self.resetCreditsCache = resetCreditsCache
        self.updateManager = updateManager
    }

    var snapshot: RadarSnapshot? { repositoryState.snapshot }
    var costHistory: [CostHistoryPoint] { repositoryState.costHistory }
    var isStale: Bool { repositoryState.isStale }
    var errorMessage: String? { repositoryState.errorMessage }
    var isInitialLoading: Bool { !hasLoadedCache && snapshot == nil }
    var isUsageInitialLoading: Bool { usageHistory == nil && isRefreshingUsage }
    var isResetCreditsInitialLoading: Bool {
        resetCreditsSnapshot == nil && isRefreshingResetCredits
    }

    var lastSuccessfulRefresh: Date? {
        snapshot?.fetchedAt
    }

    var latestBenchmarkDate: String? {
        snapshot?.benchmarks.compactMap(\.latest?.date).max()
    }

    var availableModels: [ModelBenchmark] {
        (snapshot?.benchmarks ?? []).sorted {
            $0.label.localizedStandardCompare($1.label) == .orderedAscending
        }
    }

    var menuBarRanking: [RankedModel] {
        rankings(for: settings.menuBarMetric).prefix(2).map { $0 }
    }

    func rankings(for metric: RankingMetric) -> [RankedModel] {
        RankingEngine.rank(
            snapshot?.benchmarks ?? [],
            by: metric,
            weights: settings.rankingWeights
        )
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        repositoryState = await repository.loadCached()
        resetCreditsSnapshot = try? await resetCreditsCache.load()
        hasLoadedCache = true
        await reconfigureSchedulers()
        Task { [weak self] in await self?.refreshIfNeeded() }
        Task { [weak self] in await self?.refreshUsageIfNeeded() }
        Task { [weak self] in await self?.refreshResetCreditsIfNeeded() }
        updateManager.start()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        repositoryState = await repository.refresh()
        isRefreshing = false
    }

    func refreshIfNeeded() async {
        let due = RefreshPolicy.isRefreshDue(
            lastSuccessfulRefresh: lastSuccessfulRefresh,
            now: Date(),
            interval: settings.refreshInterval
        )
        if due {
            await refresh()
        }
    }

    func refreshUsage() async {
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        defer { isRefreshingUsage = false }
        do {
            usageHistory = try await usageReader.readUsage(now: Date(), calendar: .current)
            recalculateTaskQuotaEstimates()
            usageErrorMessage = nil
        } catch {
            usageErrorMessage = error.localizedDescription
        }
    }

    func refreshUsageIfNeeded() async {
        let interval = TimeInterval(settings.usageRefreshInterval.rawValue * 60)
        guard usageHistory == nil
            || Date().timeIntervalSince(usageHistory?.generatedAt ?? .distantPast) >= interval else { return }
        await refreshUsage()
    }

    func clearUsageHistory() async {
        do {
            try await usageReader.clearHistory()
            usageHistory = nil
            taskQuotaEstimatesByDuration = [:]
            usageErrorMessage = nil
            await refreshUsage()
        } catch {
            usageErrorMessage = error.localizedDescription
        }
    }

    func refreshResetCredits() async {
        guard !isRefreshingResetCredits else { return }
        isRefreshingResetCredits = true
        defer { isRefreshingResetCredits = false }
        do {
            let snapshot = try await resetCreditsReader.readResetCredits()
            resetCreditsSnapshot = snapshot
            recalculateTaskQuotaEstimates()
            resetCreditsErrorMessage = nil
            try? await resetCreditsCache.save(snapshot)
        } catch {
            resetCreditsErrorMessage = error.localizedDescription
        }
    }

    func refreshResetCreditsIfNeeded() async {
        let interval = TimeInterval(settings.resetCreditsRefreshInterval.rawValue * 60)
        guard resetCreditsSnapshot == nil
            || resetCreditsSnapshot?.quotaWindows.isEmpty == true
            || Date().timeIntervalSince(resetCreditsSnapshot?.fetchedAt ?? .distantPast) >= interval else { return }
        await refreshResetCredits()
    }

    func refreshAllIfNeeded() async {
        async let radar: Void = refreshIfNeeded()
        async let usage: Void = refreshUsageIfNeeded()
        async let credits: Void = refreshResetCreditsIfNeeded()
        _ = await (radar, usage, credits)
    }

    func settingsDidChange() {
        Task { await reconfigureSchedulers() }
    }

    private func reconfigureSchedulers() async {
        let enabled = settings.automaticRefreshEnabled
        let interval = settings.refreshInterval
        await radarScheduler.configure(enabled: enabled, interval: interval) { [weak self] in
            await self?.refresh()
        }
        await usageScheduler.configure(
            enabled: true,
            everyMinutes: settings.usageRefreshInterval.rawValue
        ) { [weak self] in
            await self?.refreshUsage()
        }
        await resetCreditsScheduler.configure(
            enabled: true,
            everyMinutes: settings.resetCreditsRefreshInterval.rawValue
        ) { [weak self] in
            await self?.refreshResetCredits()
        }
    }

    private func recalculateTaskQuotaEstimates(now: Date = Date()) {
        guard let history = usageHistory else {
            taskQuotaEstimatesByDuration = [:]
            return
        }
        taskQuotaEstimatesByDuration = (resetCreditsSnapshot?.quotaWindows ?? []).reduce(
            into: [:]
        ) { result, window in
            guard now < window.resetsAt else { return }
            result[window.durationMinutes] = TaskQuotaEstimator.estimates(
                history: history,
                window: window,
                now: now
            )
        }
    }
}
