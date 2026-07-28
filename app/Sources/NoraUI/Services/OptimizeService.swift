import Foundation
import Combine

/// One maintenance task from Nora's optimize catalog.
///
/// The list is fixed rather than read back from the CLI: `mo optimize` has no
/// machine-readable listing, and parsing its rendered output would break the
/// first time a label changed. Names mirror `lib/optimize/catalog.sh`.
struct OptimizeTask: Identifiable {
    enum Group: String, CaseIterable {
        case repair, database, caches, spotlight, housekeeping, system

        var label: String {
            switch self {
            case .repair: return "Sửa lỗi hệ thống"
            case .database: return "Nén cơ sở dữ liệu"
            case .caches: return "Làm mới cache"
            case .spotlight: return "Spotlight"
            case .housekeeping: return "Dọn dữ liệu tích tụ"
            case .system: return "Bảo trì macOS"
            }
        }

        var symbol: String {
            switch self {
            case .repair: return "wrench.and.screwdriver"
            case .database: return "cylinder.split.1x2"
            case .caches: return "arrow.triangle.2.circlepath"
            case .spotlight: return "magnifyingglass"
            case .housekeeping: return "shippingbox"
            case .system: return "gearshape.2"
            }
        }
    }

    let id: String
    let name: String
    let detail: String
    let group: Group
    /// Tasks that need admin rights; the CLI prompts for them itself.
    let needsAdmin: Bool

    static let all: [OptimizeTask] = [
        .init(id: "fix_broken_configs", name: "Sửa preferences hỏng",
              detail: "Phát hiện và sửa các tệp cấu hình bị lỗi", group: .repair, needsAdmin: false),
        .init(id: "launch_services_rebuild", name: "Sửa menu \"Open with\"",
              detail: "Dựng lại liên kết tệp và ứng dụng mặc định", group: .repair, needsAdmin: false),
        .init(id: "dock_refresh", name: "Làm mới Dock",
              detail: "Sửa icon vỡ và lỗi hiển thị trên Dock", group: .repair, needsAdmin: false),
        .init(id: "shared_file_list_repair", name: "Sửa Finder yêu thích",
              detail: "Khôi phục mục yêu thích và tài liệu gần đây bị hỏng", group: .repair, needsAdmin: false),
        .init(id: "login_items_audit", name: "Kiểm tra mục khởi động",
              detail: "Tìm mục khởi động trỏ vào app đã gỡ", group: .repair, needsAdmin: false),
        .init(id: "launch_agents_cleanup", name: "Dọn LaunchAgents hỏng",
              detail: "Gỡ tác vụ nền có tệp thực thi không còn tồn tại", group: .repair, needsAdmin: true),
        .init(id: "disk_permissions_repair", name: "Sửa quyền thư mục",
              detail: "Sửa lỗi phân quyền trong thư mục người dùng", group: .repair, needsAdmin: false),

        .init(id: "sqlite_vacuum", name: "Nén database Mail, Safari, Messages",
              detail: "Tự bỏ qua nếu app đang mở. Đây là tác vụ cho cảm giác khác biệt rõ nhất",
              group: .database, needsAdmin: false),

        .init(id: "system_maintenance", name: "Xoá cache DNS",
              detail: "Làm mới DNS và kiểm tra trạng thái Spotlight", group: .caches, needsAdmin: true),
        .init(id: "network_optimization", name: "Khởi động lại mDNSResponder",
              detail: "Làm mới cache phân giải tên miền", group: .caches, needsAdmin: true),
        .init(id: "network_stack_optimize", name: "Xoá bảng định tuyến và ARP",
              detail: "Xử lý các trục trặc kết nối mạng", group: .caches, needsAdmin: true),
        .init(id: "cache_refresh", name: "Làm mới QuickLook và icon",
              detail: "Dựng lại thumbnail và cache biểu tượng", group: .caches, needsAdmin: false),

        .init(id: "spotlight_index_optimize", name: "Dựng lại index Spotlight",
              detail: "Chỉ chạy khi phát hiện tìm kiếm chậm", group: .spotlight, needsAdmin: true),
        .init(id: "spotlight_orphan_rules_cleanup", name: "Dọn quy tắc tìm kiếm mồ côi",
              detail: "Gỡ quy tắc trỏ vào app đã gỡ", group: .spotlight, needsAdmin: false),

        .init(id: "saved_state_cleanup", name: "Xoá trạng thái app cũ",
              detail: "Trạng thái đã lưu trên 30 ngày", group: .housekeeping, needsAdmin: false),
        .init(id: "quarantine_cleanup", name: "Xoá lịch sử tải về của Gatekeeper",
              detail: "Cơ sở dữ liệu theo dõi tệp đã tải", group: .housekeeping, needsAdmin: false),
        .init(id: "notification_cleanup", name: "Xoá thông báo cũ",
              detail: "Giảm phình cơ sở dữ liệu thông báo", group: .housekeeping, needsAdmin: false),
        .init(id: "coreduet_cleanup", name: "Xoá dữ liệu thống kê sử dụng",
              detail: "Dữ liệu theo dõi thói quen dùng máy đã cũ", group: .housekeeping, needsAdmin: false),
        .init(id: "legacy_overrides_audit", name: "Gỡ tinh chỉnh cũ",
              detail: "Ghi đè App Nap và kiểm tra disk image do công cụ cũ để lại",
              group: .housekeeping, needsAdmin: false),

        .init(id: "periodic_maintenance", name: "Chạy bảo trì định kỳ của macOS",
              detail: "Script daily/weekly/monthly nếu đã lâu chưa chạy", group: .system, needsAdmin: true),
        .init(id: "disk_verify", name: "Kiểm tra toàn vẹn hệ thống tệp",
              detail: "Chỉ kiểm tra, không sửa đổi", group: .system, needsAdmin: false),
        .init(id: "prevent_network_dsstore", name: "Chặn .DS_Store trên ổ mạng",
              detail: "Đặt tuỳ chọn Finder cho SMB/AFP/NFS và USB", group: .system, needsAdmin: false),
    ]

