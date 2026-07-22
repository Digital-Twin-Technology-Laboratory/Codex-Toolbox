import AppKit
import Darwin
import Foundation

public enum ResetCreditsError: LocalizedError, Sendable, Equatable {
    case codexNotInstalled
    case disallowedMethod(String)
    case launchFailed(String)
    case timeout
    case notLoggedIn(String)
    case protocolIncompatible(String)
    case server(String)

    public var errorDescription: String? {
        switch self {
        case .codexNotInstalled:
            "未找到 Codex。请安装并登录 Codex 或 ChatGPT 后重试。"
        case let .disallowedMethod(method):
            "出于安全原因不允许调用 app-server 方法：\(method)"
        case .launchFailed:
            "无法启动 Codex app-server。请确认 Codex 可正常启动后重试。"
        case .timeout:
            "Codex app-server 响应超时，请确认 Codex 可正常启动后重试。"
        case .notLoggedIn:
            "Codex 尚未登录或登录已失效。请重新登录后重试。"
        case .protocolIncompatible:
            "当前 Codex app-server 协议不兼容。请更新 Codex 后重试。"
        case .server:
            "Codex app-server 返回错误。为保护账户凭据，详细信息已隐藏。"
        }
    }
}

public protocol CodexExecutableLocating: Sendable {
    func executableURL() async throws -> URL
}

public struct DefaultCodexExecutableLocator: CodexExecutableLocating, Sendable {
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func executableURL() async throws -> URL {
        let workspaceApplication = await MainActor.run {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.openai.codex")
        }
        var candidates: [URL] = []
        if let workspaceApplication {
            candidates.append(
                workspaceApplication.appendingPathComponent("Contents/Resources/codex")
            )
        }
        candidates.append(
            URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
        )
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map {
                URL(fileURLWithPath: String($0), isDirectory: true).appendingPathComponent("codex")
            })
        }
        if let match = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0.path) }) {
            return match.standardizedFileURL
        }
        throw ResetCreditsError.codexNotInstalled
    }
}

public protocol CodexAppServerRequesting: Sendable {
    func request(method: String) async throws -> Data
}

public actor ProcessCodexAppServerTransport: CodexAppServerRequesting {
    public static let allowedMethod = "account/rateLimits/read"

    private let locator: (any CodexExecutableLocating)?
    private let explicitExecutableURL: URL?
    private let timeout: TimeInterval

    public init(
        locator: any CodexExecutableLocating = DefaultCodexExecutableLocator(),
        timeout: TimeInterval = 8
    ) {
        self.locator = locator
        explicitExecutableURL = nil
        self.timeout = max(0.1, timeout)
    }

    public init(executableURL: URL, timeout: TimeInterval = 8) {
        locator = nil
        explicitExecutableURL = executableURL
        self.timeout = max(0.1, timeout)
    }

    public func request(method: String) async throws -> Data {
        guard method == Self.allowedMethod else {
            throw ResetCreditsError.disallowedMethod(method)
        }
        let executableURL: URL
        if let explicitExecutableURL {
            executableURL = explicitExecutableURL
        } else if let locator {
            executableURL = try await locator.executableURL()
        } else {
            throw ResetCreditsError.codexNotInstalled
        }
        let timeout = timeout
        return try await Task.detached(priority: .utility) {
            try Self.performRequest(
                executableURL: executableURL,
                method: method,
                timeout: timeout
            )
        }.value
    }

    private static func performRequest(
        executableURL: URL,
        method: String,
        timeout: TimeInterval
    ) throws -> Data {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = executableURL
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errorOutput
        do {
            try process.run()
        } catch {
            throw ResetCreditsError.launchFailed(error.localizedDescription)
        }

        defer {
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let stopDeadline = Date().addingTimeInterval(2)
            while process.isRunning, Date() < stopDeadline { usleep(20_000) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }

        let deadline = Date().addingTimeInterval(timeout)
        var stdoutBuffer = Data()
        var stderrText = ""
        try send([
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "Codex Toolbox", "version": AppMetadata.version],
                "capabilities": ["experimentalApi": true]
            ]
        ], to: input.fileHandleForWriting)
        _ = try waitForResponse(
            id: 1,
            process: process,
            outputFD: output.fileHandleForReading.fileDescriptor,
            errorFD: errorOutput.fileHandleForReading.fileDescriptor,
            deadline: deadline,
            stdoutBuffer: &stdoutBuffer,
            stderrText: &stderrText
        )
        try send(["method": "initialized"], to: input.fileHandleForWriting)
        try send(["id": 2, "method": method], to: input.fileHandleForWriting)
        let response = try waitForResponse(
            id: 2,
            process: process,
            outputFD: output.fileHandleForReading.fileDescriptor,
            errorFD: errorOutput.fileHandleForReading.fileDescriptor,
            deadline: deadline,
            stdoutBuffer: &stdoutBuffer,
            stderrText: &stderrText
        )
        guard let result = response["result"] as? [String: Any] else {
            throw ResetCreditsError.protocolIncompatible("响应缺少 result 对象")
        }
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }

    private static func send(_ object: [String: Any], to handle: FileHandle) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        try handle.write(contentsOf: data)
    }

    private static func waitForResponse(
        id: Int,
        process: Process,
        outputFD: Int32,
        errorFD: Int32,
        deadline: Date,
        stdoutBuffer: inout Data,
        stderrText: inout String
    ) throws -> [String: Any] {
        while Date() < deadline {
            while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
                let line = Data(stdoutBuffer[..<newline])
                stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (message["id"] as? NSNumber)?.intValue == id else { continue }
                if let error = message["error"] {
                    let description = String(describing: error)
                    if description.localizedCaseInsensitiveContains("login")
                        || description.localizedCaseInsensitiveContains("auth") {
                        throw ResetCreditsError.notLoggedIn(description)
                    }
                    throw ResetCreditsError.server(description)
                }
                return message
            }

            var descriptors = [
                pollfd(fd: outputFD, events: Int16(POLLIN), revents: 0),
                pollfd(fd: errorFD, events: Int16(POLLIN), revents: 0)
            ]
            let remaining = max(1, Int32(deadline.timeIntervalSinceNow * 1_000))
            let pollResult = descriptors.withUnsafeMutableBufferPointer {
                Darwin.poll($0.baseAddress, nfds_t($0.count), remaining)
            }
            if pollResult < 0, errno != EINTR {
                throw ResetCreditsError.protocolIncompatible(String(cString: strerror(errno)))
            }
            if pollResult == 0 { break }
            if descriptors[0].revents & Int16(POLLIN) != 0 {
                stdoutBuffer.append(try readAvailable(from: outputFD))
            }
            if descriptors[1].revents & Int16(POLLIN) != 0 {
                let errorData = try readAvailable(from: errorFD)
                stderrText += String(decoding: errorData, as: UTF8.self)
                if stderrText.count > 4_096 { stderrText = String(stderrText.suffix(4_096)) }
            }
            if !process.isRunning, stdoutBuffer.isEmpty {
                let detail = stderrText.isEmpty ? "app-server 已退出" : stderrText
                throw ResetCreditsError.protocolIncompatible(detail)
            }
        }
        if !stderrText.isEmpty,
           stderrText.localizedCaseInsensitiveContains("login")
            || stderrText.localizedCaseInsensitiveContains("auth") {
            throw ResetCreditsError.notLoggedIn(stderrText)
        }
        throw ResetCreditsError.timeout
    }

    private static func readAvailable(from descriptor: Int32) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 8_192)
        let count = bytes.withUnsafeMutableBytes {
            Darwin.read(descriptor, $0.baseAddress, $0.count)
        }
        if count < 0, errno != EAGAIN, errno != EINTR {
            throw ResetCreditsError.protocolIncompatible(String(cString: strerror(errno)))
        }
        return count > 0 ? Data(bytes.prefix(count)) : Data()
    }
}

