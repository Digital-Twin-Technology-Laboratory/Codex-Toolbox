import Foundation

enum BoundedHTTPResponse {
    enum Failure: Error { case oversized, invalidResponse }

    static func data(for request: URLRequest, session: URLSession, maximumBytes: Int) async throws -> (Data, URLResponse) {
        let receiver = Receiver(maximumBytes: maximumBytes)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { receiver.start(request: request, session: session, continuation: $0) }
        } onCancel: { receiver.cancel() }
    }

    private final class Receiver: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private let maximumBytes: Int
        private var continuation: CheckedContinuation<(Data, URLResponse), any Error>?
        private var task: URLSessionDataTask?
        private var bytes = Data()
        private var response: URLResponse?
        private var cancelled = false
        private var finished = false

        init(maximumBytes: Int) { self.maximumBytes = maximumBytes }

        func start(request: URLRequest, session: URLSession, continuation: CheckedContinuation<(Data, URLResponse), any Error>) {
            let task = session.dataTask(with: request)
            task.delegate = self
            let shouldCancel = lock.withLock {
                self.continuation = continuation
                self.task = task
                return cancelled
            }
            if shouldCancel { finish(.failure(CancellationError())); task.cancel() }
            else { task.resume() }
        }

        func cancel() {
            let task = lock.withLock { cancelled = true; return self.task }
            if task != nil { finish(.failure(CancellationError())) }
            task?.cancel()
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void) {
            guard response.expectedContentLength <= Int64(maximumBytes) else {
                finish(.failure(Failure.oversized))
                completionHandler(.cancel)
                return
            }
            lock.withLock { self.response = response }
            completionHandler(.allow)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            let tooLarge = lock.withLock {
                guard !finished else { return false }
                guard data.count <= maximumBytes - bytes.count else { return true }
                bytes.append(data)
                return false
            }
            if tooLarge { finish(.failure(Failure.oversized)); dataTask.cancel() }
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
            let result: Result<(Data, URLResponse), any Error> = lock.withLock {
                if cancelled { return .failure(CancellationError()) }
                if let error { return .failure(error) }
                guard let response else { return .failure(Failure.invalidResponse) }
                return .success((bytes, response))
            }
            finish(result)
        }

        private func finish(_ result: Result<(Data, URLResponse), any Error>) {
            let continuation = lock.withLock {
                guard !finished else { return nil as CheckedContinuation<(Data, URLResponse), any Error>? }
                finished = true
                defer { self.continuation = nil; task = nil; bytes = Data() }
                return self.continuation
            }
            continuation?.resume(with: result)
        }
    }
}
