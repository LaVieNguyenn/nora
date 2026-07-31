import Foundation
import Combine

/// Keeps a long-lived `status --watch` process alive and republishes each
/// newline-delimited JSON frame it emits.
final class StatusStream: ObservableObject {
    @Published private(set) var snapshot: StatusSnapshot?
    @Published private(set) var isRunning = false
    @Published private(set) var lastError: String?

    /// Rolling history for the sparklines. Bounded so a long-running menubar
    /// session cannot grow this without limit.
    @Published private(set) var cpuHistory: [Double] = []
    @Published private(set) var ramHistory: [Double] = []
    private let historyLimit = 60

    private var process: Process?
    private var stdoutPipe: Pipe?
    /// Restart backoff, so a collector that dies instantly is not respawned in
    /// a tight loop.
    private var restartDelay: TimeInterval = 1

    private(set) var currentInterval = "2s"

    func start(interval: String = "2s") {
        guard process == nil else { return }
        currentInterval = interval
        guard let binary = NoraLocator.statusBinary else {
            lastError = NoraLocator.setupProblem ?? "Không tìm thấy status-go"
            return
        }

        let process = Process()
        process.executableURL = binary
        process.arguments = ["--watch", "--interval", interval]
        process.standardInput = FileHandle.nullDevice

        var env = Foundation.ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        process.environment = env

        let pipe = Pipe()
        stdoutPipe = pipe
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let lineBuffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            let lines = lineBuffer.append(chunk)
            guard !lines.isEmpty else { return }

            // Decode off the main actor; only the decoded frame crosses over.
            let frames = lines.compactMap { line -> StatusSnapshot? in
                guard let data = line.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(StatusSnapshot.self, from: data)
            }
            guard let latest = frames.last else { return }

            DispatchQueue.main.async { [weak self] in self?.apply(latest) }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in self?.handleTermination() }
        }

        do {
            try process.run()
            self.process = process
            isRunning = true
            lastError = nil
            restartDelay = 1
        } catch {
            lastError = "Không chạy được status-go: \(error.localizedDescription)"
        }
    }

    /// Restart the collector at a different cadence, skipping the work when it
    /// already runs at that rate.
    func setInterval(_ interval: String) {
        guard interval != currentInterval else { return }
        stop()
        start(interval: interval)
    }

    func stop() {
        if let process, process.isRunning {
            process.terminationHandler = nil
            process.terminate()
        }
        // Disarm the read source. Left set, it re-fires continuously with
        // empty data once the child's write end closes, and the pipe's fd is
        // never released — one leaked fd per interval change.
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        process = nil
        isRunning = false
    }

    private func apply(_ frame: StatusSnapshot) {
        snapshot = frame
        append(&cpuHistory, frame.cpu?.usage ?? 0)
        append(&ramHistory, frame.memory?.usedPercent ?? 0)
    }

    private func append(_ series: inout [Double], _ value: Double) {
        series.append(value)
        if series.count > historyLimit { series.removeFirst(series.count - historyLimit) }
    }

    private func handleTermination() {
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stdoutPipe = nil
        process = nil
        isRunning = false
        // The collector should never exit on its own; if it does, bring it back
        // with a widening delay rather than hammering it.
        let delay = restartDelay
        restartDelay = min(restartDelay * 2, 60)
        // Come back at the cadence that was in force, not the default: a
        // collector that dies while idle must not silently return at the
        // popover-open rate and poll all day.
        let interval = currentInterval
        // A GCD timer, not `Task.sleep`: a suspended task never resumes in this
        // process, so a sleeping retry would mean the collector stays dead
        // after its first unexpected exit.
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            DispatchQueue.main.async { self.start(interval: interval) }
        }
    }
}
