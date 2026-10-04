import Foundation

/// Optional published history never replaces current live metrics.
actor RadarHistoryLoader {
    private struct Cache: Codable {
        let data: Data
        let etag: String?
        let checkedAt: Date
    }
    private let session: URLSession
    private let endpoint: URL
    private let fileURL: URL
    private var cache: Cache?
    init(session: URLSession, endpoint: URL, fileURL: URL? = nil) {
        self.session = session; self.endpoint = endpoint
        self.fileURL = fileURL ?? ApplicationSupportLayout().currentDirectory.appendingPathComponent("radar-published-history-v1.json")
        if let data = try? Data(contentsOf: self.fileURL) { cache = try? JSONDecoder().decode(Cache.self, from: data) }
    }
    func merging(into current: [ModelBenchmark], sourceDate: String) async -> [ModelBenchmark] {
        if cache == nil || Date().timeIntervalSince(cache!.checkedAt) >= 6 * 3600 {
            var request = URLRequest(url: endpoint); request.timeoutInterval = 20
            request.setValue("CodexToolbox/\(AppMetadata.version)", forHTTPHeaderField: "User-Agent")
            request.setValue(cache?.etag, forHTTPHeaderField: "If-None-Match")
            if let (data, response) = try? await session.data(for: request), let http = response as? HTTPURLResponse {
                if http.statusCode == 304, let old = cache { cache = Cache(data: old.data, etag: old.etag, checkedAt: Date()) }
                else if http.statusCode == 200, data.count <= 12 * 1024 * 1024,
                        let decoded = try? JSONDecoder().decode(IntelligenceEfficiencyResponse.self, from: data),
                        (2...3).contains(decoded.schema), decoded.mode == "equal_latest_3" {
                    cache = Cache(data: data, etag: http.value(forHTTPHeaderField: "ETag"), checkedAt: Date())
                }
                if let cache { try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true); try? JSONEncoder().encode(cache).write(to: fileURL, options: .atomic) }
            }
        }
        guard let cache, let history = try? JSONDecoder().decode(IntelligenceEfficiencyResponse.self, from: cache.data),
              history.mode == "equal_latest_3", let currentDate = MetricFormatter.sourceDate(sourceDate) else { return current }
        let byID = Dictionary(uniqueKeysWithValues: history.benchmarks.map { ($0.id, $0) })
        return current.map { benchmark in
            guard let old = byID[benchmark.id] else { return benchmark }
            let records = (old.recentDays + [old.latest].compactMap { $0 }).filter { record in
                guard let date = MetricFormatter.sourceDate(record.date) else { return false }
                return date <= currentDate
            }.map { record in
                // Missing/different aggregation cannot be joined into a median cost curve.
                let compatible = record.priceAggregation != nil && record.priceAggregation == benchmark.latest?.priceAggregation
                return BenchmarkRecord(date: record.date, score: record.score, status: record.status, passed: record.passed, tasks: record.tasks, wallSeconds: record.wallSeconds, costUSD: compatible ? record.costUSD : nil, combinedCostIndex: nil, priceAggregation: record.priceAggregation, priceBasis: record.priceBasis, priceSamples: record.priceSamples, durationSamples: record.durationSamples)
            }
            return ModelBenchmark(id: benchmark.id, label: benchmark.label, model: benchmark.model, reasoningEffort: benchmark.reasoningEffort, latest: benchmark.latest, recentDays: records)
        }
    }
}
