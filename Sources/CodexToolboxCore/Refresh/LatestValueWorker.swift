import Foundation

@MainActor
public final class LatestValueWorker<Input: Sendable, Output: Sendable> {
    private struct Request {
        let id: UUID
        let input: Input
        let receive: @MainActor (Output) -> Void
    }

    private let operation: @Sendable (Input) async throws -> Output
    private let priority: TaskPriority
    private var acceptedID: UUID?
    private var pending: Request?
    private var worker: Task<Output, Error>?

    public init(
        priority: TaskPriority = .utility,
        operation: @escaping @Sendable (Input) async throws -> Output
    ) {
        self.priority = priority
        self.operation = operation
    }

    deinit { worker?.cancel() }

    public func submit(_ input: Input, receive: @escaping @MainActor (Output) -> Void) {
        let request = Request(id: UUID(), input: input, receive: receive)
        acceptedID = request.id
        if worker != nil {
            pending = request
            worker?.cancel()
        } else {
            start(request)
        }
    }

    public func cancel() {
        acceptedID = nil
        pending = nil
        worker?.cancel()
    }

    private func start(_ request: Request) {
        let input = request.input
        let operation = operation
        let running = Task.detached(priority: priority) {
            try Task.checkCancellation()
            let output = try await operation(input)
            try Task.checkCancellation()
            return output
        }
        worker = running
        Task { [weak self] in
            let result = await running.result
            guard let self else { return }
            self.worker = nil
            if self.acceptedID == request.id, case let .success(output) = result {
                request.receive(output)
            }
            if let next = self.pending {
                self.pending = nil
                self.start(next)
            }
        }
    }
}

public enum BackgroundWork {
    public static func run<Value: Sendable>(
        priority: TaskPriority = .utility,
        operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let worker = Task.detached(priority: priority) {
            try Task.checkCancellation()
            let value = try operation()
            try Task.checkCancellation()
            return value
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
