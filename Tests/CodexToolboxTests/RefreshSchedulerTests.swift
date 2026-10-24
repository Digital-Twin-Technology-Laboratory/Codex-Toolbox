import Foundation
import XCTest
@testable import CodexToolboxCore

final class RefreshSchedulerTests: XCTestCase {
    func testUnchangedConfigurationKeepsOriginalPendingDeadline() async throws {
        let sleeping = expectation(description: "Original deadline is waiting")
        let fired = expectation(description: "Original deadline fires")
        let clock = ControlledRefreshClock(onFirstSleep: { sleeping.fulfill() })
        let scheduler = RefreshScheduler(sleep: { try await clock.sleep($0) })
        await scheduler.configureIfChanged(enabled: true, every: .seconds(60)) {
            await scheduler.stop()
            fired.fulfill()
        }
        await fulfillment(of: [sleeping], timeout: 2)
        await scheduler.configureIfChanged(enabled: true, every: .seconds(60)) {
            XCTFail("An unchanged configuration replaced the original operation")
        }
        await clock.advance()
        await fulfillment(of: [fired], timeout: 2)
        let requests = await clock.requestCount
        XCTAssertEqual(requests, 1)
    }

    func testOldConfigurationCannotRestartAfterNewerSleepStop() async {
        let unexpected = expectation(description: "Old configuration remains stopped")
        unexpected.isInverted = true
        let scheduler = RefreshScheduler()
        await scheduler.stop(generation: 2)
        await scheduler.configureIfChanged(enabled: true, every: .milliseconds(1), generation: 1) {
            unexpected.fulfill()
        }
        await fulfillment(of: [unexpected], timeout: 0.05)
        await scheduler.stop(generation: 3)
    }

    func testOldSleepStopCannotCancelNewerWakeConfiguration() async {
        let sleeping = expectation(description: "Wake deadline is waiting")
        let fired = expectation(description: "Wake operation survives old stop")
        let clock = ControlledRefreshClock(onFirstSleep: { sleeping.fulfill() })
        let scheduler = RefreshScheduler(sleep: { try await clock.sleep($0) })
        await scheduler.configureIfChanged(enabled: true, every: .seconds(60), generation: 3) {
            await scheduler.stop(generation: 4)
            fired.fulfill()
        }
        await fulfillment(of: [sleeping], timeout: 2)
        await scheduler.stop(generation: 2)
        await clock.advance()
        await fulfillment(of: [fired], timeout: 2)
    }

    func testMissingRefreshIsImmediatelyDue() {
        XCTAssertTrue(RefreshPolicy.isRefreshDue(
            lastSuccessfulRefresh: nil,
            now: Date(),
            interval: .thirtyMinutes
        ))
    }

    func testRefreshBecomesDueAtSelectedInterval() {
        let last = Date(timeIntervalSince1970: 1_000)
        XCTAssertFalse(RefreshPolicy.isRefreshDue(
            lastSuccessfulRefresh: last,
            now: last.addingTimeInterval(1_799),
            interval: .thirtyMinutes
        ))
        XCTAssertTrue(RefreshPolicy.isRefreshDue(
            lastSuccessfulRefresh: last,
            now: last.addingTimeInterval(1_800),
            interval: .thirtyMinutes
        ))
    }

    func testStopCancelsPendingWorkAndConfigureRestartsIt() async throws {
        let scheduler = RefreshScheduler()
        let counter = RefreshCounter()

        await scheduler.configure(enabled: true, every: .milliseconds(40)) {
            await counter.increment()
        }
        await scheduler.stop()
        try await Task.sleep(for: .milliseconds(70))
        let stoppedCount = await counter.value()
        XCTAssertEqual(stoppedCount, 0)

        let restarted = expectation(description: "Restarted scheduler runs its operation")
        restarted.assertForOverFulfill = false
        await scheduler.configure(enabled: true, every: .milliseconds(10)) {
            await counter.increment()
            restarted.fulfill()
        }
        await fulfillment(of: [restarted], timeout: 5)
        await scheduler.stop()
        let restartedCount = await counter.value()
        XCTAssertGreaterThanOrEqual(restartedCount, 1)
    }
}

private actor ControlledRefreshClock {
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private(set) var requestCount = 0
    private let onFirstSleep: @Sendable () -> Void
    init(onFirstSleep: @escaping @Sendable () -> Void) { self.onFirstSleep = onFirstSleep }
    func sleep(_ duration: Duration) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                waiters[id] = continuation
                requestCount += 1
                if requestCount == 1 { onFirstSleep() }
            }
        } onCancel: { Task { await self.cancel(id) } }
    }
    func advance() {
        let pending = waiters.values
        waiters = [:]
        for waiter in pending { waiter.resume() }
    }
    private func cancel(_ id: UUID) { waiters.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
}

private actor RefreshCounter {
    private var count = 0

    func increment() { count += 1 }
    func value() -> Int { count }
}
