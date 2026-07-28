import SwiftUI

/// Which bubble the user tapped.
enum MetricKind: String, Identifiable {
    case cpu, memory, disk, network, thermal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Bộ nhớ"
        case .disk: return "Ổ đĩa"
        case .network: return "Mạng"
        case .thermal: return "Nhiệt độ"
        }
    }

    /// Same hue as the bubble, so the panel reads as that bubble opened up.
    var tint: Color {
        switch self {
        case .cpu: return Theme.cpu
        case .memory: return Theme.ram
        case .disk: return Theme.disk
        case .network: return Theme.net
        case .thermal: return Theme.heat
        }
    }

    var light: Color {
        switch self {
        case .cpu: return Theme.cpuLight
        case .memory: return Theme.ramLight
        case .disk: return Theme.diskLight
        case .network: return Theme.netLight
        case .thermal: return Theme.heatLight
        }
    }
}

/// The panel that slides in under the bubbles when one is tapped.
///
/// Everything here comes from the snapshot the popover already has, so opening
/// a detail costs no extra collection — it only shows fields the compact view
/// has no room for.
struct MetricDetailPanel: View {
    let kind: MetricKind
    let snapshot: StatusSnapshot?
    let cpuHistory: [Double]
    let ramHistory: [Double]
    let onClose: () -> Void

