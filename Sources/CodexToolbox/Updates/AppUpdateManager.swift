import Foundation
import Observation
import Sparkle

enum AppUpdateState: Equatable {
    case idle
    case checking
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
        state = .checking
        // The settings page is our user-facing progress UI. Keep this check
        // in the background so a newly found update follows the same silent
        // download -> badge -> explicit install flow as a scheduled check.
        updater.checkForUpdatesInBackground()
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
        state = .failed("下载更新失败：\(error.localizedDescription)")
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
            if case .checking = state {
                state = .upToDate(checkedAt: Date())
            }
            return
        }
        if case .upToDate = state { return }
        if case .readyToInstall = state { return }
        state = .failed(error.localizedDescription)
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
