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
    private let identityRepository = AccountIdentityRepository()
    private let nativeTaskQuotaStore = NativeTaskQuotaStore()
    private let nativeTaskQuotaScheduler = RefreshScheduler()
    private var nativeQuotaSnapshots: [NativeTaskQuotaSnapshot] = []
    private var nativeContinuityID = UUID().uuidString
    private var nativeDayBoundaryTask: Task<Void, Never>?
    private var nativePriorityTaskIDs: Set<String> = []
    private var lastNativeQuotaRefreshAt: Date?
    private var isBackgroundSuspended = false
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

    var todayUsage: DailyUsageSummary? {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let key = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return usageHistory?.summary(for: key)
    }

    var snapshot: RadarSnapshot? { repositoryState.snapshot }
    var costHistory: [CostHistoryPoint] { repositoryState.costHistory }
    var isStale: Bool { repositoryState.isStale || (snapshot?.sourceMonitoredAt.flatMap(MetricFormatter.sourceDate).map { Date().timeIntervalSince($0) > 24 * 3600 } ?? false) }
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
        guard settings.experimentalLocalCostEstimatesEnabled, !isRefreshingRateCard else { return }
        isRefreshingRateCard = true
        defer { isRefreshingRateCard = false }
        isRefreshingAPIPriceCard = true
        async let creditCard = rateCardRepository.refresh()
        async let priceCard = apiPriceCardRepository.refresh()
        let rates = await creditCard
        let prices = await priceCard
        isRefreshingAPIPriceCard = false
        guard settings.experimentalLocalCostEstimatesEnabled else { return }
        rateCardState = rates
        apiPriceCardState = prices
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
            var costsEnabled = settings.experimentalLocalCostEstimatesEnabled
            var refreshed = try await usageReader.readUsage(
                now: Date(),
                calendar: .current,
                rateCard: costsEnabled ? rateCardState.manifest : nil,
                rateCardMode: settings.rateCardMode,
                apiPriceCard: costsEnabled ? apiPriceCardState.manifest : nil
            )
            while costsEnabled != settings.experimentalLocalCostEstimatesEnabled {
                costsEnabled = settings.experimentalLocalCostEstimatesEnabled
                refreshed = try await usageReader.readUsage(now: Date(), calendar: .current,
                    rateCard: costsEnabled ? rateCardState.manifest : nil, rateCardMode: settings.rateCardMode,
                    apiPriceCard: costsEnabled ? apiPriceCardState.manifest : nil)
            }
            usageHistory = refreshed
            recalculateTaskQuotaEstimates()
            usageErrorMessage = nil
            Task { [weak self] in await self?.refreshNativeTaskQuota() }
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

    func checkAccountIdentity() async {
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
        guard identityRefreshID == id else { return }
        identityRefreshID = nil
        identityRefreshTask = nil
        guard accountSession.observe(authentication) else { return }
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
            guard accountSession.accepts(ticket) else { return }
            resetCreditsSnapshot = cached
            isResetCreditsStale = cached != nil
            let snapshots = try? await nativeTaskQuotaStore.snapshots(accountKey: ticket.accountKey)
            guard accountSession.accepts(ticket) else { return }
            nativeQuotaSnapshots = snapshots ?? []
            recalculateTaskQuotaEstimates()
        }
    }

    func refreshResetCredits() async {
        guard !isRefreshingResetCredits else { return }
        isRefreshingResetCredits = true
        var retryForNewAccount = false
        defer {
            isRefreshingResetCredits = false
            if retryForNewAccount, accountSession.ticket != nil {
                Task { [weak self] in await self?.refreshResetCredits() }
            }
        }
        await checkAccountIdentity()
        guard let ticket = accountSession.ticket else { return }
        do {
            let refreshedSnapshot = try await resetCreditsReader.readResetCredits()
            await checkAccountIdentity()
            guard accountSession.accepts(ticket) else { retryForNewAccount = true; return }
            let preservedCreditDetails = refreshedSnapshot.shouldPreserveCreditDetails(from: resetCreditsSnapshot)
            let snapshot = refreshedSnapshot.preservingCreditDetails(from: resetCreditsSnapshot)
            resetCreditsSnapshot = snapshot
            isResetCreditsStale = preservedCreditDetails
            resetCreditsErrorMessage = nil
            try? await resetCreditsCache.save(snapshot, accountKey: ticket.accountKey)
            try? await usageReader.recordAccountQuotaSnapshot(
                windows: snapshot.quotaWindows, planType: snapshot.planType,
                timestamp: snapshot.fetchedAt, accountKey: ticket.accountKey
            )
            guard accountSession.accepts(ticket) else { retryForNewAccount = true; return }
            usageHistory = usageHistory?.appendingAccountSnapshot(
                timestamp: snapshot.fetchedAt, planType: snapshot.planType,
                windows: snapshot.quotaWindows, accountKey: ticket.accountKey
            )
            recalculateTaskQuotaEstimates()
        } catch {
            await checkAccountIdentity()
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
        nativeContinuityID = UUID().uuidString
        nativeDayBoundaryTask?.cancel()
        updateManager.setApplicationAwake(false)
        async let radar: Void = radarScheduler.stop()
        async let usage: Void = usageScheduler.stop()
        async let credits: Void = resetCreditsScheduler.stop()
        async let rates: Void = rateCardScheduler.stop()
        async let quota: Void = activeQuotaScheduler.stop()
        async let native: Void = nativeTaskQuotaScheduler.stop()
        _ = await (radar, usage, credits, rates, quota, native)
    }

    func resumeBackgroundWork() async {
        isBackgroundSuspended = false
        updateManager.setApplicationAwake(true)
        await reconfigureSchedulers()
        await refreshAllIfNeeded()
        await refreshNativeTaskQuota(force: true)
    }

    func settingsDidChange() {
        Task {
            if !settings.experimentalLocalCostEstimatesEnabled {
                async let rates: Void = rateCardRepository.cancelRefresh()
                async let prices: Void = apiPriceCardRepository.cancelRefresh()
                _ = await (rates, prices)
            }
            await reconfigureSchedulers()
            if settings.showsStationRecommendations,
               stationRecommendationState.snapshot == nil {
                stationRecommendationState = await stationRepository.loadCached()
                await refreshStationRecommendations()
            }
            await refreshUsage()
            if settings.experimentalLocalCostEstimatesEnabled && settings.automaticRateCardUpdatesEnabled {
                await refreshRateCard()
            }
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
            enabled: settings.experimentalLocalCostEstimatesEnabled && settings.automaticRateCardUpdatesEnabled,
            everyMinutes: 360
        ) { [weak self] in
            await self?.refreshRateCard()
        }
        await activeQuotaScheduler.configure(enabled: true, everyMinutes: 1) { [weak self] in
            await self?.checkAccountIdentity()
            await self?.sampleActiveAccountQuotaIfNeeded()
        }
        await nativeTaskQuotaScheduler.configure(enabled: !isBackgroundSuspended, everyMinutes: 5) { [weak self] in
            await self?.refreshNativeTaskQuota(force: true)
        }
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

    func prioritizeNativeQuotaTasks(_ rootIDs: Set<String>) {
        guard nativePriorityTaskIDs != rootIDs else { return }
        nativePriorityTaskIDs = rootIDs
        Task { [weak self] in await self?.refreshNativeTaskQuota(force: true) }
    }

    func refreshNativeTaskQuota(force: Bool = false) async {
        guard !isBackgroundSuspended, !isDemoMode, !isRefreshingNativeTaskQuota,
              force || lastNativeQuotaRefreshAt.map({ Date().timeIntervalSince($0) >= 300 }) != false,
              let catalogueReader = usageReader as? any NativeThreadReading else { return }
        isRefreshingNativeTaskQuota = true
        let priorities = nativePriorityTaskIDs
        var retry = false
        defer {
            isRefreshingNativeTaskQuota = false
            if !isBackgroundSuspended && (retry || priorities != nativePriorityTaskIDs) {
                Task { [weak self] in await self?.refreshNativeTaskQuota(force: true) }
            }
        }
        await checkAccountIdentity()
        guard let ticket = accountSession.ticket else { return }
        let continuity = nativeContinuityID
        do {
            let now = Date()
            let catalogue = try await catalogueReader.nativeCatalogue(now: now)
            let since = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: now)) ?? now
            let roots = priorities.union(usageHistory?.days.filter { $0.dateKey >= Self.quotaDayKey(since) }.flatMap { $0.tasks.map(\.rootTaskID) } ?? [])
            let threads = catalogue.threads.filter { roots.contains($0.id) }.sorted {
                if priorities.contains($0.id) != priorities.contains($1.id) { return priorities.contains($0.id) }
                return $0.id < $1.id
            }
            guard !threads.isEmpty else { return }
            for batch in DailyTaskQuotaAnalyzer.batches(threads) {
                guard accountSession.accepts(ticket), continuity == nativeContinuityID, !isBackgroundSuspended else { retry = true; return }
                let report = try await identityRepository.taskUsage(threads: batch)
                await checkAccountIdentity()
                guard accountSession.accepts(ticket), report.accountKey == ticket.accountKey,
                      continuity == nativeContinuityID, !isBackgroundSuspended else { retry = true; return }
                let requested = Dictionary(uniqueKeysWithValues: batch.map { ($0.id, $0) })
                guard report.threads.allSatisfy({ requested[$0.id] != nil }),
                      let collected = MetricFormatter.sourceDate(report.collectedAt) else { throw NativeAnalyticsError.invalidResponse }
                let additions = report.threads.compactMap { row -> NativeTaskQuotaSnapshot? in
                    guard let thread = requested[row.id] else { return nil }
                    return NativeTaskQuotaSnapshot(accountKey: ticket.accountKey, thread: thread, row: row, collectedAt: collected,
                        dataAsOf: report.dataAsOf.flatMap(MetricFormatter.sourceDate), planType: report.planType,
                        timezoneIdentifier: usageHistory?.timezoneIdentifier ?? Calendar.current.timeZone.identifier, continuityID: continuity)
                }
                try await nativeTaskQuotaStore.append(additions, now: Date())
                guard accountSession.accepts(ticket) else { retry = true; return }
                nativeQuotaSnapshots = try await nativeTaskQuotaStore.snapshots(accountKey: ticket.accountKey)
                guard accountSession.accepts(ticket) else { retry = true; return }
                recalculateTaskQuotaEstimates()
            }
            lastNativeQuotaRefreshAt = Date()
            nativeTaskQuotaError = nil
        } catch {
            await checkAccountIdentity()
            guard accountSession.accepts(ticket) else { retry = true; return }
            nativeTaskQuotaError = error.localizedDescription
        }
    }

    private static func quotaDayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
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
        guard let history = usageHistory, let key = accountSession.authentication.accountKey else {
            taskQuotaEstimatesByDuration = [:]
            dailyTaskQuotas = [:]
            return
        }
        dailyTaskQuotas = DailyTaskQuotaAnalyzer.values(history: history, snapshots: nativeQuotaSnapshots, accountKey: key, now: now)
        for (duration, tasks) in TaskQuotaEstimator.dailyEstimates(
            history: history, accountKey: key, now: now, accountSnapshot: resetCreditsSnapshot,
            unattributedSince: accountSession.unattributedQuotaSince
        ) {
            for (id, percent) in tasks where dailyTaskQuotas[duration]?[id] == nil {
                dailyTaskQuotas[duration, default: [:]][id] = DailyTaskQuotaValue(percent: percent, isExact: false,
                    updatedAt: history.generatedAt, help: "本机逐轮额度观测校准的当日估算；未标账户历史仅按已验证套餐和窗口作近似匹配，不回填账户身份。")
            }
        }
        let supported = Set(TaskQuotaMetric.supported(by: resetCreditsSnapshot?.quotaWindows ?? []).map(\.rawValue))
        dailyTaskQuotas = dailyTaskQuotas.filter { supported.contains($0.key) }
        taskQuotaEstimatesByDuration = (resetCreditsSnapshot?.quotaWindows ?? []).reduce(
            into: [:]
        ) { result, window in
            guard now < window.resetsAt else { return }
            result[window.durationMinutes] = TaskQuotaEstimator.estimates(
                history: history,
                window: window,
                now: now,
                accountKey: key
            )
        }
    }
}
