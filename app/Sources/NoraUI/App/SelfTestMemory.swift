import Foundation

/// Checks the per-application memory grouping against this machine's real
/// process list. Called from `SelfTest`.
enum MemoryGroupingCheck {
    /// Returns the lines to print, and whether the check passed.
    static func run() -> (lines: [String], passed: Bool) {
        guard let ps = ProcessRunner.which("ps") else {
            return (["ps không có trên PATH"], false)
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = OutputBox()
        Task {
            let result = await ProcessRunner.run(ps, arguments: ["-Ao", "rss=,comm="], timeout: 10)
            box.set(result.stdout)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 20)

        let apps = ProcessMemoryService.group(box.value)
        guard !apps.isEmpty else { return (["không gộp được tiến trình nào"], false) }

        var lines: [String] = []
        for app in apps.prefix(6) {
            lines.append("        · \(app.name): \(ByteFormatter.string(app.bytes))"
                         + " (\(app.processCount) tiến trình)")
        }

        // Grouping is only worth doing if it actually merges helper processes;
        // a machine running a browser always has some multi-process app.
        let merged = apps.contains { $0.processCount > 1 }
        if !merged { lines.append("        không gộp được tiến trình con nào") }

        // Nesting is checked against known paths rather than by scanning names
        // for "Helper": plenty of system daemons are legitimately called
        // `mDNSResponderHelper` or `AirPlayXPCHelper`, and matching on the word
        // failed the check on a correctly grouped machine.
        let nesting = nestingIsCorrect()
        if !nesting { lines.append("        gộp sai tầng bundle lồng nhau") }

        return (lines, merged && nesting)
    }

    /// A helper bundle nested inside its parent must be attributed to the
    /// parent — the app the user actually launched.
    private static func nestingIsCorrect() -> Bool {
        let nested = """
        1024 /Applications/Claude.app/Contents/Frameworks/Claude Helper (Renderer).app\
        /Contents/MacOS/Claude Helper (Renderer)
        2048 /Applications/Claude.app/Contents/MacOS/Claude
        512 /usr/sbin/mDNSResponderHelper
        """

        let grouped = ProcessMemoryService.group(nested)
        guard let claude = grouped.first(where: { $0.name == "Claude" }) else { return false }

        // Both Claude processes merged, and the standalone daemon stayed
        // separate under its own name.
        return claude.processCount == 2
            && claude.bytes == 3072 * 1024
            && grouped.contains { $0.name == "mDNSResponderHelper" && $0.processCount == 1 }
    }

    private final class OutputBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored = ""

        func set(_ text: String) {
            lock.lock(); defer { lock.unlock() }
            stored = text
        }

        var value: String {
            lock.lock(); defer { lock.unlock() }
            return stored
        }
    }
}