    static var grouped: [(Group, [OptimizeTask])] {
        Group.allCases.compactMap { group in
            let tasks = all.filter { $0.group == group }
            return tasks.isEmpty ? nil : (group, tasks)
        }
    }
}

/// Runs `mo optimize`, streaming its output into the activity log.
///
/// Unlike cleanup, the app does not pick individual tasks: `mo optimize` has no
/// per-task flag, and driving it by any other means would bypass the CLI's own
/// ordering and sudo handling. The task list above is what the run will cover.
/// Lifecycle of OptimizeService.
///
/// Top-level on purpose. Nested inside the `@MainActor` service it inherited
/// that isolation, so every `switch` on it inside a SwiftUI body became a
/// runtime isolation check — and that check segfaults once the view starts
/// re-evaluating on live data. A plain state enum needs no isolation.
enum OptimizePhase: Equatable {
    case idle
    case previewing
    case running
    case finished
}

final class OptimizeService: ObservableObject {

    @Published private(set) var phase: OptimizePhase = .idle
    @Published private(set) var log: [LogLine] = []
    @Published private(set) var lastRun: Date?

    private var process: Process?

    var isBusy: Bool { phase == .previewing || phase == .running }

    func run(dryRun: Bool) {
        guard !isBusy else { return }
        guard let entrypoint = NoraLocator.entrypoint else {
            append(.failed, "Không tìm thấy Nora CLI", detail: NoraLocator.setupProblem)
            return
        }

        phase = dryRun ? .previewing : .running
        log = []
        append(.working, dryRun ? "Xem trước — không thay đổi gì" : "Bắt đầu tối ưu")

        var arguments = ["optimize"]
        if dryRun { arguments.append("--dry-run") }

        let process = Process()
        process.executableURL = entrypoint
        process.arguments = arguments
        // A real run may need admin rights. The CLI asks for them on its own
        // terminal; with stdin closed it skips those tasks and says so, rather
        // than blocking forever on a prompt nobody can answer.
        process.standardInput = FileHandle.nullDevice

        var env = ProcessInfo.processInfo.environment
        env["LC_ALL"] = "C"
        env["NO_COLOR"] = "1"
        process.environment = env

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let buffer = LineBuffer()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            let lines = buffer.append(chunk)
                .map { CleanupService.stripANSI($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else { return }
            Task { @MainActor [weak self] in
                for line in lines { self?.appendCLILine(line) }
            }
        }

        process.terminationHandler = { proc in
            let code = proc.terminationStatus
            DispatchQueue.main.async { [weak self] in self?.finish(exitCode: code) }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            phase = .idle
            append(.failed, "Không chạy được mo optimize", detail: error.localizedDescription)
        }
    }

    func cancel() {
        process?.terminate()
        process = nil
        phase = .idle
        append(.skipped, "Đã dừng theo yêu cầu")
    }

    /// Classify a CLI line so the log reads at a glance.
    private func appendCLILine(_ line: String) {
        let lower = line.lowercased()
        let level: LogLine.Level

        if lower.contains("skip") || lower.contains("whitelist") {
            level = .skipped
        } else if lower.contains("fail") || lower.contains("error") {
            level = .failed
        } else if lower.hasPrefix("➤") || lower.contains("...") {
            level = .working
        } else {
            level = .removed
        }

        append(level, line)
    }

    private func finish(exitCode: Int32) {
        process = nil
        let preview = phase == .previewing
        phase = .finished
        lastRun = Date()
        append(
            exitCode == 0 ? .done : .failed,
            exitCode == 0
                ? (preview ? "Xem trước xong — chưa thay đổi gì" : "Tối ưu xong")
                : "Kết thúc với mã lỗi \(exitCode)"
        )
    }

    private func append(_ level: LogLine.Level, _ message: String, detail: String? = nil) {
        log.append(LogLine(time: Date(), level: level, message: message, detail: detail))
        if log.count > 2000 { log.removeFirst(log.count - 2000) }
    }

    var logText: String {
        log.map { "\($0.timeText) \($0.message)" }.joined(separator: "\n")
    }
}
