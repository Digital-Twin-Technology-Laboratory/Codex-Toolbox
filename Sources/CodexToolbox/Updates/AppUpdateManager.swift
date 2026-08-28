import CodexToolboxCore
import Foundation
import Observation
import OSLog
import Sparkle

enum AppUpdateState: Equatable {
    case idle
    case checking
    case retryingCheck(attempt: Int)
    case upToDate(checkedAt: Date)
    case downloading(version: String)
    case preparing(version: String)
    case readyToInstall(version: String)
    case installing(version: String)
    case failed(String)
}

enum UpdateCheckFrequency: TimeInterval, CaseIterable, Identifiable {
    case hourly = 3_600
    case daily = 86_400

    var id: TimeInterval { rawValue }

    var displayName: String {
        switch self {
        case .hourly: "每小时"
        case .daily: "每天"
        }
    }

    static func closest(to interval: TimeInterval) -> UpdateCheckFrequency {
        allCases.min { abs($0.rawValue - interval) < abs($1.rawValue - interval) } ?? .daily
    }
}

@MainActor
@Observable
final class AppUpdateManager: NSObject, SPUUpdaterDelegate {
    private enum LifecycleError {
        static let domain = "CodexToolbox.UpdateLifecycle"
        static let suspended = 1
    }

    private enum DefaultsKey {
        static let didMigrateLegacyPreference = "didMigrateLegacyUpdatePreferenceToSparkle"
        static let legacyAutomaticChecks = "automaticUpdateChecksEnabled"
    }

    var state: AppUpdateState = .idle
    private(set) var automaticallyChecksForUpdates = true
    private(set) var checkFrequency: UpdateCheckFrequency = .daily

    var showsUpdateBadge: Bool {
        if case .readyToInstall = state { return true }
        return false
    }

    @ObservationIgnored
    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: false,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    @ObservationIgnored
    private var immediateInstallationHandler: (() -> Void)?

    @ObservationIgnored
    private let defaults: UserDefaults

    @ObservationIgnored
    private let isEnabled: Bool

    @ObservationIgnored
    private var didStart = false

    @ObservationIgnored
    private var pendingUserInitiatedCheck = false

    @ObservationIgnored
    private var pendingRetryOrigin: UpdateCheckOrigin?

    @ObservationIgnored
    private var activeCheckOrigin: UpdateCheckOrigin = .scheduled

    @ObservationIgnored
    private var completedRetries = 0

    @ObservationIgnored
    private var preCheckState: AppUpdateState = .idle

    @ObservationIgnored
    private var retryTask: Task<Void, Never>?

    @ObservationIgnored
    private var applicationIsAwake = true

    @ObservationIgnored
    private let logger = Logger(
        subsystem: "io.github.zzzzzzjw.CodexToolbox",
        category: "Updates"
    )

    init(defaults: UserDefaults = .standard, isEnabled: Bool = true) {
        self.defaults = defaults
        self.isEnabled = isEnabled
        super.init()
    }

    func start() {
        guard isEnabled, !didStart else { return }
        didStart = true

        let updater = updaterController.updater
        migrateLegacyPreferenceIfNeeded(to: updater)
        updaterController.startUpdater()
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        checkFrequency = .closest(to: updater.updateCheckInterval)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        start()
        let updater = updaterController.updater
        updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        if enabled {
            updater.resetUpdateCycleAfterShortDelay()
        }
    }

    func setCheckFrequency(_ frequency: UpdateCheckFrequency) {
        start()
        let updater = updaterController.updater
        updater.updateCheckInterval = frequency.rawValue
        checkFrequency = .closest(to: updater.updateCheckInterval)
        if updater.automaticallyChecksForUpdates {
            updater.resetUpdateCycleAfterShortDelay()
        }
    }

    func checkForUpdates() {
        start()
        let updater = updaterController.updater
        guard updater.canCheckForUpdates else { return }
        retryTask?.cancel()
        pendingUserInitiatedCheck = true
        pendingRetryOrigin = nil
        completedRetries = 0
        preCheckState = stableState(before: state)
        state = .checking
        // The settings page is our user-facing progress UI. Keep this check
        // in the background so a newly found update follows the same silent
        // download -> badge -> explicit install flow as a scheduled check.
        updater.checkForUpdatesInBackground()
    }

    func setApplicationAwake(_ isAwake: Bool) {
        applicationIsAwake = isAwake
        guard !isAwake else { return }

        retryTask?.cancel()
        retryTask = nil
        pendingRetryOrigin = nil
        pendingUserInitiatedCheck = false
        if case .checking = state {
            state = preCheckState
        } else if case .retryingCheck = state {
            state = preCheckState
        }
    }

