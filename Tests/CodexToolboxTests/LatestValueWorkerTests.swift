import Foundation
import XCTest
@testable import CodexToolboxCore

final class LatestValueWorkerTests: XCTestCase {
    @MainActor
    func testReplacementActuallyCancelsRunningOperation() async {
        let started = expectation(description: "First computation started")
        let cancelled = expectation(description: "Running operation observed cancellation")
        let latest = expectation(description: "Replacement finished")
        let worker = LatestValueWorker<Int, Int> { value in
            if value == 1 {
                started.fulfill()
                do { try await Task.sleep(for: .seconds(30)) }
                catch { cancelled.fulfill(); throw error }
            }
            return value
        }
        var published: [Int] = []
        worker.submit(1) { published.append($0) }
        await fulfillment(of: [started], timeout: 2)
        worker.submit(2) { published.append($0); latest.fulfill() }
        await fulfillment(of: [cancelled, latest], timeout: 2)
        XCTAssertEqual(published, [2])
    }

    @MainActor
    func testCancelDropsPendingRequestAndAlreadyCompletedOldResult() async {
        let gate = WorkerGate()
        let started = expectation(description: "First computation started")
        let latest = expectation(description: "New session finished")
        let worker = LatestValueWorker<Int, Int> { value in
            await gate.began(value)
            if value == 1 { started.fulfill(); await gate.wait() }
            await gate.ended()
            return value
        }
        var published: [Int] = []
        worker.submit(1) { published.append($0) }
        await fulfillment(of: [started], timeout: 2)
        worker.submit(2) { published.append($0) }
        worker.cancel()
        worker.submit(3) { published.append($0); latest.fulfill() }
        await gate.release()
        await fulfillment(of: [latest], timeout: 2)
        XCTAssertEqual(published, [3])
        let values = await gate.values()
        XCTAssertEqual(values.inputs, [1, 3])
        XCTAssertEqual(values.maximumActive, 1)
    }

    @MainActor
    func testReplacesPendingInputAndNeverPublishesSupersededWork() async {
        let gate = WorkerGate()
        let started = expectation(description: "First computation started")
        let finished = expectation(description: "Latest computation published")
        let worker = LatestValueWorker<Int, Int> { value in
            await gate.began(value)
            if value == 1 {
                started.fulfill()
                await gate.wait()
            }
            await gate.ended()
            return value
        }
        var published: [Int] = []
        worker.submit(1) { published.append($0) }
        await fulfillment(of: [started], timeout: 2)
        worker.submit(2) { published.append($0) }
        worker.submit(3) { published.append($0); finished.fulfill() }
        await gate.release()
        await fulfillment(of: [finished], timeout: 2)
        XCTAssertEqual(published, [3])
        let values = await gate.values()
        XCTAssertEqual(values.inputs, [1, 3])
        XCTAssertEqual(values.maximumActive, 1)
    }
}

private actor WorkerGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false
    private var active = 0
    private var maximumActive = 0
    private var inputs: [Int] = []
    func began(_ input: Int) { inputs.append(input); active += 1; maximumActive = max(maximumActive, active) }
    func ended() { active -= 1 }
    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
    func values() -> (inputs: [Int], maximumActive: Int) { (inputs, maximumActive) }
}
