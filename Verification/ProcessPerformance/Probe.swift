import Darwin
import Foundation

@main struct Probe {
    static func main() async throws {
        let executable = URL(fileURLWithPath: CommandLine.arguments[1])
        let transport = ProcessCodexAppServerTransport(executableURL: executable, timeout: 2)
        var before = rusage(), after = rusage()
        getrusage(RUSAGE_SELF, &before)
        let start = ContinuousClock.now
        var outcome = "success"
        do { _ = try await transport.request(method: ProcessCodexAppServerTransport.allowedMethod) }
        catch { outcome = String(describing: error) }
        let wall = start.duration(to: .now).components
        getrusage(RUSAGE_SELF, &after)
        func cpu(_ usage: rusage) -> Double {
            Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1e6
        }
        let output: [String: Any] = ["outcome": outcome,
            "wall_seconds": Double(wall.seconds) + Double(wall.attoseconds) / 1e18,
            "cpu_seconds": cpu(after) - cpu(before)]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
    }
}
