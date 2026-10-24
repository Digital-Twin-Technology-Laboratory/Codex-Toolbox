import Darwin
import Foundation

enum ProcessExecutionError: Error {
    case launch(String), timeout, invalidResponse, inputLimit, outputLimit
}

/// Owns the child and all of its pipes for one bounded request.
enum BoundedProcess {
    static func run(
        executableURL: URL, arguments: [String] = [], timeout: TimeInterval,
        maximumInputBytes: Int, maximumOutputBytes: Int,
        operation: @escaping @Sendable (ProcessChannel) throws -> Data
    ) async throws -> Data {
        let cancellation = ProcessCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        try cancellation.check()
                        let channel = try ProcessChannel(
                            executableURL: executableURL, arguments: arguments,
                            timeout: timeout, maximumInputBytes: maximumInputBytes,
                            maximumOutputBytes: maximumOutputBytes, cancellation: cancellation
                        )
                        let result = Result {
                            let data = try operation(channel)
                            try cancellation.check()
                            return data
                        }
                        channel.close()
                        continuation.resume(with: result)
                    } catch { continuation.resume(throwing: error) }
                }
            }
        } onCancel: { cancellation.cancel() }
    }
}

private final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.withLock { cancelled = true } }
    func check() throws {
        if lock.withLock({ cancelled }) { throw CancellationError() }
    }
}

final class ProcessChannel {
    private let process = Process()
    private let input = Pipe(), output = Pipe(), errors = Pipe()
    private let cancellation: ProcessCancellation
    private let deadline: ContinuousClock.Instant
    private let maximumInputBytes: Int, maximumOutputBytes: Int
    private var inputBytes = 0, outputBytes = 0, errorBytes = 0
    private var outputEOF = false, errorEOF = false, inputClosed = false
    private var buffer = Data()
    private(set) var errorText = ""

    fileprivate init(
        executableURL: URL, arguments: [String], timeout: TimeInterval,
        maximumInputBytes: Int, maximumOutputBytes: Int, cancellation: ProcessCancellation
    ) throws {
        self.cancellation = cancellation
        self.maximumInputBytes = maximumInputBytes
        self.maximumOutputBytes = maximumOutputBytes
        deadline = ContinuousClock.now.advanced(by: .seconds(max(0.1, timeout)))
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        do { try process.run() }
        catch { throw ProcessExecutionError.launch(error.localizedDescription) }
        try? input.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        for fd in [input.fileHandleForWriting.fileDescriptor, output.fileHandleForReading.fileDescriptor, errors.fileHandleForReading.fileDescriptor] {
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        }
        // A child may exit while a request is being written. Never deliver SIGPIPE to the app.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
    }

    func send(_ data: Data) throws {
        guard !inputClosed, data.count <= maximumInputBytes - inputBytes else { throw ProcessExecutionError.inputLimit }
        inputBytes += data.count
        var offset = 0
        while offset < data.count {
            try check()
            let count = data.withUnsafeBytes { bytes in
                Darwin.write(input.fileHandleForWriting.fileDescriptor, bytes.baseAddress!.advanced(by: offset), data.count - offset)
            }
            if count > 0 { offset += count }
            else if count < 0 && errno != EAGAIN && errno != EINTR { throw ProcessExecutionError.invalidResponse }
            else { try pump(waitsForInput: true) }
        }
    }

    func closeInput() {
        guard !inputClosed else { return }
        inputClosed = true
        try? input.fileHandleForWriting.close()
    }

    func readLine() throws -> Data {
        while true {
            try check()
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = Data(buffer[..<newline])
                buffer.removeSubrange(buffer.startIndex...newline)
                return line
            }
            guard !outputEOF else { throw ProcessExecutionError.invalidResponse }
            try pump()
        }
    }

    func readToEnd() throws -> Data {
        while !outputEOF { try pump() }
        try check()
        return buffer
    }

    func close() {
        closeInput()
        if process.isRunning {
            process.terminate()
            let grace = ContinuousClock.now.advanced(by: .milliseconds(150))
            while process.isRunning, ContinuousClock.now < grace { usleep(5_000) }
            if process.isRunning { Darwin.kill(process.processIdentifier, SIGKILL) }
        }
        process.waitUntilExit()
        try? output.fileHandleForReading.close()
        try? errors.fileHandleForReading.close()
    }

    private func check() throws {
        try cancellation.check()
        guard ContinuousClock.now < deadline else { throw ProcessExecutionError.timeout }
    }

    private func pump(waitsForInput: Bool = false) throws {
        try check()
        var descriptors = [
            pollfd(fd: outputEOF ? -1 : output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0),
            pollfd(fd: errorEOF ? -1 : errors.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0),
            pollfd(fd: waitsForInput ? input.fileHandleForWriting.fileDescriptor : -1, events: Int16(POLLOUT), revents: 0)
        ]
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let milliseconds = Double(remaining.seconds) * 1_000 + Double(remaining.attoseconds) / 1e15
        let timeout = Int32(max(1, min(50, milliseconds)))
        let result = descriptors.withUnsafeMutableBufferPointer { Darwin.poll($0.baseAddress, nfds_t($0.count), timeout) }
        if result < 0 {
            if errno == EINTR { return }
            throw ProcessExecutionError.invalidResponse
        }
        for index in 0..<2 where descriptors[index].revents != 0 {
            if descriptors[index].revents & Int16(POLLNVAL) != 0 { throw ProcessExecutionError.invalidResponse }
            try drain(fd: descriptors[index].fd, isError: index == 1)
            if descriptors[index].revents & Int16(POLLERR) != 0 { throw ProcessExecutionError.invalidResponse }
            if descriptors[index].revents & Int16(POLLHUP) != 0 {
                if index == 0 { outputEOF = true } else { errorEOF = true }
            }
        }
        if waitsForInput, descriptors[2].revents & Int16(POLLERR | POLLHUP | POLLNVAL) != 0 {
            throw ProcessExecutionError.invalidResponse
        }
    }

    private func drain(fd: Int32, isError: Bool) throws {
        var bytes = [UInt8](repeating: 0, count: 8_192)
        while true {
            try check()
            let count = Darwin.read(fd, &bytes, bytes.count)
            if count == 0 {
                if isError { errorEOF = true } else { outputEOF = true }
                return
            }
            if count < 0 {
                if errno == EAGAIN { return }
                if errno == EINTR { continue }
                throw ProcessExecutionError.invalidResponse
            }
            if isError {
                errorBytes += count
                guard errorBytes <= 65_536 else { throw ProcessExecutionError.outputLimit }
                errorText += String(decoding: bytes.prefix(count), as: UTF8.self)
                if errorText.count > 4_096 { errorText = String(errorText.suffix(4_096)) }
            } else {
                guard count <= maximumOutputBytes - outputBytes else { throw ProcessExecutionError.outputLimit }
                outputBytes += count
                buffer.append(contentsOf: bytes.prefix(count))
            }
        }
    }
}
