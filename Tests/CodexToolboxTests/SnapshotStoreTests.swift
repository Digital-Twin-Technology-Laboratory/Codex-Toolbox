import Foundation
import XCTest
@testable import CodexToolboxCore

final class SnapshotStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let file = directory.appendingPathComponent("latest.json")
        let store = SnapshotStore(fileURL: file)
        let state = StoredRadarState(snapshot: fixtureSnapshot(), costHistory: [])

        try await store.save(state)
        let loaded = try await store.load()

        XCTAssertEqual(loaded, state)
        try? FileManager.default.removeItem(at: directory)
    }

    func testCostHistoryReplacesSameModelAndDate() {
        let old = CostHistoryPoint(modelID: "model", dateKey: "day", costUSD: 10, recordedAt: .distantPast)
        let latest = ModelBenchmark(
            id: "model",
            label: "Model",
            model: "model",
            reasoningEffort: "high",
            latest: BenchmarkRecord(
                date: "day",
                score: 100,
                status: nil,
                passed: nil,
                tasks: nil,
                wallSeconds: 100,
                costUSD: 12
            ),
            recentDays: []
        )

        let merged = CostHistoryBuilder.merging([old], benchmarks: [latest], recordedAt: Date())

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].costUSD, 12)
    }

    func testLoadMigratesLegacyStateWithoutDeletingRollbackFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let current = directory.appendingPathComponent("CodexToolbox/radar-latest.json")
        let legacy = directory.appendingPathComponent("ShowCodexIQ/latest.json")
        try FileManager.default.createDirectory(
            at: legacy.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let legacyStore = SnapshotStore(fileURL: legacy)
        let state = StoredRadarState(snapshot: fixtureSnapshot(), costHistory: [])
        try await legacyStore.save(state)

        let store = SnapshotStore(fileURL: current, legacyFileURL: legacy)
        let loaded = try await store.load()

        XCTAssertEqual(loaded, state)
        XCTAssertTrue(FileManager.default.fileExists(atPath: current.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
        try? FileManager.default.removeItem(at: directory)
    }

    private func fixtureSnapshot() -> RadarSnapshot {
        RadarSnapshot(
            schemaVersion: "2.0",
            sourceMonitoredAt: "2026-07-13T16:30:00+08:00",
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            benchmarks: [],
            validators: CacheValidators(etag: "etag", lastModified: "date")
        )
    }
}
