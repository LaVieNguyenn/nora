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
    private var cancelRequested = false

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

    func cancelScan() {
        scanProcess?.terminate()
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
        scanProcess = nil
        let file = NoraLocator.cleanListFile

        guard let text = try? String(contentsOf: file, encoding: .utf8) else {
            phase = .idle
            appendLog(.failed, "Không đọc được danh sách", detail: file.path)
            return
        }

        let parsed = CleanupLedgerParser.parse(text)
        groups = parsed
        lastScanDate = Date()

        // Pre-tick only the regenerable groups; everything else waits for a
        // deliberate choice.
        selection = Set(
            parsed.filter(\.isSafeByDefault).flatMap(\.items).map(\.id)
        )

        phase = parsed.isEmpty ? .idle : .ready
        scanProgress = ""
        appendLog(
            .done,
            "Quét xong: \(parsed.count) nhóm, \(parsed.reduce(0) { $0 + $1.items.count }) mục",
            detail: ByteFormatter.string(selectedBytes) + " đang được chọn"
        )
    }

    // MARK: - Selection

    var allItems: [CleanupItem] { groups.flatMap(\.items) }

    var selectedItems: [CleanupItem] { allItems.filter { selection.contains($0.id) } }

    var selectedBytes: Int64 {
        selectedItems.compactMap(\.sizeBytes).reduce(0, +)
    }

    var totalBytes: Int64 { allItems.compactMap(\.sizeBytes).reduce(0, +) }

    func toggle(_ item: CleanupItem) {
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func toggle(group: CleanupGroup) {
        let ids = Set(group.items.map(\.id))
        if ids.isSubset(of: selection) {
            selection.subtract(ids)
        } else {
            selection.formUnion(ids)
        }
    }

    func selectionState(of group: CleanupGroup) -> (checked: Bool, partial: Bool) {
        let ids = Set(group.items.map(\.id))
        let hit = ids.intersection(selection).count
        return (hit > 0, hit > 0 && hit < ids.count)
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

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let useTrash = await self.moveToTrash

            for target in targets {
                if await self.cancelRequested {
                    await self.appendLog(.skipped, "Đã dừng theo yêu cầu")
                    break
                }
                await self.process(target, useTrash: useTrash)
            }

            await self.completeClean()
        }
    }

    func requestCancel() { cancelRequested = true }

    private func process(_ item: CleanupItem, useTrash: Bool) async {
        let fileManager = FileManager()

        guard fileManager.fileExists(atPath: item.path) else {
            appendLog(.skipped, "Bỏ qua \(item.lastComponent)", detail: "không còn tồn tại")
            itemsProcessed += 1
            return
        }

        // Size the path now rather than trusting the ledger: the scan may have
        // run minutes ago and a cache grows while you read the list.
        let actualSize = item.sizeBytes ?? 0
        let url = URL(fileURLWithPath: item.path)

        do {
            if useTrash {
                try fileManager.trashItem(at: url, resultingItemURL: nil)
            } else {
                try fileManager.removeItem(at: url)
            }
            bytesFreed += actualSize
            itemsProcessed += 1
            appendLog(
                .removed,
                useTrash ? "Chuyển \(item.lastComponent)" : "Xóa \(item.lastComponent)",
                detail: actualSize > 0 ? ByteFormatter.string(actualSize) : nil
            )
        } catch let error as NSError {
            itemsProcessed += 1
            let reason: String
            switch error.code {
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                reason = "cần quyền quản trị"
            case NSFileWriteFileExistsError:
                reason = "đang được dùng"
            default:
                reason = error.localizedDescription
            }
            appendLog(.skipped, "Bỏ qua \(item.lastComponent)", detail: reason)
        }
    }

    private func completeClean() {
        phase = .finished
        appendLog(
            .done,
            "Hoàn tất — \(itemsProcessed) mục, \(ByteFormatter.string(bytesFreed))",
            detail: moveToTrash ? "Dung lượng được giải phóng khi bạn dọn Thùng rác" : nil
        )
    }

    func reset() {
        phase = groups.isEmpty ? .idle : .ready
        bytesFreed = 0
        itemsProcessed = 0
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
        // A long run can emit thousands of lines; keep the tail bounded so the
        // view does not accumulate rows forever.
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
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
    static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: bytes)
    }
}
