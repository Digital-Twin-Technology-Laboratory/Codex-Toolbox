import Foundation

public enum RefreshPolicy {
    public static func isRefreshDue(
        lastSuccessfulRefresh: Date?,
        now: Date,
        interval: RefreshInterval
    ) -> Bool {
        guard let lastSuccessfulRefresh else { return true }
        return now.timeIntervalSince(lastSuccessfulRefresh) >= Double(interval.rawValue * 60)
    }
}

public actor RefreshScheduler {
    private var task: Task<Void, Never>?

    public init() {}

    public func configure(
        enabled: Bool,
        interval: RefreshInterval,
        operation: @escaping @Sendable () async -> Void
    ) {
        configure(
            enabled: enabled,
            everyMinutes: interval.rawValue,
            operation: operation
        )
    }

    public func configure(
        enabled: Bool,
        everyMinutes: Int,
        operation: @escaping @Sendable () async -> Void
    ) {
        configure(
            enabled: enabled,
            every: .seconds(max(1, everyMinutes) * 60),
            operation: operation
        )
    }

    func configure(
        enabled: Bool,
        every duration: Duration,
        operation: @escaping @Sendable () async -> Void
    ) {
        task?.cancel()
        task = nil
        guard enabled else { return }

        task = Task {
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: duration)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await operation()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
