import Foundation
import AppKit
import Combine

/// Result of `analyze --json` for one directory.
struct AnalyzeResult: Decodable {
    struct Entry: Decodable, Identifiable {
        let name: String
        let path: String
        let size: Int64
        let isDir: Bool

        var id: String { path }

        enum CodingKeys: String, CodingKey {
            case name, path, size
            case isDir = "is_dir"
        }
    }

    struct LargeFile: Decodable, Identifiable {
        let name: String
        let path: String
        let size: Int64

        var id: String { path }
    }

    let path: String
    let overview: Bool?
    let entries: [Entry]?
    let largeFiles: [LargeFile]?
    let totalSize: Int64?
    let totalFiles: Int?

    enum CodingKeys: String, CodingKey {
        case path, overview, entries
        case largeFiles = "large_files"
        case totalSize = "total_size"
        case totalFiles = "total_files"
    }
}

/// Runs the disk analyzer and keeps a breadcrumb trail for drilling down.
final class AnalyzeService: ObservableObject {
    @Published private(set) var result: AnalyzeResult?
    @Published private(set) var isScanning = false
    @Published private(set) var error: String?
    /// Every directory visited, so the breadcrumb can walk back up.
    @Published private(set) var trail: [String] = []

    /// The directory entries, largest first.
    ///
    /// Sorted once when a result lands rather than inside the view body: the
    /// body re-evaluates on every hover, and re-sorting a home directory's
    /// entry list per mouse move showed up as a stutter on the row highlight.
    @Published private(set) var sortedEntries: [AnalyzeResult.Entry] = []

    private var currentTask: Task<Void, Never>?

    var currentPath: String? { trail.last }

    func scan(_ path: String, pushToTrail: Bool = true) {
        currentTask?.cancel()
        isScanning = true
        error = nil

        if pushToTrail {
            // Re-entering a directory already in the trail truncates back to it
            // rather than appending a duplicate.
            if let index = trail.firstIndex(of: path) {
                trail = Array(trail[...index])
            } else {
                trail.append(path)
            }
        }

        currentTask = Task { [weak self] in
            guard let binary = NoraLocator.analyzeBinary else {
                DispatchQueue.main.async {
                    self?.isScanning = false
                    self?.error = "Thiếu bin/analyze-go — cài lại Nora, hoặc chạy `make build` nếu chạy từ mã nguồn."
                }
                return
            }

            // A cold scan of a large tree is slow; the timeout is generous
            // because a partial result is worse than a slow one here.
            let output = await ProcessRunner.run(
                binary, arguments: ["--json", path], timeout: 300)

            guard !Task.isCancelled else { return }

            DispatchQueue.main.async {
                guard let self else { return }
                self.isScanning = false

                guard let data = output.stdout.data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(AnalyzeResult.self, from: data)
                else {
                    self.error = output.exitCode == -2
                        ? "Quá thời gian chờ khi quét \(path)"
                        : "Không đọc được kết quả quét"
                    return
                }
                self.result = decoded
                self.sortedEntries = (decoded.entries ?? []).sorted { $0.size > $1.size }
                // A cold scan of a home directory decodes tens of thousands of
                // entries and throws most of them away; hand the pages back
                // rather than sitting on them until the next scan.
                MemoryRelief.release()
            }
        }
    }

    func goUp(to path: String) {
        scan(path, pushToTrail: true)
    }

    func reset() {
        trail = []
        result = nil
        sortedEntries = []
        error = nil
    }

    /// Release the decoded tree when the tab goes away.
    func discard() {
        currentTask?.cancel()
        currentTask = nil
        reset()
        isScanning = false
        MemoryRelief.release()
    }

    func reveal(_ path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    /// Home directory, the default starting point.
    static var defaultRoot: String {
        FileManager.default.homeDirectoryForCurrentUser.path
    }
}
