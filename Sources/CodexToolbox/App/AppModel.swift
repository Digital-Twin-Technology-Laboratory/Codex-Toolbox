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
    private let identityRepository: AccountIdentityRepository
    private let nativeTaskQuotaStore: NativeTaskQuotaStore
    private let nativeTaskQuotaScheduler = RefreshScheduler()
    private var nativeQuotaSnapshots: [NativeTaskQuotaSnapshot] = []
    private var nativeContinuityID = UUID().uuidString
    private var nativeDayBoundaryTask: Task<Void, Never>?
    private var nativePriorityTaskIDs: Set<String> = []
    private var lastNativeQuotaRefreshAt: Date?
    private var isBackgroundSuspended = false
    private var lifecycleRevision = UUID()
    private var publicDataGeneration: UInt64 = 0
    private var radarRefreshGeneration: UInt64?
    private var stationRefreshGeneration: UInt64?
    private var rateRefreshGeneration: UInt64?
    private var schedulerRevision: UInt64 = 0
    private var historyRevision = UUID()
    private var historyEpoch = UUID()
    private var quotaRevision = UUID()
    private var quotaCalculationDebounceTask: Task<Void, Never>?
    private var priceRevision = UUID()
    private var lastUsageCostSettings: CostSettings?
    private var lastUsagePriceRevision: UUID?
    private var usageRefreshRequested = false
    private var usageRequestTask: Task<UsageHistory, Error>?
    private var resetCreditsRequestTask: Task<ResetCreditsSnapshot, Error>?
    private var settingsChangeTask: Task<Void, Never>?
    private var lastRefreshSettings: RefreshSettings?
    private var pendingRefreshSettings: RefreshSettings?
    private var nativeIncludesRecentTasks = false
    private var nativeFetchedAt: [String: Date] = [:]
    private var nativeRequestTask: Task<NativeTaskUsageReport, Error>?
    private let quotaWorker = LatestValueWorker<QuotaComputationInput, QuotaComputationOutput> {
        try QuotaComputationOutput.calculate($0)
    }
    var usagePresentation: UsagePresentation?
    private(set) var isDashboardVisible = false
    var isRefreshingNativeTaskQuota = false
    var nativeTaskQuotaError: String?
    var dailyTaskQuotas: [Int: [String: DailyTaskQuotaValue]] = [:]
    private var identityRefreshTask: Task<AccountAuthentication, Never>?
    private var identityRefreshID: UUID?
    private var accountSession = AccountSession()
    var isAPIAuthentication: Bool { accountSession.authentication == .api }
    var hasChatGPTQuotaAccount: Bool { accountSession.ticket != nil }
    var accountAvailabilityMessage: String {
        switch accountSession.authentication {
        case .api: "当前使用 API 登录，不适用 ChatGPT 套餐额度与重置卡；本机用量仍可查看。"
        case .signedOut: "请在 Codex 中登录 ChatGPT 账户后刷新；本机用量仍可查看。"
        case .unknown: "暂时无法确认账户身份；本机用量仍可查看。"
        case .chatGPT: "账户额度暂不可用，请稍后刷新。"
        }
    }
    private var didStart = false

    private(set) var radarContentRevision = UUID()
    var repositoryState: RadarRepositoryState = .empty { didSet { radarContentRevision = UUID() } }
    var stationRecommendationState: StationRecommendationRepositoryState = .empty
    var rateCardState: RateCardRepositoryState
    var apiPriceCardState: APIPriceCardRepositoryState
    let radarRefreshFeedback = RadarRefreshFeedback()
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
        identityRepository: AccountIdentityRepository = AccountIdentityRepository(),
        nativeTaskQuotaStore: NativeTaskQuotaStore = NativeTaskQuotaStore(),
        bundledRateCard: RateCardManifest? = nil,
        bundledAPIPriceCard: APIPriceManifest? = nil,
        isDemoMode: Bool = false
    ) {
        self.settings = settings
        self.isDemoMode = isDemoMode
        self.repository = repository
        self.stationRepository = stationRepository
        let bundledRateCard = bundledRateCard ?? Self.loadBundledRateCard()
        let bundledAPIPriceCard = bundledAPIPriceCard ?? Self.loadBundledAPIPriceCard()
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
        self.identityRepository = identityRepository
        self.nativeTaskQuotaStore = nativeTaskQuotaStore
        lastRefreshSettings = RefreshSettings(settings)
    }

    var todayUsage: DailyUsageSummary? {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return usageSummary(for: key)
    }

    func usageSummary(for dateKey: String) -> DailyUsageSummary? { usagePresentation?.summariesByDay[dateKey] }

    var snapshot: RadarSnapshot? { repositoryState.snapshot }
    var costHistory: [CostHistoryPoint] { repositoryState.costHistory }
    var isStale: Bool {
        repositoryState.isStale
            || (snapshot?.sourceMonitoredAt.flatMap(MetricFormatter.sourceDate).map { Date().timeIntervalSince($0) > 24 * 3600 } ?? false)
            || ((snapshot?.managed?.checkedAt).flatMap(MetricFormatter.sourceDate).map { Date().timeIntervalSince($0) > 6.5 * 3600 } ?? false)
    }
    var errorMessage: String? { repositoryState.errorMessage }
    var radarScoreLabel: String { snapshot?.managed?.dataset.scoreLabel ?? "Radar IQ" }
    var radarStatusLabel: String {
        if repositoryState.refreshFailed {
            return snapshot?.benchmarks.isEmpty == false ? "刷新失败 · 本地缓存" : "连接异常 · 暂无成绩"
        }
        if isStale && snapshot?.managed?.status == "current" { return "历史数据" }
        return snapshot?.managed?.statusLabel ?? (snapshot == nil ? "暂无成绩" : "历史数据")
    }
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
        // Legacy quota caches have no account binding; validate identity before loading.
        await checkAccountIdentity()
        hasLoadedCache = true
        await reconfigureSchedulers()
        Task { [weak self] in await self?.refreshIfNeeded() }
        Task { [weak self] in await self?.refreshUsageIfNeeded() }
        Task { [weak self] in await self?.refreshResetCreditsIfNeeded() }
        if settings.experimentalLocalCostEstimatesEnabled && settings.automaticRateCardUpdatesEnabled {
            Task { [weak self] in await self?.refreshRateCard() }
        }
        updateManager.start()
    }

    func refresh(manualFeedback: Bool = false) async {
        guard !isBackgroundSuspended, !isRefreshing || radarRefreshGeneration != publicDataGeneration else { return }
        let feedbackID = radarRefreshFeedback.begin(manual: manualFeedback)
        let previous = repositoryState.snapshot
        isRefreshing = true
        let lifecycle = lifecycleRevision
        let generation = publicDataGeneration
        radarRefreshGeneration = generation
        defer { if radarRefreshGeneration == generation { isRefreshing = false } }
        async let station: Void = refreshStationRecommendations()
        let refreshed = await repository.refresh(generation: generation)
        guard !isBackgroundSuspended, lifecycle == lifecycleRevision, !Task.isCancelled,
              radarRefreshGeneration == generation else { return }
        repositoryState = refreshed
        settings.migrateLegacyModelAliases(using: availableModels)
        radarRefreshFeedback.finish(feedbackID, result: .comparing(previous: previous, current: repositoryState))
        await station
    }

    func isModelVisible(model: String, reasoningEffort: String) -> Bool {
        settings.isModelVisible(
            ModelCatalog.entry(model: model, reasoningEffort: reasoningEffort)
        )
    }

    func refreshStationRecommendations() async {
        guard !isBackgroundSuspended, settings.showsStationRecommendations,
              !isRefreshingStationRecommendations || stationRefreshGeneration != publicDataGeneration else { return }
        isRefreshingStationRecommendations = true
        let lifecycle = lifecycleRevision
        let generation = publicDataGeneration
        stationRefreshGeneration = generation
        defer { if stationRefreshGeneration == generation { isRefreshingStationRecommendations = false } }
        let refreshed = await stationRepository.refresh(generation: generation)
        guard !isBackgroundSuspended, lifecycle == lifecycleRevision, !Task.isCancelled,
              stationRefreshGeneration == generation else { return }
        stationRecommendationState = refreshed
    }

    func refreshRateCard() async {
        guard !isBackgroundSuspended, settings.experimentalLocalCostEstimatesEnabled,
              !isRefreshingRateCard || rateRefreshGeneration != publicDataGeneration else { return }
        isRefreshingRateCard = true
        let lifecycle = lifecycleRevision
        let generation = publicDataGeneration
        rateRefreshGeneration = generation
        defer {
            if rateRefreshGeneration == generation {
                isRefreshingRateCard = false
                isRefreshingAPIPriceCard = false
            }
        }
        isRefreshingAPIPriceCard = true
        async let creditCard = rateCardRepository.refresh(generation: generation)
        async let priceCard = apiPriceCardRepository.refresh(generation: generation)
        let rates = await creditCard
        let prices = await priceCard
        guard !isBackgroundSuspended, lifecycle == lifecycleRevision, !Task.isCancelled,
              rateRefreshGeneration == generation, publicDataGeneration == generation,
              settings.experimentalLocalCostEstimatesEnabled else { return }
        rateCardState = rates
        apiPriceCardState = prices
        priceRevision = UUID()
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
        guard !isBackgroundSuspended else { return }
        usageRefreshRequested = true
        guard !isRefreshingUsage else { return }
        isRefreshingUsage = true
        defer {
            usageRequestTask = nil
            isRefreshingUsage = false
            if usageRefreshRequested && !isBackgroundSuspended {
                Task { [weak self] in await self?.refreshUsage() }
            }
        }
        repeat {
            usageRefreshRequested = false
            let lifecycle = lifecycleRevision
            let epoch = historyEpoch
            let costSettings = CostSettings(settings)
            let prices = priceRevision
            let calendar = Calendar.current
            let now = Date()
            let reader = usageReader
            let rateCard = costSettings.enabled ? rateCardState.manifest : nil
            let apiPriceCard = costSettings.enabled ? apiPriceCardState.manifest : nil
            let request = Task {
                try await reader.readUsage(now: now, calendar: calendar, rateCard: rateCard,
                    rateCardMode: costSettings.mode, apiPriceCard: apiPriceCard)
            }
            usageRequestTask = request
            do {
                let refreshed = try await withTaskCancellationHandler {
                    try await request.value
                } onCancel: { request.cancel() }
                try Task.checkCancellation()
                guard !isBackgroundSuspended, lifecycleRevision == lifecycle, historyEpoch == epoch else { return }
                guard costSettings == CostSettings(settings), prices == priceRevision,
                      calendar.timeZone.identifier == Calendar.current.timeZone.identifier else {
                    usageRefreshRequested = true
                    continue
                }
                let presentation = try await BackgroundWork.run {
                    try UsagePresentation.prepare(history: refreshed, now: now, calendar: calendar)
                }
                guard !isBackgroundSuspended, lifecycleRevision == lifecycle, historyEpoch == epoch else { return }
                guard costSettings == CostSettings(settings), prices == priceRevision,
                      calendar.timeZone.identifier == Calendar.current.timeZone.identifier,
                      presentation.calendarDay == Calendar.current.startOfDay(for: Date()) else {
                    usageRefreshRequested = true
                    continue
                }
                usageHistory = refreshed
                usagePresentation = presentation
                lastUsageCostSettings = costSettings
                lastUsagePriceRevision = prices
                historyRevision = UUID()
                recalculateTaskQuotaEstimates()
                usageErrorMessage = nil
                Task { [weak self] in await self?.refreshNativeTaskQuota() }
            } catch is CancellationError {
                return
            } catch {
                guard !isBackgroundSuspended, lifecycleRevision == lifecycle, historyEpoch == epoch,
                      costSettings == CostSettings(settings), prices == priceRevision else { return }
                usageErrorMessage = error.localizedDescription
            }
        } while usageRefreshRequested && !Task.isCancelled && !isBackgroundSuspended
    }

    func refreshUsageIfNeeded() async {
        guard !isRefreshingUsage else { return }
        let interval = TimeInterval(settings.usageRefreshInterval.rawValue * 60)
        let calendar = Calendar.current
        guard usageHistory == nil
            || lastUsageCostSettings != CostSettings(settings)
            || lastUsagePriceRevision != priceRevision
            || usagePresentation?.calendarDay != calendar.startOfDay(for: Date())
            || usagePresentation?.timezoneIdentifier != calendar.timeZone.identifier
            || Date().timeIntervalSince(usageHistory?.generatedAt ?? .distantPast) >= interval else { return }
        await refreshUsage()
    }

    func clearUsageHistory() async {
        historyEpoch = UUID()
        usageRequestTask?.cancel()
        quotaCalculationDebounceTask?.cancel()
        quotaWorker.cancel()
        do {
            try await usageReader.clearHistory()
            usageHistory = nil
            usagePresentation = nil
            historyRevision = UUID()
            quotaWorker.cancel()
            dailyTaskQuotas = [:]
            taskQuotaEstimatesByDuration = [:]
            usageErrorMessage = nil
            await refreshUsage()
        } catch {
            usageErrorMessage = error.localizedDescription
        }
    }

    func checkAccountIdentity() async {
        guard !isBackgroundSuspended else { return }
        let lifecycle = lifecycleRevision
        let task: Task<AccountAuthentication, Never>
        let id: UUID
        if let pending = identityRefreshTask, let pendingID = identityRefreshID { task = pending; id = pendingID }
        else {
            task = Task { [identityRepository, isDemoMode] in
                if isDemoMode { return .chatGPT(accountKey: String(repeating: "d", count: 64)) }
                return (try? await identityRepository.authentication()) ?? .unknown
            }
            id = UUID()
            identityRefreshID = id
            identityRefreshTask = task
        }
        let authentication = await task.value
        guard identityRefreshID == id, !isBackgroundSuspended, lifecycle == lifecycleRevision else { return }
        identityRefreshID = nil
        identityRefreshTask = nil
        guard accountSession.observe(authentication) else { return }
        quotaWorker.cancel()
        quotaRevision = UUID()
        nativeFetchedAt = [:]
        resetCreditsSnapshot = nil
        resetCreditsErrorMessage = nil
        taskQuotaEstimatesByDuration = [:]
        dailyTaskQuotas = [:]
        nativeQuotaSnapshots = []
        nativeContinuityID = UUID().uuidString
        lastNativeQuotaRefreshAt = nil
        nativeTaskQuotaError = nil
        isResetCreditsStale = false
        if let ticket = accountSession.ticket {
            let cached = try? await resetCreditsCache.load(accountKey: ticket.accountKey)
            guard !isBackgroundSuspended, lifecycle == lifecycleRevision, accountSession.accepts(ticket) else { return }
            resetCreditsSnapshot = cached
            isResetCreditsStale = cached != nil
            let snapshots = try? await nativeTaskQuotaStore.snapshots(accountKey: ticket.accountKey)
            guard !isBackgroundSuspended, lifecycle == lifecycleRevision, accountSession.accepts(ticket) else { return }
            nativeQuotaSnapshots = snapshots ?? []
            recalculateTaskQuotaEstimates()
        }
    }

    func refreshResetCredits() async {
        guard !isBackgroundSuspended, !isRefreshingResetCredits else { return }
        isRefreshingResetCredits = true
        let lifecycle = lifecycleRevision
        var retryForNewAccount = false
        defer {
            isRefreshingResetCredits = false
            resetCreditsRequestTask = nil
            if retryForNewAccount, !isBackgroundSuspended, accountSession.ticket != nil {
                Task { [weak self] in await self?.refreshResetCredits() }
            }
        }
        await checkAccountIdentity()
        guard !isBackgroundSuspended, lifecycle == lifecycleRevision, let ticket = accountSession.ticket else { return }
        do {
            let reader = resetCreditsReader
            let request = Task { try await reader.readResetCredits() }
            resetCreditsRequestTask = request
            let refreshedSnapshot = try await withTaskCancellationHandler {
                try await request.value
            } onCancel: { request.cancel() }
            guard !Task.isCancelled, !isBackgroundSuspended, lifecycle == lifecycleRevision else { return }
            await checkAccountIdentity()
            guard !isBackgroundSuspended, lifecycle == lifecycleRevision else { return }
            guard accountSession.accepts(ticket) else { retryForNewAccount = true; return }
            let preservedCreditDetails = refreshedSnapshot.shouldPreserveCreditDetails(from: resetCreditsSnapshot)
            let snapshot = refreshedSnapshot.preservingCreditDetails(from: resetCreditsSnapshot)
            resetCreditsSnapshot = snapshot
            isResetCreditsStale = preservedCreditDetails
            resetCreditsErrorMessage = nil
            try? await resetCreditsCache.save(snapshot, accountKey: ticket.accountKey)
            guard !isBackgroundSuspended, lifecycle == lifecycleRevision, accountSession.accepts(ticket) else { return }
            try? await usageReader.recordAccountQuotaSnapshot(
                windows: snapshot.quotaWindows, planType: snapshot.planType,
                timestamp: snapshot.fetchedAt, accountKey: ticket.accountKey
            )
            guard !isBackgroundSuspended, lifecycle == lifecycleRevision else { return }
            guard accountSession.accepts(ticket) else { retryForNewAccount = true; return }
            if let history = usageHistory {
                let revision = historyRevision
                let updated = try await BackgroundWork.run {
                    history.appendingAccountSnapshot(timestamp: snapshot.fetchedAt, planType: snapshot.planType,
                        windows: snapshot.quotaWindows, accountKey: ticket.accountKey)
                }
                guard !isBackgroundSuspended, lifecycle == lifecycleRevision, accountSession.accepts(ticket) else { return }
                if revision == historyRevision {
                    usageHistory = updated
                    historyRevision = UUID()
                } else {
                    await refreshUsage()
                }
            }
            recalculateTaskQuotaEstimates()
        } catch is CancellationError {
            return
        } catch {
            guard !isBackgroundSuspended, lifecycle == lifecycleRevision else { return }
            await checkAccountIdentity()
            guard !isBackgroundSuspended, lifecycle == lifecycleRevision else { return }
            guard accountSession.accepts(ticket) else { retryForNewAccount = true; return }
            if let resetError = error as? ResetCreditsError, resetError.isTransient, resetCreditsSnapshot != nil {
                isResetCreditsStale = true
                resetCreditsErrorMessage = nil
            } else { resetCreditsErrorMessage = error.localizedDescription }
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
        await checkAccountIdentity()
        async let radar: Void = refreshIfNeeded()
        async let usage: Void = refreshUsageIfNeeded()
        async let credits: Void = refreshResetCreditsIfNeeded()
        _ = await (radar, usage, credits)
        await refreshNativeTaskQuota()
    }

    func suspendBackgroundWork() async {
        isBackgroundSuspended = true
        lifecycleRevision = UUID()
        publicDataGeneration &+= 1
        let publicGeneration = publicDataGeneration
        schedulerRevision &+= 1
        let scheduling = schedulerRevision
        quotaRevision = UUID()
        quotaWorker.cancel()
        quotaCalculationDebounceTask?.cancel()
        usageRefreshRequested = false
        usageRequestTask?.cancel()
        resetCreditsRequestTask?.cancel()
        identityRefreshTask?.cancel()
        identityRefreshTask = nil
        identityRefreshID = nil
        nativeRequestTask?.cancel()
        settingsChangeTask?.cancel()
        nativeContinuityID = UUID().uuidString
        nativeDayBoundaryTask?.cancel()
        updateManager.setApplicationAwake(false)
        async let radar: Void = radarScheduler.stop(generation: scheduling)
        async let usage: Void = usageScheduler.stop(generation: scheduling)
        async let credits: Void = resetCreditsScheduler.stop(generation: scheduling)
        async let rates: Void = rateCardScheduler.stop(generation: scheduling)
        async let quota: Void = activeQuotaScheduler.stop(generation: scheduling)
        async let native: Void = nativeTaskQuotaScheduler.stop(generation: scheduling)
        async let radarRequest: Void = repository.cancelRefresh(generation: publicGeneration)
        async let stationRequest: Void = stationRepository.cancelRefresh(generation: publicGeneration)
        async let creditRateRequest: Void = rateCardRepository.cancelRefresh(generation: publicGeneration)
        async let apiPriceRequest: Void = apiPriceCardRepository.cancelRefresh(generation: publicGeneration)
        _ = await (radar, usage, credits, rates, quota, native,
                   radarRequest, stationRequest, creditRateRequest, apiPriceRequest)
    }

    func resumeBackgroundWork() async {
        isBackgroundSuspended = false
        lifecycleRevision = UUID()
        publicDataGeneration &+= 1
        let lifecycle = lifecycleRevision
        updateManager.setApplicationAwake(true)
        await reconfigureSchedulers()
        guard !isBackgroundSuspended, lifecycle == lifecycleRevision, !Task.isCancelled else { return }
        settingsDidChange()
        async let refresh: Void = refreshAllIfNeeded()
        async let native: Void = refreshNativeTaskQuota(force: true)
        _ = await (refresh, native)
        guard !isBackgroundSuspended, lifecycle == lifecycleRevision, !Task.isCancelled else { return }
        recalculateTaskQuotaEstimates()
    }

    func settingsDidChange() {
        let previous = lastRefreshSettings
        let current = RefreshSettings(settings)
        let hadPendingChange = settingsChangeTask != nil
        let priorRequested = pendingRefreshSettings ?? previous
        let pricePolicyChanged = priorRequested?.cost.enabled != current.cost.enabled || priorRequested?.automaticRates != current.automaticRates
        let resumesInterruptedRates = hadPendingChange && (priorRequested?.cost.enabled == false || priorRequested?.automaticRates == false)
        settingsChangeTask?.cancel()
        guard previous != current || hadPendingChange else { return }
        if pricePolicyChanged { publicDataGeneration &+= 1 }
        let publicGeneration = publicDataGeneration
        pendingRefreshSettings = current
        settingsChangeTask = Task { [weak self] in
            guard let self else { return }
            if !current.cost.enabled {
                async let rates: Void = rateCardRepository.cancelRefresh(generation: publicGeneration)
                async let prices: Void = apiPriceCardRepository.cancelRefresh(generation: publicGeneration)
                _ = await (rates, prices)
            }
            guard !Task.isCancelled, !isBackgroundSuspended else { return }
            await reconfigureSchedulers()
            guard !Task.isCancelled, !isBackgroundSuspended else { return }
            if current.showsRecommendations && previous?.showsRecommendations != true {
                let cached = await stationRepository.loadCached()
                guard !Task.isCancelled, !isBackgroundSuspended else { return }
                stationRecommendationState = cached
                await refreshStationRecommendations()
            }
            guard !Task.isCancelled, !isBackgroundSuspended else { return }
            if previous?.cost != current.cost {
                await refreshUsage()
            }
            if current.cost.enabled && current.automaticRates,
               previous?.cost.enabled != true || previous?.automaticRates != true || resumesInterruptedRates {
                await refreshRateCard()
            }
            guard !Task.isCancelled, !isBackgroundSuspended else { return }
            lastRefreshSettings = current
            pendingRefreshSettings = nil
            settingsChangeTask = nil
        }
    }

    private func reconfigureSchedulers() async {
        schedulerRevision &+= 1
        let revision = schedulerRevision
        guard !isBackgroundSuspended else { return }
        let enabled = settings.automaticRefreshEnabled
        let interval = settings.refreshInterval
        await radarScheduler.configureIfChanged(enabled: enabled, interval: interval, generation: revision) { [weak self] in
            await self?.refresh()
        }
        guard !isBackgroundSuspended, schedulerRevision == revision else { return }
        await usageScheduler.configureIfChanged(
            enabled: true,
            everyMinutes: settings.usageRefreshInterval.rawValue,
            generation: revision
        ) { [weak self] in
            await self?.refreshUsage()
        }
        guard !isBackgroundSuspended, schedulerRevision == revision else { return }
        await resetCreditsScheduler.configureIfChanged(
            enabled: true,
            everyMinutes: settings.resetCreditsRefreshInterval.rawValue,
            generation: revision
        ) { [weak self] in
            await self?.refreshResetCredits()
        }
        guard !isBackgroundSuspended, schedulerRevision == revision else { return }
        await rateCardScheduler.configureIfChanged(
            enabled: settings.experimentalLocalCostEstimatesEnabled && settings.automaticRateCardUpdatesEnabled,
            everyMinutes: 360,
            generation: revision
        ) { [weak self] in
            await self?.refreshRateCard()
        }
        guard !isBackgroundSuspended, schedulerRevision == revision else { return }
        await activeQuotaScheduler.configureIfChanged(enabled: true, everyMinutes: 1, generation: revision) { [weak self] in
            await self?.checkAccountIdentity()
            await self?.sampleActiveAccountQuotaIfNeeded()
        }
        guard !isBackgroundSuspended, schedulerRevision == revision else { return }
        await nativeTaskQuotaScheduler.configureIfChanged(enabled: true, everyMinutes: 5, generation: revision) { [weak self] in
            await self?.refreshNativeTaskQuota(force: true)
        }
        guard !isBackgroundSuspended, schedulerRevision == revision else { return }
        scheduleNativeQuotaDayBoundary()
    }

    private func scheduleNativeQuotaDayBoundary() {
        nativeDayBoundaryTask?.cancel()
        guard !isBackgroundSuspended,
              let next = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())) else { return }
        nativeDayBoundaryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow))) } catch { return }
            guard !Task.isCancelled, let self else { return }
            await refreshUsage()
            await refreshNativeTaskQuota(force: true)
            scheduleNativeQuotaDayBoundary()
        }
    }

    func setDashboardVisible(_ visible: Bool) {
        isDashboardVisible = visible
    }

    func prioritizeNativeQuotaTasks(_ rootIDs: Set<String>, refresh: Bool = true) {
        guard nativePriorityTaskIDs != rootIDs else { return }
        nativePriorityTaskIDs = rootIDs
        if refresh && isDashboardVisible {
            Task { [weak self] in await self?.refreshNativeTaskQuota(priorityOnly: true) }
        }
    }

    func refreshNativeTaskQuota(force: Bool = false, priorityOnly: Bool = false) async {
        guard !isBackgroundSuspended, !isDemoMode,
              priorityOnly || force || lastNativeQuotaRefreshAt.map({ Date().timeIntervalSince($0) >= 300 }) != false,
              let catalogueReader = usageReader as? any NativeThreadReading else { return }
        if isRefreshingNativeTaskQuota {
            if !priorityOnly { nativeIncludesRecentTasks = true }
            return
        }
        isRefreshingNativeTaskQuota = true
        nativeIncludesRecentTasks = !priorityOnly
        let lifecycle = lifecycleRevision
        var retry = false
        var changed = false
        var hasSubmittedVisibleBatch = false
        defer {
            nativeRequestTask = nil
            isRefreshingNativeTaskQuota = false
            if changed && !isBackgroundSuspended { recalculateTaskQuotaEstimates() }
            if !isBackgroundSuspended && retry {
                Task { [weak self] in await self?.refreshNativeTaskQuota(force: true) }
            }
        }
        await checkAccountIdentity()
        guard !isBackgroundSuspended, lifecycle == lifecycleRevision, !Task.isCancelled,
              let ticket = accountSession.ticket else { return }
        let continuity = nativeContinuityID
        do {
            let now = Date()
            let catalogueHistoryRevision = historyRevision
            let catalogue = try await catalogueReader.nativeCatalogue(now: now)
            let calendar = Calendar.current
            let history = usageHistory
            let priorFetched = nativeFetchedAt
            let prepared = try await BackgroundWork.run {
                var threads: [String: NativeThread] = [:]
                for thread in catalogue.threads {
                    try Task.checkCancellation()
                    threads[thread.id] = thread
                }
                let since = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: now)) ?? now
                let parts = calendar.dateComponents([.year, .month, .day], from: since)
                let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
                let recent = Set(history?.days.filter { $0.dateKey >= key }.flatMap { $0.tasks.map(\.rootTaskID) } ?? [])
                let fetched = priorFetched.filter { threads[$0.key] != nil && now.timeIntervalSince($0.value) >= 0 && now.timeIntervalSince($0.value) < 300 }
                return (threads, recent, fetched)
            }
            guard accountSession.accepts(ticket), continuity == nativeContinuityID,
                  lifecycle == lifecycleRevision, !isBackgroundSuspended else { retry = true; return }
            nativeFetchedAt = prepared.2
            var completed: Set<String> = []
            while true {
                try Task.checkCancellation()
                guard accountSession.accepts(ticket), continuity == nativeContinuityID,
                      lifecycle == lifecycleRevision, !isBackgroundSuspended else { retry = true; return }
                let priorities = nativePriorityTaskIDs
                let includesRecent = nativeIncludesRecentTasks
                let roots = priorities.union(includesRecent ? prepared.1 : [])
                let fetched = nativeFetchedAt
                let completedIDs = completed
                let batch = try await BackgroundWork.run {
                    let candidates = roots.subtracting(completedIDs).compactMap { id -> NativeThread? in
                        if !includesRecent, let last = fetched[id], now.timeIntervalSince(last) >= 0,
                           now.timeIntervalSince(last) < 300 { return nil }
                        return prepared.0[id]
                    }.sorted {
                        if priorities.contains($0.id) != priorities.contains($1.id) { return priorities.contains($0.id) }
                        return $0.id < $1.id
                    }
                    return DailyTaskQuotaAnalyzer.batches(candidates).first ?? []
                }
                guard accountSession.accepts(ticket), continuity == nativeContinuityID,
                      lifecycle == lifecycleRevision, !isBackgroundSuspended else { retry = true; return }
                if priorities != nativePriorityTaskIDs { continue }
                guard !batch.isEmpty else { break }
                let repository = identityRepository
                let request = Task { try await repository.taskUsage(threads: batch) }
                nativeRequestTask = request
                let report = try await withTaskCancellationHandler {
                    try await request.value
                } onCancel: { request.cancel() }
                await checkAccountIdentity()
                guard accountSession.accepts(ticket), continuity == nativeContinuityID,
                      lifecycle == lifecycleRevision, !isBackgroundSuspended else { retry = true; return }
                guard report.accountKey == ticket.accountKey else { throw NativeAnalyticsError.invalidResponse }
                let timezone = usageHistory?.timezoneIdentifier ?? Calendar.current.timeZone.identifier
                let additions = try await BackgroundWork.run {
                    let requested = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0) })
                    guard report.threads.allSatisfy({ requested[$0.id] != nil }),
                          let collected = MetricFormatter.sourceDate(report.collectedAt) else { throw NativeAnalyticsError.invalidResponse }
                    return report.threads.compactMap { row -> NativeTaskQuotaSnapshot? in
                        guard let thread = requested[row.id] else { return nil }
                        return NativeTaskQuotaSnapshot(accountKey: ticket.accountKey, thread: thread, row: row,
                            collectedAt: collected, dataAsOf: report.dataAsOf.flatMap(MetricFormatter.sourceDate),
                            planType: report.planType, timezoneIdentifier: timezone, continuityID: continuity)
                    }
                }
                try Task.checkCancellation()
                guard accountSession.accepts(ticket), continuity == nativeContinuityID,
                      lifecycle == lifecycleRevision, !isBackgroundSuspended else { retry = true; return }
                let snapshots = try await nativeTaskQuotaStore.append(additions, now: Date(), accountKey: ticket.accountKey)
                guard accountSession.accepts(ticket), continuity == nativeContinuityID,
                      lifecycle == lifecycleRevision, !isBackgroundSuspended else { retry = true; return }
                nativeQuotaSnapshots = snapshots
                changed = true
                quotaRevision = UUID()
                quotaWorker.cancel()
                if isDashboardVisible {
                    let visibleBatch = batch.contains { nativePriorityTaskIDs.contains($0.id) }
                    scheduleQuotaComputation(immediate: visibleBatch && !hasSubmittedVisibleBatch)
                    hasSubmittedVisibleBatch = hasSubmittedVisibleBatch || visibleBatch
                }
                let fetchedAt = Date()
                for thread in batch { completed.insert(thread.id); nativeFetchedAt[thread.id] = fetchedAt }
            }
            if catalogueHistoryRevision != historyRevision,
               nativePriorityTaskIDs.contains(where: { prepared.0[$0] == nil }) {
                retry = true
            }
            if nativeIncludesRecentTasks { lastNativeQuotaRefreshAt = Date() }
            nativeTaskQuotaError = nil
        } catch is CancellationError {
            retry = !isBackgroundSuspended && lifecycle != lifecycleRevision
        } catch {
            guard !isBackgroundSuspended, lifecycle == lifecycleRevision else { return }
            await checkAccountIdentity()
            guard !isBackgroundSuspended, lifecycle == lifecycleRevision else { return }
            guard accountSession.accepts(ticket) else { retry = true; return }
            nativeTaskQuotaError = error.localizedDescription
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

    private func scheduleQuotaComputation(immediate: Bool) {
        quotaCalculationDebounceTask?.cancel()
        if immediate { recalculateTaskQuotaEstimates(); return }
        quotaCalculationDebounceTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(150)) } catch { return }
            guard let self, !self.isBackgroundSuspended else { return }
            self.recalculateTaskQuotaEstimates()
        }
    }

    private func recalculateTaskQuotaEstimates(now: Date = Date()) {
        quotaCalculationDebounceTask?.cancel()
        quotaCalculationDebounceTask = nil
        quotaRevision = UUID()
        guard !isBackgroundSuspended, let history = usageHistory, let ticket = accountSession.ticket else {
            quotaWorker.cancel()
            taskQuotaEstimatesByDuration = [:]
            dailyTaskQuotas = [:]
            return
        }
        let revision = quotaRevision
        let lifecycle = lifecycleRevision
        let historyVersion = historyRevision
        let prices = priceRevision
        let costs = CostSettings(settings)
        let timezone = Calendar.current.timeZone.identifier
        guard history.timezoneIdentifier == timezone else {
            quotaWorker.cancel()
            dailyTaskQuotas = [:]
            taskQuotaEstimatesByDuration = [:]
            Task { [weak self] in await self?.refreshUsageIfNeeded() }
            return
        }
        let input = QuotaComputationInput(history: history, nativeSnapshots: nativeQuotaSnapshots,
            accountKey: ticket.accountKey, accountSnapshot: resetCreditsSnapshot,
            unattributedSince: accountSession.unattributedQuotaSince, now: now)
        quotaWorker.submit(input) { [weak self] output in
            guard let self, !self.isBackgroundSuspended,
                  self.quotaRevision == revision, self.lifecycleRevision == lifecycle,
                  self.historyRevision == historyVersion, self.priceRevision == prices,
                  costs == CostSettings(self.settings), self.accountSession.accepts(ticket),
                  Calendar.current.timeZone.identifier == timezone else { return }
            let completedAt = Date()
            let crossedDay = Calendar.current.startOfDay(for: now) != Calendar.current.startOfDay(for: completedAt)
            let crossedReset = input.accountSnapshot?.quotaWindows.contains { now < $0.resetsAt && completedAt >= $0.resetsAt } == true
            if crossedDay || crossedReset { self.recalculateTaskQuotaEstimates(now: completedAt); return }
            self.dailyTaskQuotas = output.daily
            self.taskQuotaEstimatesByDuration = output.windows
        }
    }
}

private struct CostSettings: Equatable {
    let enabled: Bool
    let mode: RateCardMode
    @MainActor init(_ settings: AppSettings) {
        enabled = settings.experimentalLocalCostEstimatesEnabled
        mode = settings.rateCardMode
    }
}

private struct RefreshSettings: Equatable {
    let cost: CostSettings
    let automaticRates: Bool
    let showsRecommendations: Bool
    let automaticRadar: Bool
    let radarInterval: RefreshInterval
    let usageInterval: UsageRefreshInterval
    let quotaInterval: ResetCreditsRefreshInterval
    @MainActor init(_ settings: AppSettings) {
        cost = CostSettings(settings)
        automaticRates = settings.automaticRateCardUpdatesEnabled
        showsRecommendations = settings.showsStationRecommendations
        automaticRadar = settings.automaticRefreshEnabled
        radarInterval = settings.refreshInterval
        usageInterval = settings.usageRefreshInterval
        quotaInterval = settings.resetCreditsRefreshInterval
    }
}
