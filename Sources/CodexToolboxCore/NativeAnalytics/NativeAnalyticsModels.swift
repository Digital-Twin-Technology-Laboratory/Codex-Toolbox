import Foundation

public struct NativeThread: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let title: String
    public let createdAt: String?
    public let descendantIDs: [String]
    public let earliestCreatedAt: String?
    public var scopeKey: String { ([id] + descendantIDs.sorted()).joined(separator: "|") }
    public init(id: String, title: String, createdAt: String?, descendantIDs: [String], earliestCreatedAt: String? = nil) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.descendantIDs = descendantIDs
        self.earliestCreatedAt = earliestCreatedAt ?? (descendantIDs.isEmpty ? createdAt : nil)
    }
}
public struct NativeCatalogue: Sendable {
    public let threads: [NativeThread]
    public let eligibleCount: Int
    public let excludedCount: Int
    public let since: String
    public init(threads: [NativeThread], eligibleCount: Int, excludedCount: Int, since: String) {
        self.threads = threads; self.eligibleCount = eligibleCount; self.excludedCount = excludedCount; self.since = since
    }
}
public protocol NativeThreadReading: Sendable {
    func nativeCatalogue(now: Date) async throws -> NativeCatalogue
}

public enum AccountAuthentication: Equatable, Sendable {
    case chatGPT(accountKey: String), api, signedOut, unknown
    public var accountKey: String? { if case let .chatGPT(key) = self { key } else { nil } }
    public static func decode(_ data: Data) throws -> Self {
        struct Response: Decodable { let schemaVersion: Int; let authMode: String; let accountKey: String? }
        guard let value = try? JSONDecoder().decode(Response.self, from: data), value.schemaVersion == 2 else {
            throw NativeAnalyticsError.invalidResponse
        }
        if value.authMode == "chatGPT" {
            guard let key = value.accountKey, key.count == 64, key.allSatisfy(\.isHexDigit) else { throw NativeAnalyticsError.invalidResponse }
            return .chatGPT(accountKey: key)
        }
        guard value.accountKey == nil else { throw NativeAnalyticsError.invalidResponse }
        switch value.authMode {
        case "api": return .api
        case "signedOut": return .signedOut
        case "unknown": return .unknown
        default: throw NativeAnalyticsError.invalidResponse
        }
    }
}

/// A generation prevents an A -> B -> A transition from accepting an old A request.
public struct AccountSession: Sendable {
    public struct Ticket: Equatable, Sendable {
        public let accountKey: String
        fileprivate let generation: UInt64
    }
    public private(set) var authentication: AccountAuthentication = .unknown
    public private(set) var unattributedQuotaSince: Date?
    private var lastKnownAuthentication: AccountAuthentication?
    private var generation: UInt64 = 0
    public init() {}
    @discardableResult public mutating func observe(_ authentication: AccountAuthentication, at timestamp: Date = Date()) -> Bool {
        guard self.authentication != authentication else { return false }
        if authentication != .unknown {
            if let previous = lastKnownAuthentication, previous != authentication {
                unattributedQuotaSince = timestamp
            }
            lastKnownAuthentication = authentication
        }
        self.authentication = authentication
        generation &+= 1
        return true
    }
    public var ticket: Ticket? { authentication.accountKey.map { Ticket(accountKey: $0, generation: generation) } }
    public func accepts(_ ticket: Ticket) -> Bool { self.ticket == ticket }
}
