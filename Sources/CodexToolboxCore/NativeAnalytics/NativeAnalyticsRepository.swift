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
        guard let executableURL, FileManager.default.isExecutableFile(atPath: executableURL.path) else { throw NativeAnalyticsError.helperUnavailable }
        return try await Task.detached(priority: .utility) {
            let process = Process(); process.executableURL = executableURL
            let input = Pipe(); let output = Pipe()
            process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
            try process.run()
            defer { if process.isRunning { process.terminate() }; try? output.fileHandleForReading.close() }
            try input.fileHandleForWriting.write(contentsOf: body); try input.fileHandleForWriting.close()
            let deadline = Date().addingTimeInterval(timeout)
            let fd = output.fileHandleForReading.fileDescriptor
            var bytes = Data(); var chunk = [UInt8](repeating: 0, count: 8192)
            while Date() < deadline {
                var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let polled = Darwin.poll(&descriptor, 1, 250)
                if polled > 0 {
                    let count = Darwin.read(fd, &chunk, chunk.count)
                    if count == 0 { break }
                    if count > 0 { bytes.append(contentsOf: chunk.prefix(count)) }
                    if bytes.count > maximumBytes { throw NativeAnalyticsError.invalidResponse }
                }
                if Task.isCancelled { throw CancellationError() }
            }
            guard Date() < deadline else { throw NativeAnalyticsError.timeout }
            struct Failure: Decodable { let error: String }
            if let failure = try? JSONDecoder().decode(Failure.self, from: bytes) {
                throw NativeAnalyticsError(rawValue: failure.error) ?? .accountUnavailable
            }
            return bytes
        }.value
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