public actor ResetCreditsClient: AccountRateLimitsReading {
    private let transport: any CodexAppServerRequesting
    private let now: @Sendable () -> Date

    public init(
        transport: any CodexAppServerRequesting = ProcessCodexAppServerTransport(),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.transport = transport
        self.now = now
    }

    public func readResetCredits() async throws -> ResetCreditsSnapshot {
        let data = try await transport.request(method: ProcessCodexAppServerTransport.allowedMethod)
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ResetCreditsError.protocolIncompatible("rateLimits/read 结果不是 JSON 对象")
        }
        let quotaWindows = Self.quotaWindows(from: result["rateLimits"])
        guard let container = result["rateLimitResetCredits"] as? [String: Any] else {
            return ResetCreditsSnapshot(
                availableCount: 0,
                credits: [],
                quotaWindows: quotaWindows,
                fetchedAt: now()
            )
        }
        let availableCount = (container["availableCount"] as? NSNumber)?.intValue ?? 0
        let rows = container["credits"] as? [[String: Any]] ?? []
        let credits = rows.enumerated().map { index, row in
            ResetCreditSummary(
                sequence: index + 1,
                status: row["status"] as? String ?? "unknown",
                grantedAt: Self.date(row["grantedAt"]),
                expiresAt: Self.date(row["expiresAt"])
            )
        }
        return ResetCreditsSnapshot(
            availableCount: availableCount,
            credits: credits,
            quotaWindows: quotaWindows,
            fetchedAt: now()
        )
    }

    private static func quotaWindows(from value: Any?) -> [AccountQuotaWindow] {
        guard let container = value as? [String: Any] else { return [] }
        var seenDurations = Set<Int>()
        return ["primary", "secondary"].compactMap { key in
            guard let row = container[key] as? [String: Any],
                  let duration = (row["windowDurationMins"] as? NSNumber)?.intValue,
                  duration > 0,
                  let usedPercent = (row["usedPercent"] as? NSNumber)?.doubleValue,
                  usedPercent.isFinite,
                  let resetsAt = date(row["resetsAt"]),
                  seenDurations.insert(duration).inserted else { return nil }
            return AccountQuotaWindow(
                durationMinutes: duration,
                usedPercent: usedPercent,
                resetsAt: resetsAt
            )
        }
    }

    private static func date(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        guard let string = value as? String else { return nil }
        return try? Date(string, strategy: .iso8601)
    }
}
