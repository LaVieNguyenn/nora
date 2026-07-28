import Foundation

/// `NoraUI --selftest` exercises every parser against the real data on this
/// machine and prints what it decoded.
///
/// The UI is the only other place these parsers run, and a wrong field there
/// shows up as a blank card rather than an error — this makes the decode step
/// checkable on its own.
enum SelfTest {
    static func run() -> Int32 {
        var failures = 0

        func check(_ name: String, _ passed: Bool, _ detail: String) {
            print("\(passed ? "  ok  " : " FAIL ") \(name): \(detail)")
            if !passed { failures += 1 }
        }

        print("\n=== Vị trí Nora ===")
        check("repo", NoraLocator.repoRoot != nil, NoraLocator.repoRoot?.path ?? "không tìm thấy")
        check("status-go", NoraLocator.statusBinary != nil,
              NoraLocator.statusBinary?.path ?? "thiếu")
        check("analyze-go", NoraLocator.analyzeBinary != nil,
              NoraLocator.analyzeBinary?.path ?? "thiếu")
        check("nora entrypoint", NoraLocator.entrypoint != nil,
              NoraLocator.entrypoint?.path ?? "thiếu")

        print("\n=== status --json ===")
        if let binary = NoraLocator.statusBinary {
            let result = runSync(binary, ["--json"])
            if let data = result.data(using: .utf8),
               let snapshot = try? JSONDecoder().decode(StatusSnapshot.self, from: data) {
                check("cpu.usage", snapshot.cpu?.usage != nil,
                      String(format: "%.1f%%", snapshot.cpu?.usage ?? -1))
                check("memory", snapshot.memory?.usedPercent != nil,
                      String(format: "%.1f%% đã dùng", snapshot.memory?.usedPercent ?? -1))
                check("disk", snapshot.primaryDisk != nil,
                      snapshot.primaryDisk.map {
                          "\(ByteFormatter.string($0.used ?? 0)) / \(ByteFormatter.string($0.total ?? 0))"
                      } ?? "thiếu")
                check("health", snapshot.healthScore != nil,
                      "\(snapshot.healthScore ?? -1) \(snapshot.healthScoreMsg ?? "")")
                check("battery", snapshot.macBattery != nil,
                      snapshot.macBattery.map { "\($0.percent ?? -1)% \($0.status ?? "")" } ?? "không có")
                check("top_processes", (snapshot.topProcesses?.count ?? 0) > 0,
                      "\(snapshot.topProcesses?.count ?? 0) tiến trình")
                let rates = snapshot.networkRates
                check("network", true,
                      "↓\(RateFormatter.string(rates.down)) ↑\(RateFormatter.string(rates.up))"
                      + String(format: " (thô: %.4f MB/s)", rates.down))
                // The unit has to track the magnitude, or idle traffic reads 0.
                let samples: [Double] = [0, 0.0004, 0.018, 0.25, 1.4, 12, 340]
                check("đơn vị tốc độ",
                      samples.allSatisfy { !RateFormatter.string($0).hasPrefix("0.0") },
                      samples.map { RateFormatter.string($0) }.joined(separator: " · "))
            } else {
                check("decode", false, "không giải mã được JSON")
            }
        }

        print("\n=== Pin thiết bị (system_profiler) ===")
        if let profiler = ProcessRunner.which("system_profiler") {
            let output = runSync(profiler, ["SPBluetoothDataType", "-json"])
            let devices = DeviceBatteryService.parseBluetooth(Data(output.utf8))
            // Parsing succeeded if it saw the paired list at all; whether any
            // device currently reports a level depends on what is switched on.
            check("bluetooth parse", !devices.isEmpty, "\(devices.count) thiết bị đã ghép đôi")
            let withBattery = devices.filter { $0.effectivePercent != nil }
            check("có báo pin", true,
                  withBattery.isEmpty
                      ? "không thiết bị nào đang báo pin (chưa kết nối cái nào)"
                      : "\(withBattery.count) thiết bị")
            for device in devices.prefix(8) {
                let level = device.effectivePercent.map { "\($0)%" } ?? "—"
                let state = device.isConnected ? "kết nối" : "ngắt"
                print("        · \(device.name) [\(device.kind.rawValue)] \(level) \(state)"
                      + (device.detail.map { " (\($0))" } ?? ""))
            }
        }

        print("\n=== Gộp RAM theo ứng dụng ===")
        let memory = MemoryGroupingCheck.run()
        check("gộp tiến trình con", memory.passed, "\(memory.lines.count) dòng")
        for line in memory.lines { print(line) }

        print("\n=== Nhánh hết giờ của ProcessRunner ===")
        // The timeout path used to read the pipe buffers while the drain
        // closures were still writing them, corrupting the heap. Hammer it:
        // a surviving run means the buffers are properly serialised.
        if let sleepTool = ProcessRunner.which("sleep") {
            var timeouts = 0
            for _ in 0..<25 {
                let result = runSync(sleepTool, ["5"], timeout: 0.2)
                if result.isEmpty { timeouts += 1 }
            }
            check("25 lần hết giờ liên tiếp", timeouts == 25,
                  "\(timeouts)/25 kết thúc sạch, không hỏng vùng nhớ")
        }

        print("\n=== iPhone (libimobiledevice) ===")
        if let list = ProcessRunner.which("idevice_id") {
            let output = runSync(list, ["-l"]).trimmingCharacters(in: .whitespacesAndNewlines)
            check("idevice_id", true, output.isEmpty ? "chưa thấy thiết bị nào ghép đôi" : output)
        } else {
            check("idevice_id", false, "chưa cài — brew install libimobiledevice")
        }

        print("\n=== Danh sách dọn dẹp (clean-list.txt) ===")
        let ledger = NoraLocator.cleanListFile
        if let text = try? String(contentsOf: ledger, encoding: .utf8) {
            let groups = CleanupLedgerParser.parse(text)
            check("nhóm", !groups.isEmpty, "\(groups.count) nhóm")
            let items = groups.flatMap(\.items)
            check("mục", !items.isEmpty, "\(items.count) mục")
            let sized = items.filter { $0.sizeBytes != nil }
            check("đo được dung lượng", sized.count > items.count / 2,
                  "\(sized.count)/\(items.count) mục")
            let total = items.compactMap(\.sizeBytes).reduce(0, +)
            check("tổng", total > 0, ByteFormatter.string(total))
            for group in groups {
                print("        · \(group.vietnameseName): \(group.items.count) mục, "
                      + ByteFormatter.string(group.totalBytes)
                      + (group.isSafeByDefault ? " [tick sẵn]" : ""))
            }
            // Paths must be absolute and must still exist often enough to be
            // worth showing; a ledger full of vanished paths means it is stale.
            let existing = items.prefix(60).filter(\.exists).count
            check("path còn tồn tại", existing > 0, "\(existing)/60 mẫu đầu")
        } else {
            check("đọc file", false, "chưa có \(ledger.path) — chạy `mo clean --dry-run`")
        }

        print("\n=== analyze --json ===")
        if let binary = NoraLocator.analyzeBinary {
            let home = FileManager.default.homeDirectoryForCurrentUser
                .appending(path: "Documents").path
            let output = runSync(binary, ["--json", home], timeout: 240)
            if let data = output.data(using: .utf8),
               let result = try? JSONDecoder().decode(AnalyzeResult.self, from: data) {
                check("entries", (result.entries?.count ?? 0) > 0,
                      "\(result.entries?.count ?? 0) mục con")
                check("total", (result.totalSize ?? 0) > 0,
                      ByteFormatter.string(result.totalSize ?? 0))
                check("large_files", (result.largeFiles?.count ?? 0) > 0,
                      "\(result.largeFiles?.count ?? 0) tệp lớn")
            } else {
                check("decode", false, "không giải mã được")
            }
        }

        print("\n=== uninstall --list ===")
        if let entrypoint = NoraLocator.entrypoint {
            let output = runSync(entrypoint, ["uninstall", "--list"], timeout: 180)
            if let start = output.firstIndex(of: "["), let end = output.lastIndex(of: "]"),
               let data = String(output[start...end]).data(using: .utf8),
               let apps = try? JSONDecoder().decode([InstalledApp].self, from: data) {
                check("apps", !apps.isEmpty, "\(apps.count) ứng dụng")
                let sized = apps.filter { $0.sizeBytes != nil }
                check("có dung lượng", !sized.isEmpty, "\(sized.count)/\(apps.count)")
                for app in sized.sorted(by: { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }).prefix(5) {
                    print("        · \(app.name): \(ByteFormatter.string(app.sizeBytes ?? 0))")
                }
            } else {
                check("decode", false, "không giải mã được danh sách")
            }
        }

        print("\n=== history --json ===")
        if let entrypoint = NoraLocator.entrypoint {
            let output = runSync(entrypoint, ["history", "--json", "--limit", "5"], timeout: 30)
            if let start = output.firstIndex(of: "{"),
               let data = String(output[start...]).data(using: .utf8),
               let decoded = try? JSONDecoder().decode(HistoryResponse.self, from: data) {
                check("sessions", true, "\(decoded.sessions?.count ?? 0) phiên")
            } else {
                check("decode", false, "không giải mã được")
            }
        }

        print("\n\(failures == 0 ? "Tất cả kiểm tra đều đạt." : "\(failures) kiểm tra thất bại.")\n")
        return failures == 0 ? 0 : 1
    }

    /// Blocking runner: the self-test is a script, not a UI, so it wants
    /// straight-line execution rather than the async path.
    private static func runSync(
        _ executable: URL, _ arguments: [String], timeout: TimeInterval = 60
    ) -> String {
        // Same shape as ProcessRunner's own buffers: the Task writes from
        // whatever thread it lands on while this function reads after the
        // semaphore, so the value crosses threads and needs a lock rather than
        // a captured `var`.
        let box = ResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task {
            let result = await ProcessRunner.run(executable, arguments: arguments, timeout: timeout)
            box.set(result.stdout)
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + timeout + 10)
        return box.value
    }

    private final class ResultBox: @unchecked Sendable {
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
