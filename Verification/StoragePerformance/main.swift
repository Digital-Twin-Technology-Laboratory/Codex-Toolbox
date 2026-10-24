import Foundation
@_silgen_name("storage_written") func storageWritten() -> UInt64
@_silgen_name("storage_cpu") func storageCPU() -> Double

@main enum StoragePerformance {
    struct NativeEnvelope: Codable { var schemaVersion = 1; var snapshots: [NativeTaskQuotaSnapshot] }
    struct Measurement: Codable { var wallSeconds: Double; var cpuSeconds: Double; var bytesWritten: UInt64 }
    @MainActor static func measure(_ action: () async throws -> Void) async rethrows -> Measurement {
        let wall = Date(); let cpu = storageCPU(); let written = storageWritten()
        try await action()
        return Measurement(wallSeconds: Date().timeIntervalSince(wall), cpuSeconds: storageCPU() - cpu, bytesWritten: storageWritten() - written)
    }
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4, let scale = Int(args[3]), scale > 0 else { fatalError("Expected fixture-directory output-directory scale") }
        let fixture = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let original = try decoder.decode(VersionedUsageLedger.self, from: Data(contentsOf: fixture.appendingPathComponent("usage-ledger.json")))
        var ledger = original
        if scale > 1 {
            for copy in 1..<scale {
                for entry in original.threads.values {
                    var cloned = entry; cloned.threadID += "-copy\(copy)"; cloned.rootTaskID += "-copy\(copy)"
                    ledger.threads[cloned.threadID] = cloned
                }
                for observation in original.accountObservations {
                    var cloned = observation; cloned.accountKey = (cloned.accountKey ?? "unknown") + "-copy\(copy)"
                    ledger.accountObservations.append(cloned)
                }
            }
        }
        let ledgerURL = output.appendingPathComponent("ledger.json")
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(ledger).write(to: ledgerURL, options: .atomic)
        let nativeDecoder = JSONDecoder()
        nativeDecoder.dateDecodingStrategy = .custom { decoder in
            let field = try decoder.singleValueContainer()
            if let seconds = try? field.decode(Double.self) { return Date(timeIntervalSinceReferenceDate: seconds) }
            return MetricFormatter.sourceDate(try field.decode(String.self))!
        }
        let originalNative = try nativeDecoder.decode(NativeEnvelope.self, from: Data(contentsOf: fixture.appendingPathComponent("native-task-quota-v1.json")))
        var native = originalNative
        if scale > 1 {
            for copy in 1..<scale { native.snapshots += originalNative.snapshots.map {
                NativeTaskQuotaSnapshot(accountKey: $0.accountKey + "-copy\(copy)", thread: $0.thread, row: $0.row,
                    collectedAt: $0.collectedAt, dataAsOf: $0.dataAsOf, planType: $0.planType,
                    timezoneIdentifier: $0.timezoneIdentifier, continuityID: $0.continuityID)
            } }
        }
        let nativeURL = output.appendingPathComponent("native.json")
        try JSONEncoder().encode(native).write(to: nativeURL, options: .atomic)
        let reader = LocalCodexUsageReader(codexHome: output, ledgerURL: ledgerURL)
        let store = NativeTaskQuotaStore(fileURL: nativeURL)
        let now = max(ledger.accountObservations.map(\.timestamp).max() ?? ledger.generatedAt,
            native.snapshots.map(\.collectedAt).max() ?? ledger.generatedAt).addingTimeInterval(60)
        let windows = [AccountQuotaWindow(durationMinutes: 10080, usedPercent: 1, resetsAt: now.addingTimeInterval(7 * 86400))]
        var report: [String: Measurement] = [:]
        report["ledgerInitialImport"] = try await measure {
            try await reader.recordAccountQuotaSnapshot(windows: windows, planType: "pro", timestamp: now, accountKey: "benchmark")
        }
        report["nativeInitialImport"] = try await measure { _ = try await store.snapshots(accountKey: "benchmark") }
        report["ledgerAppend"] = try await measure {
            try await reader.recordAccountQuotaSnapshot(windows: windows, planType: "pro", timestamp: now.addingTimeInterval(60), accountKey: "benchmark")
        }
        report["ledgerIdenticalRetry"] = try await measure {
            try await reader.recordAccountQuotaSnapshot(windows: windows, planType: "pro", timestamp: now.addingTimeInterval(60), accountKey: "benchmark")
        }
        let sample = NativeTaskQuotaSnapshot(accountKey: "benchmark", thread: NativeThread(id: "benchmark", title: "Benchmark", createdAt: nil, descendantIDs: [], earliestCreatedAt: nil),
            row: NativeTaskUsageRow(id: "benchmark", status: "available", usageSource: "included_plan", fiveHourPercent: nil, weeklyPercent: 1, groups: []),
            collectedAt: now, dataAsOf: now, planType: "pro", timezoneIdentifier: ledger.timezoneIdentifier, continuityID: "benchmark")
        report["nativeAppend"] = try await measure { try await store.append([sample], now: now) }
        report["nativeIdenticalRetry"] = try await measure { try await store.append([sample], now: now) }
        struct Report: Codable { var scale: Int; var threads: Int; var observations: Int; var nativeSnapshots: Int; var measurements: [String: Measurement] }
        let result = Report(scale: scale, threads: ledger.threads.count,
            observations: ledger.threads.values.reduce(ledger.accountObservations.count) { $0 + $1.quotaObservations.count },
            nativeSnapshots: native.snapshots.count, measurements: report)
        let resultEncoder = JSONEncoder(); resultEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try resultEncoder.encode(result), as: UTF8.self))
    }
}
