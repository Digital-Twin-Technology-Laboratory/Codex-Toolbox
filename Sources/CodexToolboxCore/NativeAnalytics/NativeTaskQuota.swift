import Foundation

public enum TaskQuotaMetric: Int, Codable, CaseIterable, Sendable {
    case weekly = 10080, fiveHour = 300
    public var displayName: String { self == .weekly ? "周" : "5小时" }
    public static func supported(by windows: [AccountQuotaWindow]) -> [Self] {
        let durations = Set(windows.map(\.durationMinutes))
        return allCases.filter { durations.contains($0.rawValue) }
    }
}

public struct NativeTaskUsageRow: Codable, Equatable, Sendable {
    public let id: String
    public let status: String
    public let usageSource: String
    public let fiveHourPercent: Double?
    public let weeklyPercent: Double?
    public let groups: [Group]
    public struct Group: Codable, Equatable, Sendable {
        public let product: String?
        public let model: String?
        public let effort: String?
        public let speed: String?
        public let fiveHourPercent: Double?
        public let weeklyPercent: Double?
    }
    public func percent(_ metric: TaskQuotaMetric) -> Double? {
        metric == .weekly ? weeklyPercent : fiveHourPercent
    }
}

public struct NativeTaskUsageReport: Decodable, Sendable {
    public let schemaVersion: Int
    public let accountKey: String
    public let planType: String?
    public let collectedAt: String
    public let dataAsOf: String?
    public let threads: [NativeTaskUsageRow]
    public static func decode(_ data: Data) throws -> Self {
        let report = try JSONDecoder().decode(Self.self, from: data)
        let values = report.threads.flatMap { row in
            [row.fiveHourPercent, row.weeklyPercent] + row.groups.flatMap { [$0.fiveHourPercent, $0.weeklyPercent] }
        }.compactMap { $0 }
        guard report.schemaVersion == 3, report.accountKey.count == 64, report.accountKey.allSatisfy(\.isHexDigit),
              let collected = MetricFormatter.sourceDate(report.collectedAt), collected <= Date().addingTimeInterval(300),
              report.dataAsOf == nil || report.dataAsOf.flatMap(MetricFormatter.sourceDate).map({ $0 <= collected }) == true,
              report.threads.count <= 100, Set(report.threads.map(\.id)).count == report.threads.count,
              report.threads.allSatisfy({ ["available", "partial", "unavailable"].contains($0.status) }),
              values.allSatisfy({ $0.isFinite && $0 >= 0 }) else { throw NativeAnalyticsError.invalidResponse }
        return report
    }
}

public struct NativeTaskQuotaSnapshot: Codable, Equatable, Sendable {
    public let accountKey: String
    public let thread: NativeThread
    public let row: NativeTaskUsageRow
    public let collectedAt: Date
    public let dataAsOf: Date?
    public let planType: String?
    public let timezoneIdentifier: String
    public let continuityID: String
    public init(accountKey: String, thread: NativeThread, row: NativeTaskUsageRow, collectedAt: Date, dataAsOf: Date?, planType: String?, timezoneIdentifier: String, continuityID: String) {
        self.accountKey = accountKey; self.thread = thread; self.row = row; self.collectedAt = collectedAt
        self.dataAsOf = dataAsOf; self.planType = planType; self.timezoneIdentifier = timezoneIdentifier; self.continuityID = continuityID
    }
    public var effectiveAt: Date { dataAsOf ?? collectedAt }
    public var epoch: String { "\(planType ?? "unknown")|\(row.usageSource)|\(thread.scopeKey)|\(continuityID)" }
}

public struct DailyTaskQuotaValue: Codable, Equatable, Sendable {
    public let percent: Double
    public let isExact: Bool
    public let updatedAt: Date
    public let help: String
    public init(percent: Double, isExact: Bool, updatedAt: Date, help: String) {
        self.percent = percent; self.isExact = isExact; self.updatedAt = updatedAt; self.help = help
    }
    public var comparison: String { isExact ? "=" : "≈" }
    public static func combined(_ values: [Self?]) -> Self? {
        guard !values.isEmpty, values.allSatisfy({ $0 != nil }) else { return nil }
        let known = values.compactMap { $0 }
        return Self(percent: known.reduce(0) { $0 + $1.percent }, isExact: known.allSatisfy(\.isExact),
                    updatedAt: known.map(\.updatedAt).min()!, help: known.map(\.help).joined(separator: "；"))
    }
}

