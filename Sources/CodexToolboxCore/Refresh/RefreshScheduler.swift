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
    private var configuredDuration: Duration?
    private var latestGeneration: UInt64 = 0
    private let sleep: @Sendable (Duration) async throws -> Void

    public init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    public func configureIfChanged(
        enabled: Bool,
        interval: RefreshInterval,
        generation: UInt64? = nil,
        operation: @escaping @Sendable () async -> Void
    ) {
        configureIfChanged(enabled: enabled, everyMinutes: interval.rawValue, generation: generation, operation: operation)
    }

    public func configureIfChanged(
        enabled: Bool,
        everyMinutes: Int,
        generation: UInt64? = nil,
        operation: @escaping @Sendable () async -> Void
    ) {
        configureIfChanged(enabled: enabled, every: .seconds(max(1, everyMinutes) * 60), generation: generation, operation: operation)
    }

    func configureIfChanged(
        enabled: Bool,
        every duration: Duration,
        generation: UInt64? = nil,
        operation: @escaping @Sendable () async -> Void
    ) {
        guard accepts(generation) else { return }
        guard enabled ? configuredDuration != duration : task != nil else { return }
        configure(enabled: enabled, every: duration, operation: operation)
    }

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
        configuredDuration = nil
        guard enabled else { return }
        configuredDuration = duration

        let sleep = sleep
        task = Task {
            while !Task.isCancelled {
                do {
                    try await sleep(duration)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await operation()
            }
        }
    }

    private func accepts(_ generation: UInt64?) -> Bool {
        guard let generation else { return true }
        guard generation >= latestGeneration else { return false }
        latestGeneration = generation
        return true
    }

    public func stop(generation: UInt64? = nil) {
        guard accepts(generation) else { return }
        task?.cancel()
        task = nil
        configuredDuration = nil
    }
}
