import Foundation
import AppKit
import Combine

/// Drives the scan-then-remove flow behind the Cleanup tab.
///
/// The candidate list always comes from `nora clean --dry-run`, so every path the
/// UI can offer has already passed Nora's protection and whitelist checks. The
/// app never invents a path of its own to delete.
/// Lifecycle of CleanupService.
///
/// Top-level on purpose. Nested inside the `@MainActor` service it inherited
/// that isolation, so every `switch` on it inside a SwiftUI body became a
/// runtime isolation check — and that check segfaults once the view starts
/// re-evaluating on live data. A plain state enum needs no isolation.
enum CleanupPhase: Equatable {
    case idle
    case scanning
    case ready
    case cleaning
    case finished
}

final class CleanupService: ObservableObject {

    @Published private(set) var phase: CleanupPhase = .idle
    @Published private(set) var groups: [CleanupGroup] = []
    @Published var selection: Set<UUID> = []
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var scanProgress: String = ""
    @Published private(set) var bytesFreed: Int64 = 0
    @Published private(set) var itemsProcessed: Int = 0
    @Published private(set) var lastScanDate: Date?

    /// Move to Trash instead of deleting outright. On by default because it
    /// makes every action reversible from Finder; the space is reclaimed when
    /// the Trash is emptied.
    @Published var moveToTrash: Bool = true

    private var scanProcess: Process?
    private var scanPipe: Pipe?
    private var cancelRequested = false

    /// Cached totals for the current selection. Recomputing them from all
    /// ~3300 items on every body evaluation made rendering during a clean
    /// quadratic — the log appends per item, and each append re-evaluated
    /// half a dozen O(n) filters.
    @Published private(set) var selectedCount = 0
    @Published private(set) var selectedBytesCached: Int64 = 0
    /// Total item count across every group, cached for the same reason: the
    /// subtitle asked for it on every body evaluation and paid a `flatMap` over
    /// the whole ledger to get it.
    @Published private(set) var itemCount = 0

    private func recalcSelection() {
        var count = 0
        var bytes: Int64 = 0
        // One pass over the groups rather than materialising `selectedItems`:
        // that built a fresh ~3300-element array on every checkbox click, and
        // during a clean it ran once per processed item.
        for group in groups {
            for item in group.items where selection.contains(item.id) {
                count += 1
                bytes += item.sizeBytes ?? 0
            }
        }
        selectedCount = count
        selectedBytesCached = bytes
    }

    // MARK: - Scan