/// A separate journal keeps account-derived observations out of machine-wide Token history.
public actor NativeTaskQuotaStore {
    private struct Envelope: Codable { var schemaVersion = 1; var snapshots: [NativeTaskQuotaSnapshot] }
    private let fileURL: URL
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? ApplicationSupportLayout().currentDirectory.appendingPathComponent("native-task-quota-v1.json")
    }
    private func load() throws -> [NativeTaskQuotaSnapshot] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { value in
            let field = try value.singleValueContainer()
            if let seconds = try? field.decode(Double.self) { return Date(timeIntervalSinceReferenceDate: seconds) }
            guard let date = MetricFormatter.sourceDate(try field.decode(String.self)) else { throw NativeAnalyticsError.invalidResponse }
            return date
        }
        let envelope = try decoder.decode(Envelope.self, from: Data(contentsOf: fileURL))
        guard envelope.schemaVersion == 1 else { throw NativeAnalyticsError.invalidResponse }
        return envelope.snapshots
    }
    public func snapshots(accountKey: String) throws -> [NativeTaskQuotaSnapshot] {
        try load().filter { $0.accountKey == accountKey }
    }
    public func append(_ additions: [NativeTaskQuotaSnapshot], now: Date) throws {
        guard !additions.isEmpty else { return }
        var all = try load()
        let cutoff = now.addingTimeInterval(-90 * 86400)
        all.removeAll { $0.collectedAt < cutoff }
        for snapshot in additions where !all.contains(snapshot) { all.append(snapshot) }
        // Preserve subsecond watermarks exactly; legacy ISO strings remain readable.
        let encoder = JSONEncoder()
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(Envelope(snapshots: all)).write(to: fileURL, options: .atomic)
    }
}

