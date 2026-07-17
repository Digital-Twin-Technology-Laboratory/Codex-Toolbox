import Combine
import CodexToolboxCore
import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginController: ObservableObject {
    private static let renameMigrationKey = "didReconcileLaunchAtLoginForCodexToolboxV1"

    @Published private(set) var isEnabled = false
    @Published private(set) var errorMessage: String?

    var isInstalledInApplications: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    init() {
        refreshStatus()
    }

    /// Re-registers the login item once so an existing Show Codex IQ registration
    /// follows the renamed application bundle at its new /Applications path.
    static func reconcileAfterRename(
        settings: AppSettings,
        defaults: UserDefaults = .standard
    ) {
        guard !defaults.bool(forKey: renameMigrationKey) else { return }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else { return }

        let service = SMAppService.mainApp
        let shouldRemainEnabled = settings.launchAtLoginEnabled || service.status == .enabled

        do {
            if shouldRemainEnabled {
                if service.status == .enabled {
                    try service.unregister()
                }
                try service.register()
                settings.launchAtLoginEnabled = service.status == .enabled
            }
            defaults.set(true, forKey: renameMigrationKey)
        } catch {
            // Leave the marker unset so the next launch can retry after the user
            // has approved Login Items or repaired the installation.
        }
    }

    func setEnabled(_ enabled: Bool) {
        errorMessage = nil
        guard !enabled || isInstalledInApplications else {
            errorMessage = "请先将 Codex Toolbox 安装到“应用程序”文件夹。"
            isEnabled = false
            return
        }

        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshStatus()
        } catch {
            refreshStatus()
            errorMessage = "无法更改开机启动设置：\(error.localizedDescription)"
        }
    }

    func refreshStatus() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}
