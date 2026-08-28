import Foundation

public enum TransientNetworkFailure: Sendable, Equatable {
    case offline
    case connectionLost
    case timedOut
    case cannotReachHost
}

public enum NetworkRecoveryPolicy {
    public static func failure(in error: any Error) -> TransientNetworkFailure? {
        var current: NSError? = error as NSError
        var visited = Set<ObjectIdentifier>()

        while let candidate = current {
            guard visited.insert(ObjectIdentifier(candidate)).inserted else { break }

            if candidate.domain == NSURLErrorDomain {
                let code = URLError.Code(rawValue: candidate.code)
                switch code {
                case .notConnectedToInternet:
                    return .offline
                case .networkConnectionLost:
                    return .connectionLost
                case .timedOut:
                    return .timedOut
                case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                    return .cannotReachHost
                default:
                    break
                }
            }

            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return nil
    }

    public static func interactiveRetryDelay(after completedRetries: Int) -> Duration? {
        let delays: [Duration] = [.seconds(2), .seconds(5)]
        return delays.indices.contains(completedRetries) ? delays[completedRetries] : nil
    }

    public static func backgroundRetryDelay(after completedRetries: Int) -> Duration? {
        completedRetries == 0 ? .seconds(30) : nil
    }
}