public enum DailyTaskQuotaAnalyzer {
    private struct Interval {
        let start: NativeTaskQuotaSnapshot
        let end: NativeTaskQuotaSnapshot
        let percent: Double
        let observations: [LocalQuotaUsageObservation]
        let baselineAt: Date
        var weight: Double { observations.reduce(0) { $0 + Double($1.tokenIncrement) } }
    }
    public static func values(history: UsageHistory, snapshots: [NativeTaskQuotaSnapshot], accountKey: String, now: Date) -> [Int: [String: DailyTaskQuotaValue]] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: history.timezoneIdentifier) ?? .current
        let scoped = snapshots.filter { $0.accountKey == accountKey && $0.timezoneIdentifier == history.timezoneIdentifier && $0.collectedAt <= now }
        let byRoot = Dictionary(grouping: scoped, by: { $0.thread.id })
        let local = Dictionary(grouping: history.quotaObservations.filter { !$0.isAccountSnapshot && $0.tokenIncrement > 0 }, by: \.rootTaskID)
        var result: [Int: [String: DailyTaskQuotaValue]] = [:]
        for metric in TaskQuotaMetric.allCases {
            var intervals: [String: [Interval]] = [:]
            var baselines: [String: [Date: Date]] = [:]
            for (root, unsorted) in byRoot {
                let sorted = unsorted.sorted { $0.collectedAt < $1.collectedAt }
                guard let first = sorted.first else { continue }
                var baselineAt = first.collectedAt
                baselines[root, default: [:]][first.collectedAt] = baselineAt
                // Corrections and backwards watermarks create a baseline, never a negative usage day.
                for (a, b) in zip(sorted, sorted.dropFirst()) {
                    let unchanged = a.epoch == b.epoch && a.row.status == "available" && b.row.status == "available"
                        && a.effectiveAt == b.effectiveAt && a.row.percent(metric) == b.row.percent(metric)
                    guard a.epoch == b.epoch, a.row.status == "available", b.row.status == "available",
                          b.effectiveAt > a.effectiveAt, b.collectedAt.timeIntervalSince(a.collectedAt) <= 15 * 60,
                          let first = a.row.percent(metric), let last = b.row.percent(metric), last >= first else {
                        if !unchanged { baselineAt = b.collectedAt }
                        baselines[root, default: [:]][b.collectedAt] = baselineAt
                        continue
                    }
                    baselines[root, default: [:]][b.collectedAt] = baselineAt
                    let rows = (local[root] ?? []).filter {
                        $0.timestamp > a.effectiveAt && $0.timestamp <= b.effectiveAt
                            && $0.executionContext?.authenticationMode == .chatGPT
                            && ($0.accountKey == nil || $0.accountKey == accountKey)
                    }
                    intervals[root, default: []].append(Interval(start: a, end: b, percent: last - first, observations: rows, baselineAt: baselineAt))
                }
            }
            for day in history.days {
                for task in day.tasks {
                    guard let samples = byRoot[task.rootTaskID]?.sorted(by: { $0.collectedAt < $1.collectedAt }),
                          let latest = samples.last(where: { $0.row.status != "unavailable" }) else { continue }
                    guard let start = date(day.dateKey, calendar: calendar), let end = calendar.date(byAdding: .day, value: 1, to: start) else { continue }
                    let through = min(now, end)
                    let dayScope = samples.last(where: { $0.row.status != "unavailable" && $0.effectiveAt <= through }) ?? latest
                    let daySamples = samples.filter { $0.row.status != "unavailable" && $0.effectiveAt >= start && $0.effectiveAt < end }
                    if let native = daySamples.last, native.row.status == "available", let percent = native.row.percent(metric),
                       let birth = native.thread.earliestCreatedAt.flatMap(MetricFormatter.sourceDate), birth >= start, birth <= native.effectiveAt {
                        result[metric.rawValue, default: [:]][task.id] = DailyTaskQuotaValue(percent: percent, isExact: true,
                            updatedAt: native.collectedAt, help: "当前账户；同日新建任务的完整原生记录，包含子代理。数据截至 \(MetricFormatter.chineseAccountDate(native.effectiveAt))。")
                        continue
                    }
                    let observed = (intervals[task.rootTaskID] ?? []).filter {
                        $0.start.effectiveAt >= start && $0.end.effectiveAt <= through
                            && $0.baselineAt == baselines[task.rootTaskID]?[dayScope.collectedAt]
                    }
                    let measured = observed.reduce(0) { $0 + $1.percent }
                    let exactBoundary = observed.first.map { $0.start.effectiveAt == start } == true
                        && observed.last.map { $0.end.effectiveAt == through } == true
                        && observed.allSatisfy { $0.start.dataAsOf != nil && $0.end.dataAsOf != nil && $0.start.planType != nil }
                        && zip(observed, observed.dropFirst()).allSatisfy { pair in
                            pair.0.end.effectiveAt == pair.1.start.effectiveAt && pair.0.end.epoch == pair.1.start.epoch
                                && pair.0.end.row.percent(metric) == pair.1.start.row.percent(metric)
                        }
                    if exactBoundary, let last = observed.last {
                        result[metric.rawValue, default: [:]][task.id] = DailyTaskQuotaValue(percent: measured, isExact: true,
                            updatedAt: last.end.collectedAt, help: "当前账户；完整覆盖当日边界的原生快照差值。")
                        continue
                    }
                    // Retain the old calibrated-rate approach, using account-scoped native steps.
                    // No historical rollout record receives the currently logged-in account ID.
                    let rows = (local[task.rootTaskID] ?? []).filter { $0.timestamp >= start && $0.timestamp < through }
                    let canInfer = !rows.isEmpty && rows.allSatisfy {
                        $0.executionContext?.authenticationMode == .chatGPT && ($0.accountKey == nil || $0.accountKey == accountKey)
                    } && rows.reduce(Int64(0), { $0 + $1.tokenIncrement }) == task.tokens
                    if canInfer, let inferred = calibratedPercent(rows: rows, intervals: intervals, scope: dayScope) {
                        result[metric.rawValue, default: [:]][task.id] = DailyTaskQuotaValue(percent: max(measured, inferred), isExact: false,
                            updatedAt: latest.collectedAt, help: "当前账户原生差值校准本机逐轮 Token 的当日估算；账户归属未知的历史未被回填。并发、其他设备及模型变化可能影响精度。")
                    } else if let last = observed.last {
                        result[metric.rawValue, default: [:]][task.id] = DailyTaskQuotaValue(percent: measured, isExact: false,
                            updatedAt: last.end.collectedAt, help: "当前账户；当日已采样区间的增量，未完整覆盖全天。首次基线、缺测或延迟会影响精度。")
                    }
                }
            }
        }
        return result
    }
    private static func contextKey(_ row: LocalQuotaUsageObservation) -> String {
        let c = row.executionContext
        return "\(c?.modelID ?? "unknown")|\(c?.reasoningEffort ?? "unknown")|\(c?.serviceTier ?? "unknown")"
    }
    private static func calibratedPercent(rows: [LocalQuotaUsageObservation], intervals: [String: [Interval]], scope: NativeTaskQuotaSnapshot) -> Double? {
        guard scope.planType != nil else { return nil }
        var rates: [String: [Double]] = [:]
        for interval in intervals.values.flatMap({ $0 }) where interval.percent > 0 && interval.weight > 0
            && interval.end.planType == scope.planType && interval.end.row.usageSource == scope.row.usageSource {
            let keys = Set(interval.observations.map(contextKey))
            guard keys.count == 1, let key = keys.first else { continue }
            rates[key, default: []].append(interval.weight / interval.percent)
        }
        var total = 0.0
        for (key, group) in Dictionary(grouping: rows, by: contextKey) {
            guard let values = rates[key]?.filter({ $0.isFinite && $0 > 0 }).sorted(), !values.isEmpty else { return nil }
            let median = values[values.count / 2]
            let clean = values.count >= 5 ? values.filter { $0 >= median / 4 && $0 <= median * 4 } : values
            guard !clean.isEmpty else { return nil }
            total += group.reduce(0) { $0 + Double($1.tokenIncrement) } / clean[clean.count / 2]
        }
        return total.isFinite ? total : nil
    }
    private static func date(_ key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
    public static func batches(_ threads: [NativeThread]) -> [[NativeThread]] {
        var batches: [[NativeThread]] = []; var batch: [NativeThread] = []; var count = 0
        for thread in threads {
            let size = 1 + thread.descendantIDs.count
            guard size <= 1000 else { continue }
            if batch.count == 100 || count + size > 1000 { batches.append(batch); batch = []; count = 0 }
            batch.append(thread); count += size
        }
        if !batch.isEmpty { batches.append(batch) }
        return batches
    }
}
