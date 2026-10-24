import Foundation
import Darwin

public enum NativeAnalyticsError: String, Error, LocalizedError, Sendable {
    case helperUnavailable, invalidResponse, signInRequired, accountUnavailable, accountChanged, timeout, unsupportedConfiguration
    public var errorDescription: String? {
        switch self {
        case .helperUnavailable: "原生分析读取组件不可用。"
        case .invalidResponse: "原生分析返回格式不受支持。"
        case .signInRequired: "请先在 Codex 中登录 ChatGPT 账户。"
        case .accountChanged: "账户已切换，正在重新读取。"
        case .accountUnavailable: "原生分析暂不可用，保留已验证账户的缓存。"
        case .timeout: "原生分析检查超时。"
        case .unsupportedConfiguration: "Codex 登录配置无法读取。"
        }
    }
}
public protocol NativeAuthenticationReading: Sendable {
    func authentication(salt: String) async throws -> AccountAuthentication
}
public protocol NativeTaskUsageReading: Sendable {
    func taskUsage(salt: String, threads: [NativeThread]) async throws -> NativeTaskUsageReport
}
public struct ProcessNativeAnalyticsClient: NativeAuthenticationReading, NativeTaskUsageReading, Sendable {
    private let executableURL: URL?
    public init(executableURL: URL? = nil) {
        self.executableURL = executableURL ?? Bundle.main.url(forAuxiliaryExecutable: "toolbox-native-analytics")
    }
    public func authentication(salt: String) async throws -> AccountAuthentication {
        try AccountAuthentication.decode(await request(body: JSONSerialization.data(withJSONObject: ["command": "identity", "salt": salt]), timeout: 15, maximumBytes: 16384))
    }
    public func taskUsage(salt: String, threads: [NativeThread]) async throws -> NativeTaskUsageReport {
        let rows: [[String: Any]] = threads.map {
            ["id": $0.id, "createdAt": $0.createdAt as Any? ?? NSNull(), "descendantIds": $0.descendantIDs]
        }
        let body = try JSONSerialization.data(withJSONObject: ["command": "taskUsage", "salt": salt, "threads": rows])
        return try NativeTaskUsageReport.decode(await request(body: body, timeout: 40, maximumBytes: 2 * 1024 * 1024))
    }
    private func request(body: Data, timeout: TimeInterval, maximumBytes: Int) async throws -> Data {
        guard body.count <= 131_072 else { throw NativeAnalyticsError.invalidResponse }
        guard let executableURL, FileManager.default.isExecutableFile(atPath: executableURL.path) else { throw NativeAnalyticsError.helperUnavailable }
        let bytes: Data
        do {
            bytes = try await BoundedProcess.run(
                executableURL: executableURL, timeout: timeout,
                maximumInputBytes: 131_072, maximumOutputBytes: maximumBytes
            ) { channel in
                try channel.send(body)
                channel.closeInput()
                return try channel.readToEnd()
            }
        } catch let error as ProcessExecutionError {
            switch error {
            case .launch: throw NativeAnalyticsError.helperUnavailable
            case .timeout: throw NativeAnalyticsError.timeout
            case .invalidResponse, .inputLimit, .outputLimit: throw NativeAnalyticsError.invalidResponse
            }
        }
        struct Failure: Decodable { let error: String }
        if let failure = try? JSONDecoder().decode(Failure.self, from: bytes) {
            throw NativeAnalyticsError(rawValue: failure.error) ?? .accountUnavailable
        }
        return bytes
    }
}
public actor AccountIdentityRepository {
    private let client: any NativeAuthenticationReading
    private let salt: String
    public init(client: any NativeAuthenticationReading = ProcessNativeAnalyticsClient(), directory: URL? = nil) {
        self.client = client
        let directory = directory ?? ApplicationSupportLayout().currentDirectory.appendingPathComponent("native-analytics", isDirectory: true)
        let saltURL = directory.appendingPathComponent("installation-salt")
        if let value = try? String(contentsOf: saltURL, encoding: .utf8), value.count == 64, value.allSatisfy(\.isHexDigit) { salt = value }
        else {
            salt = (UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").lowercased()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? salt.write(to: saltURL, atomically: true, encoding: .utf8)
        }
    }
    public func authentication() async throws -> AccountAuthentication {
        try await client.authentication(salt: salt)
    }
    public func taskUsage(threads: [NativeThread]) async throws -> NativeTaskUsageReport {
        guard let reader = client as? any NativeTaskUsageReading else { throw NativeAnalyticsError.helperUnavailable }
        return try await reader.taskUsage(salt: salt, threads: threads)
    }
}
