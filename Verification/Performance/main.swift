import Foundation

// Compile alongside Core sources to compare the same fixture with a frozen checkout.
// Inputs and full numerical outputs stay outside the repository's tracked files.
@main
struct PerformanceProbe {
    struct Fixture: Decodable {
        let history: UsageHistory
        let snapshots: [NativeTaskQuotaSnapshot]
        let accountKey: String
        let accountSnapshot: ResetCreditsSnapshot?
        let now: Date
    }
    struct Report: Encodable {
        let days: Int
        let observations: Int
        let snapshots: Int
        let legacySeconds: Double
        let nativeSeconds: Double
        let legacy: [Int: [String: Double]]
        let native: [Int: [String: DailyTaskQuotaValue]]
    }
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fatalError("Usage: performance-probe <fixture.json> <report.json>")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer()
            if let seconds = try? value.decode(Double.self) { return Date(timeIntervalSinceReferenceDate: seconds) }
            guard let date = MetricFormatter.sourceDate(try value.decode(String.self)) else {
                throw DecodingError.dataCorruptedError(in: value, debugDescription: "Invalid fixture date")
            }
            return date
        }
        let input = try decoder.decode(Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        let clock = ContinuousClock()
        let start = clock.now
        let legacy = TaskQuotaEstimator.dailyEstimates(history: input.history, accountKey: input.accountKey,
            now: input.now, accountSnapshot: input.accountSnapshot)
        let middle = clock.now
        let native = DailyTaskQuotaAnalyzer.values(history: input.history, snapshots: input.snapshots,
            accountKey: input.accountKey, now: input.now)
        let end = clock.now
        func seconds(_ duration: Duration) -> Double {
            Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        }
        let report = Report(days: input.history.days.count, observations: input.history.quotaObservations.count,
            snapshots: input.snapshots.count, legacySeconds: seconds(start.duration(to: middle)),
            nativeSeconds: seconds(middle.duration(to: end)), legacy: legacy, native: native)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(report).write(to: URL(fileURLWithPath: CommandLine.arguments[2]), options: .atomic)
        print("days=\(report.days) observations=\(report.observations) snapshots=\(report.snapshots) legacy_seconds=\(report.legacySeconds) native_seconds=\(report.nativeSeconds)")
    }
}
