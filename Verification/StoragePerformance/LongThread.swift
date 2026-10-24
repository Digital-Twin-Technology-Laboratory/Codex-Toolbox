import Foundation
import SQLite3
@_silgen_name("storage_written") func storageWritten() -> UInt64
@_silgen_name("storage_cpu") func storageCPU() -> Double

/// Synthetic, non-sensitive long-thread fixture. Compile against either frozen Core revision.
@main enum LongThreadPerformance {
    struct Measurement: Codable { var cpuSeconds: Double; var wallSeconds: Double; var bytesWritten: UInt64 }
    @MainActor static func measure(_ action: () async throws -> Void) async rethrows -> Measurement {
        let cpu = storageCPU(), wall = Date(), written = storageWritten()
        try await action()
        return .init(cpuSeconds: storageCPU() - cpu, wallSeconds: Date().timeIntervalSince(wall), bytesWritten: storageWritten() - written)
    }
    static func main() async throws {
        guard CommandLine.arguments.count == 3, let scale = Int(CommandLine.arguments[2]), scale > 0 else { fatalError("Expected output-directory scale") }
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let rollout = directory.appendingPathComponent("synthetic.jsonl"), source = directory.appendingPathComponent("state_test.sqlite"), ledger = directory.appendingPathComponent("ledger.json")
        let days = 150 * scale, perDay = 435, start = Date(timeIntervalSince1970: 1_700_006_400)
        func event(_ index: Int) -> Data {
            let date = start.addingTimeInterval(Double(index / perDay) * 86400 + Double(index % perDay))
            return Data("{\"timestamp\":\"\(date.ISO8601Format())\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":{\"total_token_usage\":{\"total_tokens\":\(index + 1)},\"last_token_usage\":{\"total_tokens\":1}}}}\n".utf8)
        }
        var contents = Data()
        for index in 0..<(days * perDay) { contents.append(event(index)) }
        try contents.write(to: rollout)
        var db: OpaquePointer?; guard sqlite3_open(source.path, &db) == SQLITE_OK else { fatalError("fixture database") }
        let escapedPath = rollout.path.replacingOccurrences(of: "'", with: "''")
        let sql = "CREATE TABLE threads(id TEXT PRIMARY KEY,title TEXT,rollout_path TEXT,created_at INTEGER,updated_at INTEGER,tokens_used INTEGER); INSERT INTO threads VALUES('root','Synthetic','\(escapedPath)',1,1,1);"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { fatalError("fixture schema") }; sqlite3_close(db)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone.current
        let reader = LocalCodexUsageReader(codexHome: directory, stateDatabaseURL: source, ledgerURL: ledger)
        var report: [String: Measurement] = [:]
        report["initialRead"] = try await measure { _ = try await reader.readUsage(calendar: calendar) }
        let file = try FileHandle(forWritingTo: rollout); try file.seekToEnd(); try file.write(contentsOf: event(days * perDay)); try file.close()
        report["rolloutAppend"] = try await measure {
            let history = try await reader.readUsage(calendar: calendar)
            precondition(history.days.reduce(Int64(0)) { $0 + $1.totalTokens } == Int64(days * perDay + 1))
        }
        report["rolloutIdenticalRetry"] = try await measure { _ = try await reader.readUsage(calendar: calendar) }
        struct Report: Codable { var scale: Int; var days: Int; var observations: Int; var measurements: [String: Measurement] }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(Report(scale: scale, days: days, observations: days * perDay, measurements: report)), as: UTF8.self))
    }
}
