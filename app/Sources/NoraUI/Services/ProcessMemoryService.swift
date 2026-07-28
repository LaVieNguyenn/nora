import Foundation
import Combine

/// One application's total resident memory, summed across its processes.
struct AppMemory: Identifiable {
    let name: String
    let bytes: Int64
    let processCount: Int

    var id: String { name }
}

/// Answers "what is actually using my RAM" by grouping every process under the
/// application that owns it.
///
/// Nora's own snapshot cannot answer this: it returns five processes sorted by
/// CPU, so the biggest memory consumer is often not in the list at all. This
/// runs its own `ps`, but only when the memory panel is opened — the popover's
/// normal cadence never pays for it.
final class ProcessMemoryService: ObservableObject {
    @Published private(set) var apps: [AppMemory] = []
    @Published private(set) var isLoading = false
    @Published private(set) var sampledAt: Date?

    /// Repeatedly opening the panel should not re-fork `ps` each time.
    private let freshness: TimeInterval = 10

    func refreshIfStale() {
        if let sampledAt, Date().timeIntervalSince(sampledAt) < freshness { return }
        refresh()
    }

    func refresh() {
        guard !isLoading else { return }
        guard let ps = ProcessRunner.which("ps") else { return }
        isLoading = true

        Task { [weak self] in
            // `comm=` gives the full executable path, which is what makes the
            // owning .app recoverable; `rss=` is resident size in KB.
            let output = await ProcessRunner.run(
                ps, arguments: ["-Ao", "rss=,comm="], timeout: 10)

            let grouped = Self.group(output.stdout)

            DispatchQueue.main.async {
                guard let self else { return }
                self.apps = grouped
                self.sampledAt = Date()
                self.isLoading = false
            }
        }
    }

    /// Sum resident memory per owning application.
    ///
    /// Chrome alone runs 21 processes; listing them separately buries the fact
    /// that together they hold more than anything else on the machine.
    static func group(_ psOutput: String) -> [AppMemory] {
        var bytes: [String: Int64] = [:]
        var counts: [String: Int] = [:]

        for line in psOutput.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "),
                  let kb = Int64(trimmed[trimmed.startIndex..<space])
            else { continue }

            let path = String(trimmed[trimmed.index(after: space)...])
                .trimmingCharacters(in: .whitespaces)
            guard !path.isEmpty else { continue }

            let name = owningApp(of: path)
            bytes[name, default: 0] += kb * 1024
            counts[name, default: 0] += 1
        }

        return bytes
            .map { AppMemory(name: $0.key, bytes: $0.value, processCount: counts[$0.key] ?? 1) }
            .sorted { $0.bytes > $1.bytes }
    }

    /// Walk the path to the outermost `.app` bundle.
    ///
    /// Helper processes nest their own bundles — "Claude Helper (Renderer).app"
    /// lives inside "Claude.app" — so taking the *first* `.app` in the path
    /// attributes the helper to the application the user actually launched.
    private static func owningApp(of path: String) -> String {
        for component in path.split(separator: "/") where component.hasSuffix(".app") {
            return String(component.dropLast(4))
        }
        return path.split(separator: "/").last.map(String.init) ?? path
    }
}
