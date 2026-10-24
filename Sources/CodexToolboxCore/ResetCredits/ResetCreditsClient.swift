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
    case temporarilyUnavailable(String)
    case server(String)

    public var isTransient: Bool {
        switch self {
        case .timeout, .temporarilyUnavailable: true
        default: false
        }
    }

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
        case .temporarilyUnavailable:
            "Codex 账户服务暂时无法连接，请稍后重试。"
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
        for application in [workspaceApplication, URL(fileURLWithPath: "/Applications/ChatGPT.app"), URL(fileURLWithPath: "/Applications/Codex.app")].compactMap({ $0 }) {
            for relativePath in ["Contents/Resources/codex-cli/bin/codex", "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex", "Contents/Resources/codex"] {
                candidates.append(application.appendingPathComponent(relativePath))
            }
        }
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
        timeout: TimeInterval = 12
    ) {
        self.locator = locator
        explicitExecutableURL = nil
        self.timeout = max(0.1, timeout)
    }

    public init(executableURL: URL, timeout: TimeInterval = 12) {
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
        do {
            return try await BoundedProcess.run(
                executableURL: executableURL, arguments: ["app-server", "--listen", "stdio://"],
                timeout: timeout, maximumInputBytes: 16_384, maximumOutputBytes: 2 * 1024 * 1024
            ) { channel in
                try Self.send([
                    "id": 1, "method": "initialize",
                    "params": [
                        "clientInfo": ["name": "Codex Toolbox", "version": AppMetadata.version],
                        "capabilities": ["experimentalApi": true]
                    ]
                ], to: channel)
                _ = try Self.waitForResponse(id: 1, channel: channel)
                try Self.send(["method": "initialized"], to: channel)
                try Self.send(["id": 2, "method": method], to: channel)
                let response = try Self.waitForResponse(id: 2, channel: channel)
                guard let result = response["result"] as? [String: Any] else {
                    throw ResetCreditsError.protocolIncompatible("响应缺少 result 对象")
                }
                return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            }
        } catch let error as ProcessExecutionError {
            switch error {
            case let .launch(message): throw ResetCreditsError.launchFailed(message)
            case .timeout: throw ResetCreditsError.timeout
            case .invalidResponse, .inputLimit, .outputLimit:
                throw ResetCreditsError.protocolIncompatible("app-server 响应不完整或超过限制")
            }
        }
    }

    private static func send(_ object: [String: Any], to channel: ProcessChannel) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        try channel.send(data)
    }

    private static func waitForResponse(id: Int, channel: ProcessChannel) throws -> [String: Any] {
        do {
            while true {
                let line = try channel.readLine()
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      (message["id"] as? NSNumber)?.intValue == id else { continue }
                if let error = message["error"] {
                    let description = serverDescription(error)
                    if description.localizedCaseInsensitiveContains("login")
                        || description.localizedCaseInsensitiveContains("auth") {
                        throw ResetCreditsError.notLoggedIn(description)
                    }
                    if isTemporaryRateLimitFailure(error, description: description) {
                        throw ResetCreditsError.temporarilyUnavailable(description)
                    }
                    throw ResetCreditsError.server(description)
                }
                return message
            }
        } catch let error as ProcessExecutionError {
            if channel.errorText.localizedCaseInsensitiveContains("login")
                || channel.errorText.localizedCaseInsensitiveContains("auth") {
                throw ResetCreditsError.notLoggedIn(channel.errorText)
            }
            throw error
        }
    }

    private static func serverDescription(_ error: Any) -> String {
        guard let object = error as? [String: Any] else {
            return String(describing: error)
        }
        return [object["message"], object["data"]]
            .compactMap { $0 }
            .map { String(describing: $0) }
            .joined(separator: " ")
    }

    private static func isTemporaryRateLimitFailure(
        _ error: Any,
        description: String
    ) -> Bool {
        let code = ((error as? [String: Any])?["code"] as? NSNumber)?.intValue
        return code == -32603
            && description.localizedCaseInsensitiveContains("failed to fetch codex rate limits")
    }
}

public actor ResetCreditsClient: AccountRateLimitsReading {
    private let transport: any CodexAppServerRequesting
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(
        transport: any CodexAppServerRequesting = ProcessCodexAppServerTransport(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.transport = transport
        self.now = now
        self.sleep = sleep
    }

    public func readResetCredits() async throws -> ResetCreditsSnapshot {
        let data = try await requestWithRecovery()
        guard let result = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ResetCreditsError.protocolIncompatible("rateLimits/read 结果不是 JSON 对象")
        }
        let quotaWindows = try Self.quotaWindows(from: result["rateLimits"])
        let rateLimits = result["rateLimits"] as? [String: Any]
        let planType = (rateLimits?["planType"] as? String)
            ?? (rateLimits?["plan_type"] as? String)
            ?? (result["planType"] as? String)
        guard let container = result["rateLimitResetCredits"] as? [String: Any] else {
            return ResetCreditsSnapshot(
                availableCount: 0,
                credits: [],
                quotaWindows: quotaWindows,
                planType: planType,
                fetchedAt: now()
            )
        }
        let availableCount: Int
        if let number = container["availableCount"] as? NSNumber {
            guard let count = Int(exactly: number.doubleValue), count >= 0 else {
                throw ResetCreditsError.protocolIncompatible("重置额度数量无法表示")
            }
            availableCount = count
        } else {
            availableCount = 0
        }
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
            planType: planType,
            fetchedAt: now()
        )
    }

    private func requestWithRecovery() async throws -> Data {
        var completedRetries = 0
        while true {
            do {
                return try await transport.request(
                    method: ProcessCodexAppServerTransport.allowedMethod
                )
            } catch {
                guard let delay = Self.retryDelay(
                    after: completedRetries,
                    for: error
                ) else {
                    throw error
                }
                completedRetries += 1
                try await sleep(delay)
            }
        }
    }

    private static func retryDelay(
        after completedRetries: Int,
        for error: any Error
    ) -> Duration? {
        guard let resetError = error as? ResetCreditsError else { return nil }
        switch resetError {
        case .temporarilyUnavailable:
            let delays: [Duration] = [.seconds(2), .seconds(5)]
            return delays.indices.contains(completedRetries)
                ? delays[completedRetries]
                : nil
        case .timeout:
            return completedRetries == 0 ? .seconds(2) : nil
        default:
            return nil
        }
    }

    private static func quotaWindows(from value: Any?) throws -> [AccountQuotaWindow] {
        guard let container = value as? [String: Any] else { return [] }
        var seenDurations = Set<Int>()
        return try ["primary", "secondary"].compactMap { key in
            guard let row = container[key] as? [String: Any] else { return nil }
            if let rawDate = row["resetsAt"], !(rawDate is NSNull), date(rawDate) == nil {
                throw ResetCreditsError.protocolIncompatible("额度重置时间无法表示")
            }
            guard let number = row["windowDurationMins"] as? NSNumber else { return nil }
            guard let duration = Int(exactly: number.doubleValue) else {
                throw ResetCreditsError.protocolIncompatible("额度周期无法表示")
            }
            guard
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
            let date = Date(timeIntervalSince1970: number.doubleValue)
            return AccountQuotaWindow.isSupportedDate(date) ? date : nil
        }
        guard let string = value as? String else { return nil }
        guard let date = try? Date(string, strategy: .iso8601), AccountQuotaWindow.isSupportedDate(date) else { return nil }
        return date
    }
}
