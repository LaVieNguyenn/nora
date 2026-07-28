import Foundation

/// One removable path from Nora's dry-run ledger.
struct CleanupItem: Identifiable, Hashable {
    let id = UUID()
    let path: String
    /// nil when Nora could not size the path within its timeout.
    let sizeBytes: Int64?
    /// Number of entries the path expands to, when it stands for more than one.
    let itemCount: Int

    var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    var lastComponent: String { (path as NSString).lastPathComponent }

    var exists: Bool { FileManager.default.fileExists(atPath: path) }
}

/// A `=== Section ===` from the ledger.
struct CleanupGroup: Identifiable {
    let id = UUID()
    let name: String
    var items: [CleanupItem]

    var totalBytes: Int64 { items.compactMap(\.sizeBytes).reduce(0, +) }
    var hasUnknownSizes: Bool { items.contains { $0.sizeBytes == nil } }

    /// Groups whose contents are regenerated on demand are safe to pre-select;
    /// anything that could hold something you wrote is left for you to tick.
    var isSafeByDefault: Bool {
        switch name.lowercased() {
        case let n where n.contains("cache"): return true
        case let n where n.contains("browser"): return true
        case let n where n.contains("developer"): return true
        default: return false
        }
    }

    var vietnameseName: String {
        switch name {
        case "User essentials": return "Hệ thống người dùng"
        case "App caches": return "Cache ứng dụng"
        case "Browsers": return "Trình duyệt"
        case "Developer tools": return "Công cụ lập trình"
        case "Applications": return "Ứng dụng"
        case "Application Support": return "Application Support"
        case "App leftovers": return "Tàn dư app đã gỡ"
        default: return name
        }
    }
}

/// Parses the `~/.config/nora/clean-list.txt` ledger that `nora clean --dry-run`
/// writes.
///
/// Format, per `bin/clean.sh`:
/// ```
/// # comment header
/// === Section name ===
/// /absolute/path  # 6.95GB
/// /absolute/path  # 94KB, 3 items
/// /absolute/path  # size unknown
/// ```
enum CleanupLedgerParser {
    static func parse(_ text: String) -> [CleanupGroup] {
        var groups: [CleanupGroup] = []
        var currentName: String?
        var currentItems: [CleanupItem] = []

        func flush() {
            if let name = currentName, !currentItems.isEmpty {
                groups.append(CleanupGroup(name: name, items: currentItems))
            }
            currentItems = []
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("=== ") && line.hasSuffix(" ===") {
                flush()
                currentName = String(line.dropFirst(4).dropLast(4))
                continue
            }

            if line.hasPrefix("#") { continue }

            // Path and annotation are separated by two spaces then a hash. A
            // path may itself contain "#", so split on the last occurrence of
            // the separator rather than the first hash.
            guard let range = line.range(of: "  # ", options: .backwards) else { continue }
            let path = String(line[line.startIndex..<range.lowerBound])
            let annotation = String(line[range.upperBound...])
            guard path.hasPrefix("/") else { continue }

            currentItems.append(CleanupItem(
                path: path,
                sizeBytes: parseSize(annotation),
                itemCount: parseCount(annotation)
            ))
        }
        flush()

        return groups
    }

    /// `"6.95GB"`, `"94KB, 3 items"`, `"size unknown"`.
    static func parseSize(_ annotation: String) -> Int64? {
        let head = annotation.split(separator: ",").first.map(String.init) ?? annotation
        let trimmed = head.trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("size unknown") { return nil }

        let units: [(String, Double)] = [
            ("TB", 1_099_511_627_776), ("GB", 1_073_741_824),
            ("MB", 1_048_576), ("KB", 1024), ("B", 1),
        ]
        for (suffix, multiplier) in units where trimmed.uppercased().hasSuffix(suffix) {
            let numberPart = trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
            guard let value = Double(numberPart) else { return nil }
            return Int64(value * multiplier)
        }
        return nil
    }

    static func parseCount(_ annotation: String) -> Int {
        for part in annotation.split(separator: ",") {
            let text = part.trimmingCharacters(in: .whitespaces)
            guard text.hasSuffix("items") || text.hasSuffix("item") else { continue }
            let number = text.split(separator: " ").first.map(String.init) ?? ""
            if let count = Int(number) { return count }
        }
        return 1
    }
}

/// One line of the live activity log.
struct LogLine: Identifiable {
    enum Level { case removed, skipped, working, failed, done }

    let id = UUID()
    let time: Date
    let level: Level
    let message: String
    let detail: String?

    var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: time)
    }
}