    func scan() {
        guard phase != .scanning, phase != .cleaning else { return }
        guard let entrypoint = NoraLocator.entrypoint else {
            appendLog(.failed, "Không tìm thấy Nora CLI", detail: NoraLocator.setupProblem)
            return
        }

        phase = .scanning
        groups = []
        selection = []
        log = []
        scanProgress = "Đang khởi động…"
        appendLog(.working, "Bắt đầu quét thử (dry-run)")

        let process = Process()
        process.executableURL = entrypoint
        process.arguments = ["clean", "--dry-run"]
        process.standardInput = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        // Nora colours its output for a terminal; without a TTY it still emits
        // section headers, which is all the progress line needs.
        env["NO_COLOR"] = "1"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        let lineBuffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            for raw in lineBuffer.append(chunk) {
                let line = Self.stripANSI(raw).trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }
                DispatchQueue.main.async { self.noteScanProgress(line) }
            }
        }

        process.terminationHandler = { _ in
            DispatchQueue.main.async { self.finishScan() }
        }

        do {
            try process.run()
            scanProcess = process
        } catch {
            phase = .idle
            appendLog(.failed, "Không chạy được dry-run", detail: error.localizedDescription)
        }
    }

    /// Load the ledger a previous `nora clean --dry-run` already wrote, without
    /// running one.
    ///
    /// Diagnostics only — `NORA_CLEANUP_LEDGER=1`. A real scan takes minutes,
    /// so without this the tab's populated state, which is the one with a few
    /// thousand rows in it, could be neither laid out nor measured offscreen.
    /// It is deliberately not wired to any button: the ledger on disk is as old
    /// as the last scan, and showing stale paths as if they were current is how
    /// a cleanup tool deletes something that moved.
    func loadCachedLedger() {
        guard phase == .idle else { return }
        phase = .scanning
        finishScan()
    }

    func cancelScan() {
        scanProcess?.terminate()
        scanPipe?.fileHandleForReading.readabilityHandler = nil
        scanPipe = nil
        scanProcess = nil
        phase = .idle
        scanProgress = ""
    }

    private func noteScanProgress(_ line: String) {
        // Section headers are the only reliable progress signal; item lines are
        // too noisy to show one at a time.
        if line.hasPrefix("➤") || line.hasPrefix(">") {
            scanProgress = line
                .trimmingCharacters(in: CharacterSet(charactersIn: "➤> "))
        }
    }

    private func finishScan() {
        scanPipe?.fileHandleForReading.readabilityHandler = nil
        scanPipe = nil
        scanProcess = nil
        let file = NoraLocator.cleanListFile

        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            phase = .idle
            appendLog(.failed, "Không đọc được danh sách", detail: file.path)
            return
        }

        let parsed = CleanupLedgerParser.parse(text)
        groups = parsed
        itemCount = parsed.reduce(0) { $0 + $1.items.count }
        lastScanDate = Date()

        // Pre-tick only the regenerable groups; everything else waits for a
        // deliberate choice.
        var preselected: Set<UUID> = []
        for group in parsed where group.isSafeByDefault {
            for item in group.items { preselected.insert(item.id) }
        }
        selection = preselected
        recalcSelection()

        phase = parsed.isEmpty ? .idle : .ready
        scanProgress = ""
        appendLog(
            .done,
            "Quét xong: \(parsed.count) nhóm, \(itemCount) mục",
            detail: ByteFormatter.string(selectedBytesCached) + " đang được chọn"
        )
        // The parse walked the whole ledger and built a lot of short-lived
        // strings on the way to the item list that survives.
        MemoryRelief.release()
    }

    // MARK: - Selection

    /// The ticked items, built on demand. Only `performClean` needs the array —
    /// the counts and totals the UI shows come from `recalcSelection`, which
    /// keeps them cached.
    private var selectedItems: [CleanupItem] {
        groups.flatMap { $0.items.filter { selection.contains($0.id) } }
    }

    func toggle(_ item: CleanupItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
        recalcSelection()
    }

    func toggle(group: CleanupGroup) {
        if selectionState(of: group).checked {
            for item in group.items { selection.remove(item.id) }
        } else {
            for item in group.items { selection.insert(item.id) }
        }
        recalcSelection()
    }

    /// Whether a group is fully, partly or not selected.
    ///
    /// Counted in place rather than through `Set(group.items.map(\.id))`: the
    /// group headers are pinned, so this runs on every scroll frame, and the
    /// largest group on this machine holds 611 items — a fresh set of 611 UUIDs
    /// per frame, per header, to answer a question about a checkbox.
    func selectionState(of group: CleanupGroup) -> (checked: Bool, partial: Bool) {
        var hit = 0
        for item in group.items where selection.contains(item.id) { hit += 1 }
        return (hit > 0, hit > 0 && hit < group.items.count)
    }

    // MARK: - Clean

    func performClean() {
        guard phase == .ready else { return }
        let targets = selectedItems
        guard !targets.isEmpty else { return }

        phase = .cleaning
        cancelRequested = false
        bytesFreed = 0
        itemsProcessed = 0
        log = []
        appendLog(
            .working,
            moveToTrash
                ? "Bắt đầu chuyển \(targets.count) mục vào Thùng rác"
                : "Bắt đầu xóa \(targets.count) mục"
        )

        let useTrash = moveToTrash
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            for target in targets {
                if self.cancelRequested {
                    DispatchQueue.main.async { self.appendLog(.skipped, "Đã dừng theo yêu cầu") }
                    break
                }
                self.process(target, useTrash: useTrash)
            }

            DispatchQueue.main.async { self.completeClean() }
        }
    }

    func requestCancel() { cancelRequested = true }

    private func process(_ item: CleanupItem, useTrash: Bool) {
        let fileManager = FileManager()

        guard fileManager.fileExists(atPath: item.path) else {
            DispatchQueue.main.async { [weak self] in
                self?.appendLog(.skipped, "Bỏ qua \(item.lastComponent)", detail: "không còn tồn tại")
                self?.itemsProcessed += 1
            }
            return
        }

        // The ledger's size, not a fresh stat: re-measuring ~3300 paths at
        // delete time would repeat the entire scan. The freed-space figure is
        // therefore as old as the scan, which the UI already timestamps.
        let actualSize = item.sizeBytes ?? 0
        let url = URL(fileURLWithPath: item.path)

        do {
            if useTrash {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            } else {
                try fileManager.removeItem(at: url)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.bytesFreed += actualSize
                self.itemsProcessed += 1
                self.appendLog(
                    .removed,
                    useTrash ? "Chuyển \(item.lastComponent)" : "Xóa \(item.lastComponent)",
                    detail: actualSize > 0 ? ByteFormatter.string(actualSize) : nil
                )
            }
        } catch let error as NSError {
            let reason: String
            switch error.code {
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                reason = "cần quyền quản trị"
            case NSFileWriteFileExistsError:
                reason = "đang được dùng"
            default:
                reason = error.localizedDescription
            }
            DispatchQueue.main.async { [weak self] in
                self?.itemsProcessed += 1
                self?.appendLog(.skipped, "Bỏ qua \(item.lastComponent)", detail: reason)
            }
        }
    }

    private func completeClean() {
        phase = .finished
        appendLog(
            .done,
            "Hoàn tất — \(itemsProcessed) mục, \(ByteFormatter.string(bytesFreed))",
            detail: moveToTrash ? "Dung lượng được giải phóng khi bạn dọn Thùng rác" : nil
        )
        MemoryRelief.release()
    }

    func reset() {
        phase = groups.isEmpty ? .idle : .ready
        bytesFreed = 0
        itemsProcessed = 0
    }

    /// Throw away a finished scan.
    ///
    /// This service is owned by `AppState`, so unlike the per-tab services its
    /// results outlive the window they were shown in. A ledger is a few thousand
    /// items plus a `Set<UUID>` of the ticked ones, held for the rest of the
    /// process's life for a window nobody has open — so a run that has already
    /// been acted on is dropped when the window closes. A scan still waiting for
    /// the user's decision is kept.
    func discardIfSettled() {
        guard phase == .finished || phase == .idle else { return }
        guard !groups.isEmpty else { return }
        groups = []
        selection = []
        log = []
        itemCount = 0
        phase = .idle
        recalcSelection()
        MemoryRelief.release()
    }

    // MARK: - Helpers

    func revealInFinder(_ item: CleanupItem) {
        let url = URL(fileURLWithPath: item.path)
        if FileManager.default.fileExists(atPath: item.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            // Fall back to the parent so the click still lands somewhere useful.
            NSWorkspace.shared.activateFileViewerSelecting([url.deletingLastPathComponent()])
        }
    }

    var logText: String {
        log.map { line in
            let detail = line.detail.map { " (\($0))" } ?? ""
            return "\(line.timeText) \(line.message)\(detail)"
        }.joined(separator: "\n")
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(logText, forType: .string)
    }

    private func appendLog(_ level: LogLine.Level, _ message: String, detail: String? = nil) {
        log.append(LogLine(time: Date(), level: level, message: message, detail: detail))
        LogLine.trim(&log)
    }

    /// Nora colours its terminal output; the codes are noise in a GUI log.
    nonisolated static func stripANSI(_ text: String) -> String {
        var result = ""
        var inEscape = false
        for character in text {
            if inEscape {
                if character.isLetter { inEscape = false }
                continue
            }
            if character == "\u{1B}" { inEscape = true; continue }
            result.append(character)
        }
        return result
    }
}

/// Formats a throughput given in MB/s.
///
/// Idle traffic sits in the tens of KB/s, which renders as "0.0" in MB/s — the
/// unit has to follow the magnitude or a working connection looks dead.
enum RateFormatter {
    /// Number and unit separately, so a bubble can stack them on two lines.
    static func parts(_ megabytesPerSecond: Double) -> (value: String, unit: String) {
        let rate = max(megabytesPerSecond, 0)

        if rate < 0.001 { return ("0", "KB/s") }
        if rate < 1 { return (String(format: "%.0f", rate * 1000), "KB/s") }
        if rate < 10 { return (String(format: "%.1f", rate), "MB/s") }
        return (String(format: "%.0f", rate), "MB/s")
    }

    /// One-line form for cards and captions.
    static func string(_ megabytesPerSecond: Double) -> String {
        let parts = parts(megabytesPerSecond)
        return "\(parts.value) \(parts.unit)"
    }
}

enum ByteFormatter {
    // One instance: this is called from nearly every row of every list, and a
    // fresh ByteCountFormatter per call showed up as pure allocation churn.
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter
    }()

    static func string(_ bytes: Int64) -> String {
        formatter.string(fromByteCount: bytes)
    }
}
