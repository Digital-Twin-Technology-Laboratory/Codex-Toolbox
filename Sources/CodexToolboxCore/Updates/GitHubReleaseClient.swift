import Foundation

public struct AppRelease: Codable, Equatable, Sendable {
    public let version: String
    public let pageURL: URL
    public let publishedAt: Date?

    public init(version: String, pageURL: URL, publishedAt: Date?) {
        self.version = version
        self.pageURL = pageURL
        self.publishedAt = publishedAt
    }

    public func isNewer(than currentVersion: String) -> Bool {
        guard let latest = SemanticVersion(version),
              let current = SemanticVersion(currentVersion) else { return false }
        return latest > current
    }
}

public protocol ReleaseChecking: Sendable {
    func latestRelease() async throws -> AppRelease
}

public enum ReleaseCheckError: LocalizedError, Sendable, Equatable {
    case invalidResponse
    case unavailable(Int)
    case invalidPayload

    public var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "GitHub 更新检查返回了无效响应。"
        case let .unavailable(statusCode):
            statusCode == 404
                ? "GitHub 上暂无正式 Release。"
                : "GitHub 更新检查暂不可用（HTTP \(statusCode)）。"
        case .invalidPayload:
            "GitHub Release 信息格式无法识别。"
        }
    }
}

public actor GitHubReleaseClient: ReleaseChecking {
    private struct Payload: Decodable {
        let tagName: String
        let htmlURL: URL
        let publishedAt: Date?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case publishedAt = "published_at"
        }
    }

    private let session: URLSession
    private let endpoint: URL
    private let releasePageEndpoint: URL

    public init(
        session: URLSession = .shared,
        endpoint: URL = AppMetadata.latestReleaseAPIURL,
        releasePageEndpoint: URL = AppMetadata.latestReleasePageURL
    ) {
        self.session = session
        self.endpoint = endpoint
        self.releasePageEndpoint = releasePageEndpoint
    }

    public func latestRelease() async throws -> AppRelease {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 8
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Codex-Toolbox/\(AppMetadata.version)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw ReleaseCheckError.invalidResponse
        }
        if response.statusCode == 403 || response.statusCode == 429 {
            return try await latestReleaseFromWebRedirect()
        }
        guard response.statusCode == 200 else {
            throw ReleaseCheckError.unavailable(response.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let payload = try? decoder.decode(Payload.self, from: data) else {
            throw ReleaseCheckError.invalidPayload
        }
        return AppRelease(
            version: payload.tagName.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            pageURL: payload.htmlURL,
            publishedAt: payload.publishedAt
        )
    }

    /// GitHub's unauthenticated REST quota is intentionally small. The public
    /// `/releases/latest` page redirects to the latest non-prerelease tag and
    /// therefore provides a credential-free fallback without scraping HTML.
    private func latestReleaseFromWebRedirect() async throws -> AppRelease {
        var request = URLRequest(url: releasePageEndpoint)
        request.timeoutInterval = 8
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("Codex-Toolbox/\(AppMetadata.version)", forHTTPHeaderField: "User-Agent")

        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              let finalURL = response.url else {
            throw ReleaseCheckError.invalidResponse
        }

        let components = finalURL.pathComponents
        guard let tagIndex = components.firstIndex(of: "tag"),
              components.indices.contains(tagIndex + 1) else {
            throw ReleaseCheckError.unavailable(404)
        }
        let tag = components[tagIndex + 1].removingPercentEncoding ?? components[tagIndex + 1]
        let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        guard SemanticVersion(version) != nil else {
            throw ReleaseCheckError.invalidPayload
        }
        return AppRelease(version: version, pageURL: finalURL, publishedAt: nil)
    }
}

private struct SemanticVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int
    let prerelease: [String]

    init?(_ rawValue: String) {
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        // Preserve empty components so malformed metadata cannot disappear during parsing.
        let buildParts = normalized.split(separator: "+", maxSplits: 1, omittingEmptySubsequences: false)
        guard let withoutBuild = buildParts.first, !withoutBuild.isEmpty,
              buildParts.count == 1 || !buildParts[1].isEmpty else { return nil }
        let parts = withoutBuild.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        guard let corePart = parts.first,
              parts.count == 1 || !parts[1].isEmpty else { return nil }
        let components = corePart.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.utf8.allSatisfy { (48...57).contains($0) } }) else { return nil }
        let core = components.compactMap { Int($0) }
        guard core.count == 3 else { return nil }
        major = core[0]
        minor = core[1]
        patch = core[2]
        prerelease = parts.count == 2 ? parts[1].split(separator: ".").map(String.init) : []
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let lhsCore = [lhs.major, lhs.minor, lhs.patch]
        let rhsCore = [rhs.major, rhs.minor, rhs.patch]
        if lhsCore != rhsCore { return lhsCore.lexicographicallyPrecedes(rhsCore) }
        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty }

        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (Int(left), Int(right)) {
            case let (leftNumber?, rightNumber?): return leftNumber < rightNumber
            case (_?, nil): return true
            case (nil, _?): return false
            default: return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }
}
