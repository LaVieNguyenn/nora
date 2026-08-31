import Foundation
import AppKit
import Combine

/// One row of `nora uninstall --list`.
struct InstalledApp: Decodable, Identifiable {
    let name: String
    let bundleId: String
    let source: String
    let uninstallName: String
    let path: String
    /// Nora reports `"--"` when it could not size the bundle in time.
    let size: String

    var id: String { path }

    enum CodingKeys: String, CodingKey {
        case name, source, path, size
        case bundleId = "bundle_id"
        case uninstallName = "uninstall_name"
    }

    var sizeBytes: Int64? {
        size == "--" ? nil : CleanupLedgerParser.parseSize(size)
    }

    var isAppleApp: Bool { bundleId.hasPrefix("com.apple.") }
}

/// Lists installed apps and drives `nora uninstall` for a chosen one.
/// Lifecycle of UninstallService.
///
/// Top-level on purpose. Nested inside the `@MainActor` service it inherited
/// that isolation, so every `switch` on it inside a SwiftUI body became a
/// runtime isolation check — and that check segfaults once the view starts
/// re-evaluating on live data. A plain state enum needs no isolation.
enum UninstallPhase: Equatable {
    case idle
    case loading
    case listed
    case previewing(String)
    case removing(String)
}

final class UninstallService: ObservableObject {

    @Published private(set) var phase: UninstallPhase = .idle
    @Published private(set) var apps: [InstalledApp] = []
    @Published private(set) var previewLines: [String] = []
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var error: String?
    @Published var search = ""

    var filteredApps: [InstalledApp] {
        // `apps` is stored pre-sorted (see loadApps), so filtering is the only
        // per-keystroke work; sorting on every body evaluation parsed every
        // size string O(n log n) times per keypress.
        search.isEmpty
            ? apps
            : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    func loadApps() {
        guard phase == .idle || phase == .listed else { return }
        phase = .loading
        error = nil

        Task { [weak self] in
            guard let entrypoint = NoraLocator.entrypoint else {
                DispatchQueue.main.async {
                    self?.phase = .idle
                    self?.error = NoraLocator.setupProblem
                }
                return
            }

            let output = await ProcessRunner.run(
                entrypoint, arguments: ["uninstall", "--list"], timeout: 120)

            DispatchQueue.main.async {
                guard let self else { return }
                guard let data = Self.jsonPayload(from: output.stdout),
                      let decoded = try? JSONDecoder().decode([InstalledApp].self, from: data)
                else {
                    self.phase = .idle
                    self.error = "Không đọc được danh sách ứng dụng"
                    return
                }
                self.apps = decoded.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }
                self.phase = .listed
            }
        }
    }

    /// The CLI may print a banner before the JSON array, so slice from the
    /// first `[` rather than decoding the whole stream.
    private nonisolated static func jsonPayload(from text: String) -> Data? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]")
        else { return nil }
        return String(text[start...end]).data(using: .utf8)
    }

    /// Preview what removing an app would touch. Always run before the real
    /// removal — this is the list the confirmation sheet shows.
    func preview(_ app: InstalledApp) {
        phase = .previewing(app.name)
        previewLines = []

        Task { [weak self] in
            guard let entrypoint = NoraLocator.entrypoint else { return }
            let output = await ProcessRunner.run(
                entrypoint,
                arguments: ["uninstall", "--dry-run", app.uninstallName],
                timeout: 120
            )

            DispatchQueue.main.async {
                guard let self else { return }
                let lines = output.stdout
                    .split(separator: "\n")
                    .map { CleanupService.stripANSI(String($0)).trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
                self.previewLines = lines
                self.phase = .listed
            }
        }
    }

    /// Run the real uninstall. Nora moves bundles to the Trash by default,
    /// so this stays reversible unless `--permanent` is passed.
    func uninstall(_ app: InstalledApp) {
        phase = .removing(app.name)
        log = [LogLine(time: Date(), level: .working,
                       message: "Bắt đầu gỡ \(app.name)", detail: app.path)]

        Task { [weak self] in
            guard let entrypoint = NoraLocator.entrypoint else { return }
            // --yes because the confirmation already happened in the sheet, and
            // ProcessRunner closes stdin: without it the CLI stops at its own
            // prompt and reports failure without removing anything.
            let output = await ProcessRunner.run(
                entrypoint, arguments: ["uninstall", "--yes", app.uninstallName], timeout: 300)

            DispatchQueue.main.async {
                guard let self else { return }
                for raw in output.stdout.split(separator: "\n") {
                    let line = CleanupService.stripANSI(String(raw))
                        .trimmingCharacters(in: .whitespaces)
                    guard !line.isEmpty else { continue }
                    self.log.append(LogLine(
                        time: Date(),
                        level: Self.level(for: line),
                        message: line,
                        detail: nil
                    ))
                }
                self.log.append(LogLine(
                    time: Date(),
                    level: output.succeeded ? .done : .failed,
                    message: output.succeeded ? "Đã gỡ \(app.name)" : "Gỡ \(app.name) thất bại",
                    detail: output.succeeded ? nil : output.stderr
                ))
                // Bounded like the cleanup and optimize logs. Uninstalling app
                // after app in one session otherwise grows this for as long as
                // the app runs; nobody scrolls back past a few hundred lines.
                LogLine.trim(&self.log)
                self.previewLines = []
                self.phase = .listed
                self.loadApps()
                MemoryRelief.release()
            }
        }
    }

    /// What a line from the CLI is reporting.
    ///
    /// Everything that was not a skip used to be logged as a removal, so the
    /// lines saying the uninstall did not work — "Uninstall incomplete",
    /// "Failed: macOS privacy permission denied" — were shown with the same
    /// green check as a file that was actually deleted.
    private nonisolated static func level(for line: String) -> LogLine.Level {
        let lower = line.lowercased()
        if lower.contains("failed") || lower.contains("incomplete") || lower.hasPrefix("error") {
            return .failed
        }
        if lower.contains("skip") {
            return .skipped
        }
        return .removed
    }

    func reveal(_ app: InstalledApp) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: app.path)])
    }
}
