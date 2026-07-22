import AppKit
import CodexToolboxCore
import SwiftUI

@main
struct CodexToolboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(appModel: appDelegate.appModel)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appModel: AppModel

    private var statusItemController: StatusItemController?

    override init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--demo-dashboard") {
            let demoDefaults = UserDefaults(suiteName: "io.github.zzzzzzjw.CodexToolbox.Demo")!
            let demoCacheURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("CodexToolbox-Demo", isDirectory: true)
                .appendingPathComponent("reset-credits.json")
            appModel = AppModel(
                settings: AppSettings(defaults: demoDefaults),
                usageReader: DemoUsageReader(),
                resetCreditsReader: DemoResetCreditsReader(),
                resetCreditsCache: ResetCreditsCacheStore(fileURL: demoCacheURL),
                updateManager: AppUpdateManager(isEnabled: false),
                isDemoMode: true
            )
        } else {
            appModel = AppModel()
        }
        #else
        appModel = AppModel()
        #endif
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        statusItemController = StatusItemController(appModel: appModel)
        if !appModel.isDemoMode {
            LaunchAtLoginController.reconcileAfterRename(settings: appModel.settings)
        }

        Task {
            await appModel.start()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func workspaceDidWake(_ notification: Notification) {
        Task {
            await appModel.refreshAllIfNeeded()
        }
    }
}
