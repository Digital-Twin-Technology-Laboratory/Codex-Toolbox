import Foundation

public enum UpdateCheckOrigin: Sendable, Equatable {
    case userInitiated
    case scheduled
}

public enum UpdateFailureAction: Sendable, Equatable {
    case retry(after: Duration)
    case preservePreviousState
    case present(String)
}

public enum UpdateRecoveryPolicy {
    public static func action(
        origin: UpdateCheckOrigin,
        completedRetries: Int,
        error: any Error
    ) -> UpdateFailureAction {
        guard NetworkRecoveryPolicy.failure(in: error) != nil else {
            return .present("无法完成更新检查，请稍后重试。")
        }

        switch origin {
        case .userInitiated:
            if let delay = NetworkRecoveryPolicy.interactiveRetryDelay(
                after: completedRetries
            ) {
                return .retry(after: delay)
            }
            return .present("暂时无法连接更新服务器，请检查网络或代理后重试。")
        case .scheduled:
            if let delay = NetworkRecoveryPolicy.backgroundRetryDelay(
                after: completedRetries
            ) {
                return .retry(after: delay)
            }
            return .preservePreviousState
        }
    }
}