    /// Owned by the panel: the process list is only worth reading while the
    /// memory detail is actually open.
    @StateObject private var processMemory = ProcessMemoryService()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            VStack(alignment: .leading, spacing: 7) {
                switch kind {
                case .cpu: cpuDetail
                case .memory: memoryDetail
                case .disk: diskDetail
                case .network: networkDetail
                case .thermal: thermalDetail
                }
            }
            .padding(.horizontal, 13)
            .padding(.bottom, 11)
        }
        .background(Theme.void)
        .onAppear {
            if kind == .memory { processMemory.refreshIfStale() }
        }
        .onChange(of: kind) { _, new in
            if new == .memory { processMemory.refreshIfStale() }
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Circle().fill(kind.tint).frame(width: 8, height: 8)
            Text(kind.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(5)
                    .background(Circle().fill(Theme.card))
            }
            .buttonStyle(.plain)
            .help("Đóng")
        }
        .padding(.horizontal, 13)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Per-metric bodies

    private var cpuDetail: some View {
        let cpu = snapshot?.cpu

        return Group {
            if let history = trimmedHistory(cpuHistory) {
                SparklineView(values: history, color: kind.light, lineWidth: 1.4)
                    .frame(height: 26)
                    .padding(.bottom, 2)
            }

            row("Đang dùng", percentText(cpu?.usage))
            row("Tải trung bình", loadText)
            if let count = cpu?.coreCount {
                row("Số nhân", coreText(total: count, p: cpu?.pCoreCount, e: cpu?.eCoreCount))
            }

            if let cores = cpu?.perCore, !cores.isEmpty {
                Divider().overlay(Theme.hairline).padding(.vertical, 3)
                Text("TỪNG NHÂN")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textSecondary)
                coreGrid(cores)
            }

            if let processes = snapshot?.topProcesses, !processes.isEmpty {
                Divider().overlay(Theme.hairline).padding(.vertical, 3)
                Text("NGỐN CPU NHẤT")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textSecondary)
                ForEach(processes.prefix(4)) { process in
                    HStack(spacing: 8) {
                        Text(process.name ?? "—")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.0f%%", process.cpu ?? 0))
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.loadColor(process.cpu ?? 0))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var memoryDetail: some View {
        let memory = snapshot?.memory

        return Group {
            if let history = trimmedHistory(ramHistory) {
                SparklineView(values: history, color: kind.light, lineWidth: 1.4)
                    .frame(height: 26)
                    .padding(.bottom, 2)
            }

            row("Đang dùng", bytes(memory?.used), accent: true)
            row("Còn trống", bytes(memory?.available))
            row("Cache", bytes(memory?.cached))
            row("Tổng", bytes(memory?.total))

            if let swapUsed = memory?.swapUsed, swapUsed > 0 {
                Divider().overlay(Theme.hairline).padding(.vertical, 3)
                row("Swap đang dùng", bytes(swapUsed))
                row("Swap tổng", bytes(memory?.swapTotal))
                Text("Swap là bộ nhớ tràn ra ổ đĩa — dùng nhiều nghĩa là RAM đang thiếu.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(Theme.hairline).padding(.vertical, 3)
            appMemoryList
        }
    }

    /// "What is actually holding my RAM", grouped per application.
    @ViewBuilder
    private var appMemoryList: some View {
        HStack {
            Text("APP NGỐN RAM NHẤT")
                .font(.system(size: 9, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if processMemory.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            }
        }

        if processMemory.apps.isEmpty {
            Text(processMemory.isLoading ? "Đang đọc…" : "Chưa đọc được danh sách tiến trình")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted)
        } else {
            let top = Array(processMemory.apps.prefix(6))
            let widest = top.first?.bytes ?? 1

            ForEach(top) { app in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.name)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        if app.processCount > 1 {
                            Text("\(app.processCount) tiến trình")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textMuted)
                        }
                        Spacer()
                        Text(ByteFormatter.string(app.bytes))
                            .font(.system(size: 11))
                            .foregroundStyle(kind.light)
                            .monospacedDigit()
                    }

                    // Bars are relative to the heaviest app, so the shape of
                    // the list answers "who dominates" before any number is
                    // read.
                    Capsule()
                        .fill(Theme.hairline)
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(kind.tint)
                                    .frame(width: geo.size.width
                                           * CGFloat(Double(app.bytes) / Double(max(widest, 1))))
                            }
                        }
                        .frame(height: 4)
                }
                .padding(.vertical, 1)
            }

            // RSS counts memory shared between processes once per process, so
            // a grouped total reads higher than Activity Monitor's figure for
            // the same app. Say so rather than letting the difference look
            // like a bug.
            Text("Cộng dồn theo tiến trình con — số này nhỉnh hơn Activity Monitor "
                 + "vì bộ nhớ dùng chung bị tính nhiều lần.")
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    private var diskDetail: some View {
        Group {
            ForEach(snapshot?.disks ?? []) { disk in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(disk.mount ?? "—")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        if disk.external == true {
                            Text("gắn ngoài")
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.diskLight)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Theme.diskDeep))
                        }
                        Spacer()
                        Text("\(Int((disk.usedPercent ?? 0).rounded()))%")
                            .font(.system(size: 11))
                            .foregroundStyle(kind.light)
                            .monospacedDigit()
                    }

                    Capsule()
                        .fill(Theme.hairline)
                        .frame(height: 5)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(kind.tint)
                                    .frame(width: geo.size.width * CGFloat((disk.usedPercent ?? 0) / 100))
                            }
                        }
                        .frame(height: 5)

                    HStack {
                        Text("\(bytes(disk.used)) đã dùng")
                        Spacer()
                        Text("\(bytes((disk.total ?? 0) - (disk.used ?? 0))) trống")
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                }
                .padding(.bottom, 3)
            }

            if let io = snapshot?.diskIO {
                Divider().overlay(Theme.hairline).padding(.vertical, 3)
                row("Đọc", RateFormatter.string((io.readRate ?? 0) / 1_000_000))
                row("Ghi", RateFormatter.string((io.writeRate ?? 0) / 1_000_000))
            }
        }
    }

    private var networkDetail: some View {
        let active = (snapshot?.network ?? []).filter {
            ($0.rxRateMBs ?? 0) > 0 || ($0.txRateMBs ?? 0) > 0 || ($0.ip?.isEmpty == false)
        }

        return Group {
            let rates = snapshot?.networkRates
            row("Tải xuống", RateFormatter.string(rates?.down ?? 0), accent: true)
            row("Tải lên", RateFormatter.string(rates?.up ?? 0))

            if !active.isEmpty {
                Divider().overlay(Theme.hairline).padding(.vertical, 3)
                Text("TỪNG GIAO DIỆN")
                    .font(.system(size: 9, weight: .medium))
                    .tracking(0.5)
                    .foregroundStyle(Theme.textSecondary)

                ForEach(active) { iface in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(iface.name ?? "—")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            if let ip = iface.ip, !ip.isEmpty {
                                Text(ip)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            Text("↓ " + RateFormatter.string(iface.rxRateMBs ?? 0))
                            Text("↑ " + RateFormatter.string(iface.txRateMBs ?? 0))
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted)
                        .monospacedDigit()
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private var thermalDetail: some View {
        let thermal = snapshot?.thermal
        let battery = snapshot?.macBattery

        return Group {
            if let temp = positive(thermal?.cpuTemp) {
                row("CPU", String(format: "%.0f°C", temp), accent: true)
            }
            if let temp = positive(thermal?.gpuTemp) {
                row("GPU", String(format: "%.0f°C", temp))
            }
            if let temp = positive(thermal?.batteryTemp) {
                row("Pin", String(format: "%.0f°C", temp), accent: thermal?.cpuTemp ?? 0 <= 0)
            }
            if let speed = thermal?.fanSpeed, speed > 0 {
                row("Quạt", "\(speed) vòng/phút")
            }

            // On Apple silicon the CPU sensor needs elevated access, so the
            // reading shown is the battery's. Say so instead of letting the
            // number look like a CPU temperature.
            if positive(thermal?.cpuTemp) == nil {
                Text("macOS không mở cảm biến CPU cho app thường — số hiển thị là nhiệt độ pin.")
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let power = thermal?.systemPower, power > 0 {
                Divider().overlay(Theme.hairline).padding(.vertical, 3)
                row("Điện năng hệ thống", String(format: "%.1f W", power))
            }

            if let battery {
                Divider().overlay(Theme.hairline).padding(.vertical, 3)
                row("Pin", "\(battery.percent ?? 0)%")
                if let health = battery.health, !health.isEmpty { row("Tình trạng", health) }
                if let cycles = battery.cycleCount { row("Chu kỳ sạc", "\(cycles)") }
                if let left = battery.timeLeft, !left.isEmpty, left != "0:00" {
                    row("Còn dùng được", left)
                }
            }
        }
    }

    // MARK: - Pieces

    private func row(_ label: String, _ value: String, accent: Bool = false) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: accent ? .medium : .regular))
                .foregroundStyle(accent ? kind.light : Theme.textPrimary)
                .monospacedDigit()
        }
    }

    /// Per-core bars, four to a row.
    private func coreGrid(_ cores: [Double]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

        return LazyVGrid(columns: columns, spacing: 5) {
            ForEach(Array(cores.enumerated()), id: \.offset) { index, usage in
                VStack(spacing: 2) {
                    Capsule()
                        .fill(Theme.hairline)
                        .frame(height: 4)
                        .overlay(alignment: .leading) {
                            GeometryReader { geo in
                                Capsule()
                                    .fill(Theme.loadColor(usage))
                                    .frame(width: geo.size.width * CGFloat(min(usage, 100) / 100))
                            }
                        }
                        .frame(height: 4)
                    Text("\(index + 1)")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textMuted)
                }
            }
        }
    }

    // MARK: - Formatting

    private func trimmedHistory(_ values: [Double]) -> [Double]? {
        values.count > 1 ? Array(values.suffix(40)) : nil
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return String(format: "%.1f%%", value)
    }

    private func bytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        return ByteFormatter.string(value)
    }

    private var loadText: String {
        guard let cpu = snapshot?.cpu, let load1 = cpu.load1 else { return "—" }
        return String(format: "%.2f · %.2f · %.2f", load1, cpu.load5 ?? 0, cpu.load15 ?? 0)
    }

    private func coreText(total: Int, p: Int?, e: Int?) -> String {
        guard let p, let e, p > 0, e > 0 else { return "\(total)" }
        return "\(total) (\(p) hiệu năng + \(e) tiết kiệm)"
    }
}
