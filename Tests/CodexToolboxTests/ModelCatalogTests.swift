import Foundation
import XCTest
@testable import CodexToolboxCore

final class ModelCatalogTests: XCTestCase {
    func testPublishedSnapshotGroupsAllCurrentModelsInCatalogOrder() throws {
        let data = try Data(contentsOf: try fixtureURL("intelligence-efficiency-v2.json"))
        let response = try JSONDecoder().decode(IntelligenceEfficiencyResponse.self, from: data)

        let groups = ModelCatalog.grouped(response.benchmarks)

        XCTAssertEqual(groups.map(\.title), [
            "5.5",
            "GPT-5.6 Sol",
            "GPT-5.6 Terra",
            "GPT-5.6 Luna",
            "DeepSeek V4 Flash"
        ])
        XCTAssertEqual(groups.flatMap(\.models).count, 21)
        XCTAssertEqual(
            groups.first { $0.id == "openai-gpt-5.6-sol" }?.models.map(\.reasoningEffort),
            ["low", "medium", "high", "xhigh", "max", "ultra"]
        )
        XCTAssertEqual(
            groups.first { $0.id == "deepseek-v4-flash" }?.models.map(\.reasoningEffort),
            ["high", "max"]
        )
    }

    func testDeepSeekStableAndPreviewVariantsAreSeparatedWithinTheirActualFamilies() {
        let models = [
            benchmark(id: "flash-preview-ultra", model: "deepseek-v4-flash-preview", effort: "ultra"),
            benchmark(id: "pro-preview-high", model: "deepseek-v4-pro-preview", effort: "high"),
            benchmark(id: "pro-max", model: "deepseek-v4-pro", effort: "max"),
            benchmark(id: "flash-high", model: "deepseek-v4-flash", effort: "high")
        ]

        let groups = ModelCatalog.grouped(models)

        XCTAssertEqual(groups.map(\.title), ["DeepSeek V4 Flash", "DeepSeek V4 Pro"])
        XCTAssertEqual(groups[0].models.map(\.catalogEntry.rowTitle), [
            "正式版 · high",
            "Preview · ultra"
        ])
        XCTAssertEqual(groups[1].models.map(\.catalogEntry.rowTitle), [
            "正式版 · max",
            "Preview · high"
        ])
        XCTAssertEqual(groups[0].models.last?.catalogEntry.displayLabel, "DeepSeek V4 Flash Preview ultra")
    }

    func testUnknownModelsRemainReadableInOtherModelsWithoutInventingFamilies() throws {
        let unknown = benchmark(id: "future_model_ultra", model: "future-model", effort: "ultra")
        let group = try XCTUnwrap(ModelCatalog.grouped([unknown]).first)

        XCTAssertEqual(group.title, "其他模型")
        XCTAssertEqual(group.models.first?.catalogEntry.displayLabel, "future-model ultra")
        XCTAssertEqual(group.models.first?.catalogEntry.rowTitle, "ultra")
    }

    private func benchmark(id: String, model: String, effort: String) -> ModelBenchmark {
        ModelBenchmark(
            id: id,
            label: "source label",
            model: model,
            reasoningEffort: effort,
            latest: nil,
            recentDays: []
        )
    }

    private func fixtureURL(_ name: String) throws -> URL {
        #if SWIFT_PACKAGE
        let url = Bundle.module.url(
            forResource: name,
            withExtension: nil,
            subdirectory: "Fixtures"
        )
        #else
        let url = Bundle(for: Self.self).url(forResource: name, withExtension: nil)
        #endif
        guard let url else {
            throw CocoaError(.fileNoSuchFile)
        }
        return url
    }
}