    func installReadyUpdate() {
        guard case let .readyToInstall(version) = state else {
            checkForUpdates()
            return
        }
        guard let immediateInstallationHandler else {
            state = .failed("更新已下载，但安装会话已失效，请重新检查更新。")
            return
        }
        state = .installing(version: version)
        immediateInstallationHandler()
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state = .downloading(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard applicationIsAwake else {
            throw NSError(
                domain: LifecycleError.domain,
                code: LifecycleError.suspended,
                userInfo: [NSLocalizedDescriptionKey: "Update check paused while Mac sleeps."]
            )
        }

        if let retryOrigin = pendingRetryOrigin {
            activeCheckOrigin = retryOrigin
            pendingRetryOrigin = nil
        } else if pendingUserInitiatedCheck {
            activeCheckOrigin = .userInitiated
            pendingUserInitiatedCheck = false
        } else {
            activeCheckOrigin = .scheduled
            completedRetries = 0
            preCheckState = stableState(before: state)
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        state = .upToDate(checkedAt: Date())
    }

    func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
        state = .downloading(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didDownloadUpdate item: SUAppcastItem) {
        state = .preparing(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, willExtractUpdate item: SUAppcastItem) {
        state = .preparing(version: item.displayVersionString)
    }

    func updater(
        _ updater: SPUUpdater,
        failedToDownloadUpdate item: SUAppcastItem,
        error: any Error
    ) {
        log(error, context: "download")
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        immediateInstallationHandler = immediateInstallHandler
        state = .readyToInstall(version: item.displayVersionString)
        return true
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        state = .installing(version: item.displayVersionString)
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        guard let error else {
            clearRecoveryBookkeeping()
            if case .checking = state {
                state = .upToDate(checkedAt: Date())
            } else if case .retryingCheck = state {
                state = .upToDate(checkedAt: Date())
            }
            return
        }

        log(error, context: "cycle")
        let nsError = error as NSError
        if !applicationIsAwake
            || (nsError.domain == LifecycleError.domain
                && nsError.code == LifecycleError.suspended) {
            clearRecoveryBookkeeping()
            return
        }
        if case .upToDate = state {
            clearRecoveryBookkeeping()
            return
        }
        if case .readyToInstall = state {
            clearRecoveryBookkeeping()
            return
        }

        switch UpdateRecoveryPolicy.action(
            origin: activeCheckOrigin,
            completedRetries: completedRetries,
            error: error
        ) {
        case let .retry(delay):
            scheduleRetry(after: delay, origin: activeCheckOrigin)
        case .preservePreviousState:
            restorePreCheckState()
        case let .present(message):
            clearRecoveryBookkeeping()
            state = .failed(message)
        }
    }

    private func scheduleRetry(after delay: Duration, origin: UpdateCheckOrigin) {
        retryTask?.cancel()
        if origin == .userInitiated {
            state = .retryingCheck(attempt: completedRetries + 1)
        } else {
            state = preCheckState
        }

        retryTask = Task { [weak self] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self,
                  self.applicationIsAwake else { return }
            let updater = self.updaterController.updater
            guard updater.canCheckForUpdates else {
                if origin == .userInitiated {
                    self.clearRecoveryBookkeeping()
                    self.state = .failed("更新服务暂时忙，请稍后重试。")
                } else {
                    self.restorePreCheckState()
                }
                return
            }
            self.completedRetries += 1
            self.pendingRetryOrigin = origin
            updater.checkForUpdatesInBackground()
        }
    }

    private func restorePreCheckState() {
        clearRecoveryBookkeeping()
        state = preCheckState
    }

    private func clearRecoveryBookkeeping() {
        retryTask?.cancel()
        retryTask = nil
        pendingUserInitiatedCheck = false
        pendingRetryOrigin = nil
        completedRetries = 0
    }

    private func stableState(before candidate: AppUpdateState) -> AppUpdateState {
        switch candidate {
        case .checking, .retryingCheck, .downloading, .preparing, .installing:
            return .idle
        case .idle, .upToDate, .readyToInstall, .failed:
            return candidate
        }
    }

    private func log(_ error: any Error, context: String) {
        let nsError = error as NSError
        logger.error(
            "Sparkle \(context, privacy: .public) failed: \(nsError.domain, privacy: .public) \(nsError.code)"
        )
    }

    private func migrateLegacyPreferenceIfNeeded(to updater: SPUUpdater) {
        guard !defaults.bool(forKey: DefaultsKey.didMigrateLegacyPreference) else { return }
        if defaults.object(forKey: DefaultsKey.legacyAutomaticChecks) != nil {
            updater.automaticallyChecksForUpdates = defaults.bool(
                forKey: DefaultsKey.legacyAutomaticChecks
            )
        }
        defaults.set(true, forKey: DefaultsKey.didMigrateLegacyPreference)
    }
}
