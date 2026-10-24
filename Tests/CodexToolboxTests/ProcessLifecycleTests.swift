import Darwin
import Foundation
import XCTest
@testable import CodexToolboxCore

final class ProcessLifecycleTests: XCTestCase, @unchecked Sendable {
    func testPartialEOFIsAProtocolFailureRatherThanTimeout() async throws {
        let fixture = try executable("IFS= read -r request\nprintf partial\n")
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let transport = ProcessCodexAppServerTransport(executableURL: fixture, timeout: 0.5)
        do {
            _ = try await transport.request(method: ProcessCodexAppServerTransport.allowedMethod)
            XCTFail("An incomplete final frame must fail")
        } catch let error as ResetCreditsError {
            guard case .protocolIncompatible = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testCancellingAppServerRequestStopsTheChild() async throws {
        let fixture = try executable("IFS= read -r request\nexec /bin/sleep 10\n")
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let transport = ProcessCodexAppServerTransport(executableURL: fixture, timeout: 2)
        let task = Task { try await transport.request(method: ProcessCodexAppServerTransport.allowedMethod) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
    }

    func testNativeCancellationKillsAnUncooperativeChildBeforeReturning() async throws {
        let fixture = try executable("trap '' TERM\nIFS= read -r request\nexec /bin/sleep 10\n")
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let client = ProcessNativeAnalyticsClient(executableURL: fixture)
        let task = Task { try await client.authentication(salt: String(repeating: "a", count: 64)) }
        let pid = try await waitForPID(fixture)
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancellation must propagate") }
        catch is CancellationError {}
        catch { XCTFail("Unexpected error: \(error)") }
        XCTAssertEqual(Darwin.kill(pid, 0), -1)
        XCTAssertEqual(errno, ESRCH)
    }

    func testNativeOutputAndInputAreBounded() async throws {
        let fixture = try executable("exec /usr/bin/head -c 16385 /dev/zero\n")
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let client = ProcessNativeAnalyticsClient(executableURL: fixture)
        do { _ = try await client.authentication(salt: String(repeating: "a", count: 64)); XCTFail("Oversized output must fail") }
        catch let error as NativeAnalyticsError { XCTAssertEqual(error, .invalidResponse) }
        let inputFixture = try executable("exec /bin/sleep 10\n")
        defer { try? FileManager.default.removeItem(at: inputFixture.deletingLastPathComponent()) }
        let inputClient = ProcessNativeAnalyticsClient(executableURL: inputFixture)
        let thread = NativeThread(id: UUID().uuidString, title: "", createdAt: nil,
                                  descendantIDs: (0..<4_000).map { _ in UUID().uuidString })
        do { _ = try await inputClient.taskUsage(salt: String(repeating: "a", count: 64), threads: [thread]); XCTFail("Oversized input must fail") }
        catch let error as NativeAnalyticsError { XCTAssertEqual(error, .invalidResponse) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: inputFixture.appendingPathExtension("pid").path))
    }

    func testNativeChildExitingWithoutReadingLargeInputCannotBlockOrSignalTheApp() async throws {
        let fixture = try executable("exec /bin/sleep 0.1\n")
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let client = ProcessNativeAnalyticsClient(executableURL: fixture)
        let thread = NativeThread(id: UUID().uuidString, title: "", createdAt: nil,
                                  descendantIDs: (0..<2_000).map { _ in UUID().uuidString })
        do { _ = try await client.taskUsage(salt: String(repeating: "a", count: 64), threads: [thread]); XCTFail("Closed input pipe must fail") }
        catch let error as NativeAnalyticsError { XCTAssertEqual(error, .invalidResponse) }
    }

    func testOneDeadlineIncludesBothHandshakeAndRead() async throws {
        let fixture = try executable("IFS= read -r request\n/bin/sleep 0.2\nprintf '%s\\n' '{\"id\":1,\"result\":{}}'\nIFS= read -r initialized\nIFS= read -r request\nexec /bin/sleep 10\n")
        defer { try? FileManager.default.removeItem(at: fixture.deletingLastPathComponent()) }
        let transport = ProcessCodexAppServerTransport(executableURL: fixture, timeout: 0.3)
        let start = ContinuousClock.now
        do { _ = try await transport.request(method: ProcessCodexAppServerTransport.allowedMethod); XCTFail("One request deadline must cover both phases") }
        catch let error as ResetCreditsError { XCTAssertEqual(error, .timeout) }
        XCTAssertLessThan(start.duration(to: .now), .seconds(0.6))
    }

    private func waitForPID(_ fixture: URL) async throws -> Int32 {
        for _ in 0..<100 {
            if let text = try? String(contentsOf: fixture.appendingPathExtension("pid"), encoding: .utf8),
               let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)) { return pid }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw CocoaError(.fileNoSuchFile)
    }

    private func executable(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("fixture")
        try Data(("#!/bin/sh\nprintf '%s\\n' \"$$\" > \"$0.pid\"\n" + body).utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
