import Foundation

/// Thin wrapper around `Process` for the one-shot commands the app runs.
enum ProcessRunner {
    struct Result {
        let stdout: String
        let stderr: String
        let exitCode: Int32
        var succeeded: Bool { exitCode == 0 }
    }

    /// Run a command to completion, capturing both streams.
    ///
    /// `stdin` is closed rather than inherited: several of the tools the app
    /// shells out to (and Nora's own bash helpers) will block on a prompt if
    /// they find a terminal there, which would hang the caller forever.
    static func run(
        _ executable: URL,
        arguments: [String] = [],
        environment: [String: String]? = nil,
        timeout: TimeInterval = 30
    ) async -> Result {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runBlocking(
                    executable, arguments: arguments, environment: environment, timeout: timeout))
            }
        }
    }

    private static func runBlocking(
        _ executable: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        var env = environment ?? Foundation.ProcessInfo.processInfo.environment
        // Parsers downstream assume `.` decimal separators and English labels.
        env["LC_ALL"] = "C"
        // Homebrew tools (ideviceinfo) are not on a GUI app's inherited PATH.
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return Result(stdout: "", stderr: "\(error)", exitCode: -1)
        }

        // Drain both pipes concurrently. Reading them in sequence deadlocks as
        // soon as the unread pipe fills its 64 KB buffer.
        //
        // The buffers must be lock-protected, not captured `var`s: the waits
        // below are bounded, so a reader can reach the return statement while a
        // drain closure is still assigning. Assigning a `Data` releases the old
        // buffer and retains a new one, so an interleaved read corrupts the
        // heap — which then crashes somewhere unrelated, minutes later.
        let output = OutputCollector()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            output.setStdout(outPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            output.setStderr(errPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        var timedOut = false
        if process.isRunning {
            timedOut = true
            process.terminate()
            // Give it a moment to die on SIGTERM before escalating.
            Thread.sleep(forTimeInterval: 0.3)
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }

        // Killing the child closes both pipes, so the drains finish promptly.
        // The bound is a backstop, and it is safe to pass now that reading the
        // buffers no longer races with writing them.
        _ = group.wait(timeout: .now() + 3)
        process.waitUntilExit()

        return Result(
            stdout: output.stdoutText,
            stderr: timedOut ? "timed out after \(timeout)s" : output.stderrText,
            exitCode: timedOut ? -2 : process.terminationStatus
        )
    }

    /// Lock-protected home for the two pipe buffers.
    private final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var out = Data()
        private var err = Data()

        func setStdout(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            out = data
        }

        func setStderr(_ data: Data) {
            lock.lock(); defer { lock.unlock() }
            err = data
        }

        var stdoutText: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: out, as: UTF8.self)
        }

        var stderrText: String {
            lock.lock(); defer { lock.unlock() }
            return String(decoding: err, as: UTF8.self)
        }
    }

    /// Whether a command exists on the app's PATH.
    ///
    /// Memoised: callers ask for the same handful of tools on every refresh,
    /// and each miss walked five directories of stats for an answer that does
    /// not change while the app runs.
    private static let whichLock = NSLock()
    private static var whichCache: [String: URL?] = [:]

    static func which(_ name: String) -> URL? {
        whichLock.lock()
        if let hit = whichCache[name] {
            whichLock.unlock()
            return hit
        }
        whichLock.unlock()

        var found: URL?
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin"] {
            let url = URL(fileURLWithPath: dir).appending(path: name)
            if FileManager.default.isExecutableFile(atPath: url.path) { found = url; break }
        }

        whichLock.lock()
        whichCache[name] = found
        whichLock.unlock()
        return found
    }
}
