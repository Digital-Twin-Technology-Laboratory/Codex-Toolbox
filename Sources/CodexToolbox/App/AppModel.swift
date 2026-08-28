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
    private let stationRepository: StationRecommendationRepository
    private let rateCardRepository: RateCardRepository
    private let apiPriceCardRepository: APIPriceCardRepository
    private let radarScheduler: RefreshScheduler
    private let usageScheduler: RefreshScheduler
    private let resetCreditsScheduler: RefreshScheduler
    private let rateCardScheduler: RefreshScheduler
    private let activeQuotaScheduler: RefreshScheduler
    private let usageReader: any CodexUsageReading & UsageHistoryClearing & AccountQuotaSnapshotRecording
    private let resetCreditsReader: any AccountRateLimitsReading
    private let resetCreditsCache: ResetCreditsCacheStore
    private var didStart = false

    var repositoryState: RadarRepositoryState = .empty
    var stationRecommendationState: StationRecommendationRepositoryState = .empty
    var rateCardState: RateCardRepositoryState
    var apiPriceCardState: APIPriceCardRepositoryState
    var isRefreshing = false
    var isRefreshingStationRecommendations = false
    var isRefreshingRateCard = false
    var isRefreshingAPIPriceCard = false
    var hasLoadedCache = false
    var usageHistory: UsageHistory?
    var taskQuotaEstimatesByDuration: [Int: [String: TaskQuotaEstimate]] = [:]
    var usageErrorMessage: String?
    var isRefreshingUsage = false
    var resetCreditsSnapshot: ResetCreditsSnapshot?
    var resetCreditsErrorMessage: String?
    var isResetCreditsStale = false
    var isRefreshingResetCredits = false

    init(
        settings: AppSettings = AppSettings(),
        repository: RadarRepository = RadarRepository(
            client: URLSessionRadarClient(),
            store: SnapshotStore()
        ),
        stationRepository: StationRecommendationRepository = StationRecommendationRepository(),
        rateCardRepository: RateCardRepository? = nil,
        apiPriceCardRepository: APIPriceCardRepository? = nil,
        radarScheduler: RefreshScheduler = RefreshScheduler(),
        usageScheduler: RefreshScheduler = RefreshScheduler(),
        resetCreditsScheduler: RefreshScheduler = RefreshScheduler(),
        rateCardScheduler: RefreshScheduler = RefreshScheduler(),
        activeQuotaScheduler: RefreshScheduler = RefreshScheduler(),
        usageReader: any CodexUsageReading & UsageHistoryClearing & AccountQuotaSnapshotRecording = LocalCodexUsageReader(),
        resetCreditsReader: any AccountRateLimitsReading = ResetCreditsClient(),
        resetCreditsCache: ResetCreditsCacheStore = ResetCreditsCacheStore(),
        updateManager: AppUpdateManager = AppUpdateManager(),
        isDemoMode: Bool = false
    ) {
        self.settings = settings
        self.isDemoMode = isDemoMode
        self.repository = repository
        self.stationRepository = stationRepository
        let bundledRateCard = Self.loadBundledRateCard()
        let bundledAPIPriceCard = Self.loadBundledAPIPriceCard()
        self.rateCardRepository = rateCardRepository
            ?? RateCardRepository(bundledManifest: bundledRateCard)
        rateCardState = RateCardRepositoryState(
            manifest: bundledRateCard,
            source: .bundled,
            fetchedAt: nil,
            validators: CacheValidators(),
            errorMessage: nil
        )
        self.apiPriceCardRepository = apiPriceCardRepository
            ?? APIPriceCardRepository(bundledManifest: bundledAPIPriceCard)
        apiPriceCardState = APIPriceCardRepositoryState(
            manifest: bundledAPIPriceCard,
            source: .bundled,
            fetchedAt: nil,
            validators: CacheValidators(),
            errorMessage: nil
        )
        self.radarScheduler = radarScheduler
        self.usageScheduler = usageScheduler
        self.resetCreditsScheduler = resetCreditsScheduler
        self.rateCardScheduler = rateCardScheduler
        self.activeQuotaScheduler = activeQuotaScheduler
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
        snapshot?.sourceMonitoredAt
            ?? snapshot?.benchmarks.compactMap(\.latest?.date).max()
    }

    var stationRecommendations: StationRecommendationSnapshot? {
        stationRecommendationState.snapshot
    }

    var isRateCardStale: Bool { rateCardState.isStale(now: Date()) }
    var isAPIPriceCardStale: Bool { apiPriceCardState.isStale(now: Date()) }

    var availableModels: [ModelBenchmark] {
        ModelCatalog.sorted(snapshot?.benchmarks ?? [])
    }

    var visibleModels: [ModelBenchmark] {
        availableModels.filter(settings.isModelVisible)
    }

    var menuBarRanking: [RankedModel] {
        rankings(for: settings.menuBarMetric).prefix(2).map { $0 }
    }

    func rankings(for metric: RankingMetric) -> [RankedModel] {
        RankingEngine.rank(
            visibleModels,
            by: metric,
            weights: settings.rankingWeights,
            overallMode: settings.overallRankingMode
        )
    }

    func start() async {
        guard !didStart else { return }
        didStart = true
        repositoryState = await repository.loadCached()
        settings.migrateLegacyModelAliases(using: availableModels)
        rateCardState = await rateCardRepository.loadCached()
        apiPriceCardState = await apiPriceCardRepository.loadCached()
        if settings.showsStationRecommendations {
            stationRecommendationState = await stationRepository.loadCached()
        }
        resetCreditsSnapshot = try? await resetCreditsCache.load()
        isResetCreditsStale = resetCreditsSnapshot != nil
        hasLoadedCache = true
        await reconfigureSchedulers()
        Task { [weak self] in await self?.refreshIfNeeded() }
        Task { [weak self] in await self?.refreshUsageIfNeeded() }
        Task { [weak self] in await self?.refreshResetCreditsIfNeeded() }
        if settings.automaticRateCardUpdatesEnabled {
            Task { [weak self] in await self?.refreshRateCard() }
        }
        updateManager.start()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        if settings.showsStationRecommendations {
            async let radar = repository.refresh()
            async let station = stationRepository.refresh()
            repositoryState = await radar
            stationRecommendationState = await station
        } else {
            repositoryState = await repository.refresh()
        }
        settings.migrateLegacyModelAliases(using: availableModels)
        isRefreshing = false
    }

    func isModelVisible(model: String, reasoningEffort: String) -> Bool {
        settings.isModelVisible(
            ModelCatalog.entry(model: model, reasoningEffort: reasoningEffort)
        )
    }

    func refreshStationRecommendations() async {
        guard settings.showsStationRecommendations,
              !isRefreshingStationRecommendations else { return }
        isRefreshingStationRecommendations = true
        defer { isRefreshingStationRecommendations = false }
        stationRecommendationState = await stationRepository.refresh()
    }

    func refreshRateCard() async {
        guard !isRefreshingRateCard else { return }
        isRefreshingRateCard = true
        defer { isRefreshingRateCard = false }
        isRefreshingAPIPriceCard = true
        async let creditCard = rateCardRepository.refresh()
        async let priceCard = apiPriceCardRepository.refresh()
        rateCardState = await creditCard
        apiPriceCardState = await priceCard
        isRefreshingAPIPriceCard = false
        await refreshUsage()
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
            usageHistory = try await usageReader.readUsage(
                now: Date(),
                calendar: .current,
                rateCard: rateCardState.manifest,
                rateCardMode: settings.rateCardMode,
                apiPriceCard: apiPriceCardState.manifest
            )
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
            try? await usageReader.recordAccountQuotaSnapshot(
                windows: snapshot.quotaWindows,
                planType: snapshot.planType,
                timestamp: snapshot.fetchedAt
            )
            usageHistory = usageHistory?.appendingAccountSnapshot(
                timestamp: snapshot.fetchedAt,
                planType: snapshot.planType,
                windows: snapshot.quotaWindows
            )
            recalculateTaskQuotaEstimates()
            isResetCreditsStale = false
            resetCreditsErrorMessage = nil
            try? await resetCreditsCache.save(snapshot)
        } catch {
            if let resetError = error as? ResetCreditsError,
               resetError.isTransient,
               resetCreditsSnapshot != nil {
                isResetCreditsStale = true
                resetCreditsErrorMessage = nil
            } else {
                resetCreditsErrorMessage = error.localizedDescription
            }
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

    func suspendBackgroundWork() async {
        updateManager.setApplicationAwake(false)
        async let radar: Void = radarScheduler.stop()
        async let usage: Void = usageScheduler.stop()
        async let credits: Void = resetCreditsScheduler.stop()
        async let rates: Void = rateCardScheduler.stop()
        async let quota: Void = activeQuotaScheduler.stop()
        _ = await (radar, usage, credits, rates, quota)
    }

    func resumeBackgroundWork() async {
        updateManager.setApplicationAwake(true)
        await reconfigureSchedulers()
        await refreshAllIfNeeded()
    }

    func settingsDidChange() {
        Task {
            await reconfigureSchedulers()
            if settings.showsStationRecommendations,
               stationRecommendationState.snapshot == nil {
                stationRecommendationState = await stationRepository.loadCached()
                await refreshStationRecommendations()
            }
            await refreshUsage()
        }
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
        await rateCardScheduler.configure(
            enabled: settings.automaticRateCardUpdatesEnabled,
            everyMinutes: 360
        ) { [weak self] in
            await self?.refreshRateCard()
        }
        await activeQuotaScheduler.configure(enabled: true, everyMinutes: 1) { [weak self] in
            await self?.sampleActiveAccountQuotaIfNeeded()
        }
    }

    private func sampleActiveAccountQuotaIfNeeded(now: Date = Date()) async {
        guard let lastActivity = usageHistory?.lastLocalActivityAt,
              now.timeIntervalSince(lastActivity) >= 0,
              now.timeIntervalSince(lastActivity) <= 15 * 60 else { return }
        await refreshResetCredits()
    }

    private static func loadBundledRateCard() -> RateCardManifest {
        guard let url = Bundle.main.url(
            forResource: "codex-rate-card-v1",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url),
        let manifest = try? JSONDecoder().decode(RateCardManifest.self, from: data),
        let validated = try? manifest.validated() else {
            preconditionFailure("缺少或无法读取内置 Codex 费率清单。")
        }
        return validated
    }

    private static func loadBundledAPIPriceCard() -> APIPriceManifest {
        guard let url = Bundle.main.url(
            forResource: "api-price-card-v1",
            withExtension: "json"
        ),
        let data = try? Data(contentsOf: url),
        let manifest = try? JSONDecoder().decode(APIPriceManifest.self, from: data),
        let validated = try? manifest.validated() else {
            preconditionFailure("缺少或无法读取内置 API 价格清单。")
        }
        return validated
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
