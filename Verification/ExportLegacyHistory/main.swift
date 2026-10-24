import AppKit
import CodexToolboxCore
import Foundation

/// Explicit, one-time compatibility export; never runs as part of normal refresh.
@main
struct ExportLegacyHistory {
    enum Failure: LocalizedError {
        case usage, running, missingDirectory
        var errorDescription: String? {
            switch self {
            case .usage: "Usage: ExportLegacyHistory --directory <CodexToolbox data directory>"
            case .running: "Quit Codex Toolbox before exporting its active data directory."
            case .missingDirectory: "The requested data directory does not exist."
            }
        }
    }

    static func main() async {
        do { try await run() }
        catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }

    private static func run() async throws {
        if CommandLine.arguments == [CommandLine.arguments[0], "--help"] {
            print(Failure.usage.localizedDescription)
            return
        }
        guard CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--directory" else { throw Failure.usage }
        let directory = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true).resolvingSymlinksInPath()
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw Failure.missingDirectory
        }
        if directory == ApplicationSupportLayout().currentDirectory.resolvingSymlinksInPath(),
           !NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.zzzzzzjw.ShowCodexIQ").isEmpty {
            throw Failure.running
        }
        let ledger = directory.appendingPathComponent("usage-ledger.json")
        let native = directory.appendingPathComponent("native-task-quota-v1.json")
        if FileManager.default.fileExists(atPath: ledger.appendingPathExtension("sqlite").path) {
            let reader = LocalCodexUsageReader(codexHome: directory, ledgerURL: ledger)
            try await reader.exportLegacyHistory()
            await reader.close()
            print("Exported usage-ledger.json")
        } else { print("Usage ledger has not migrated; existing JSON retained.") }
        if FileManager.default.fileExists(atPath: native.appendingPathExtension("sqlite").path) {
            let store = NativeTaskQuotaStore(fileURL: native)
            try await store.exportLegacyHistory()
            await store.close()
            print("Exported native-task-quota-v1.json")
        } else { print("Native snapshots have not migrated; existing JSON retained.") }
        print("Compatibility export complete. SQLite and migration backups retained.")
    }
}
