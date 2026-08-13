import SwiftUI

/// The panel that opens under the list when a metric row is clicked.
///
/// Everything here comes from the snapshot the popover already holds, so
/// opening a detail costs no extra collection — it only shows the fields the
/// compact row has no room for.
struct MetricDetailPanel: View {
    let metric: Metric
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

            VStack(alignment: .leading, spacing: 6) {
                switch metric {
                case .cpu: cpuDetail
                case .memory: memoryDetail
                case .disk: diskDetail
                case .network: networkDetail
                case .thermal: thermalDetail
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .onAppear {
            if metric == .memory { processMemory.refreshIfStale() }
        }
        .onChange(of: metric) { _, new in
            if new == .memory { processMemory.refreshIfStale() }
        }
        .onDisappear {
            // Nothing here outlives the panel: the grouped process list is a
            // few hundred entries built from a full `ps` dump, and the popover
            // is closed far more often than it is open.
            processMemory.discard()
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Image(systemName: metric.symbol)
                .font(.caption)
                .foregroundStyle(metric.tint)
            Text(metric.title)
                .font(.subheadline.weight(.medium))
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Đóng")
            .accessibilityLabel("Đóng")
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    // MARK: - Per-metric bodies

    private var cpuDetail: some View {
        let cpu = snapshot?.cpu

        return Group {
            if let history = trimmed(cpuHistory) {
                Sparkline(values: history, tint: metric.tint, filled: true)
                    .frame(height: 30)
                    .padding(.bottom, 2)
            }

            KeyValueRow(label: "Đang dùng", value: percent(cpu?.usage), tint: metric.tint)
            KeyValueRow(label: "Tải trung bình", value: loadText)
            if let count = cpu?.coreCount {
                KeyValueRow(
                    label: "Số nhân",
                    value: coreText(total: count, p: cpu?.pCoreCount, e: cpu?.eCoreCount)
                )
            }

            if let cores = cpu?.perCore, !cores.isEmpty {
                Divider().padding(.vertical, 3)
                SectionHeading(text: "Từng nhân")
                coreGrid(cores)
            }

            if let processes = snapshot?.topProcesses, !processes.isEmpty {
                Divider().padding(.vertical, 3)
                SectionHeading(text: "Ngốn CPU nhất")
                ForEach(processes.prefix(4)) { process in
                    HStack(spacing: 8) {
                        Text(process.name ?? "—")
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(String(format: "%.0f%%", process.cpu ?? 0))
                            .font(.callout)
                            .foregroundStyle(Theme.loadTint(process.cpu ?? 0))
                            .monospacedDigit()
                    }
                }
            }
        }
    }

    private var memoryDetail: some View {
        let memory = snapshot?.memory

        return Group {
            if let history = trimmed(ramHistory) {
                Sparkline(values: history, tint: metric.tint, filled: true)
                    .frame(height: 30)
                    .padding(.bottom, 2)
            }

            KeyValueRow(label: "Đang dùng", value: bytes(memory?.used), tint: metric.tint)
            KeyValueRow(label: "Còn trống", value: bytes(memory?.available))
            KeyValueRow(label: "Cache", value: bytes(memory?.cached))
            KeyValueRow(label: "Tổng", value: bytes(memory?.total))

            if let swapUsed = memory?.swapUsed, swapUsed > 0 {
                Divider().padding(.vertical, 3)
                KeyValueRow(label: "Swap đang dùng", value: bytes(swapUsed), tint: Theme.warning)
                KeyValueRow(label: "Swap tổng", value: bytes(memory?.swapTotal))
                footnote("Swap là bộ nhớ tràn ra ổ đĩa — dùng nhiều nghĩa là RAM đang thiếu.")
            }

            Divider().padding(.vertical, 3)
            appMemoryList
        }
    }

    /// "What is actually holding my RAM", grouped per application.
    @ViewBuilder
    private var appMemoryList: some View {
        HStack {
            SectionHeading(text: "App ngốn RAM nhất")
            Spacer()
            if processMemory.isLoading {
                ProgressView().controlSize(.small).scaleEffect(0.6)
            }
        }

        if processMemory.apps.isEmpty {
            Text(processMemory.isLoading ? "Đang đọc…" : "Chưa đọc được danh sách tiến trình")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            let top = Array(processMemory.apps.prefix(6))
            let widest = max(top.first?.bytes ?? 1, 1)

            ForEach(top) { app in
                RankedBarRow(
                    name: app.name,
                    badge: app.processCount > 1 ? "\(app.processCount) tiến trình" : nil,
                    value: ByteFormatter.string(app.bytes),
                    fraction: Double(app.bytes) / Double(widest),
                    tint: metric.tint
                )
            }

            // RSS counts memory shared between processes once per process, so a
            // grouped total reads higher than Activity Monitor's figure for the
            // same app. Say so rather than letting the difference look like a
            // bug.
            footnote("Cộng dồn theo tiến trình con — số này nhỉnh hơn Activity Monitor "
                     + "vì bộ nhớ dùng chung bị tính nhiều lần.")
        }
    }

    private var diskDetail: some View {
        Group {
            ForEach(snapshot?.disks ?? []) { disk in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(disk.mount ?? "—")
                            .font(.callout.weight(.medium))
                        if disk.external == true {
                            Text("gắn ngoài")
                                .font(.caption2)
                                .foregroundStyle(metric.tint)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(metric.tint.opacity(0.15), in: Capsule())
                        }
                        Spacer()
                        Text("\(Int((disk.usedPercent ?? 0).rounded()))%")
                            .font(.callout)
                            .foregroundStyle(metric.tint)
                            .monospacedDigit()
                    }

                    Meter(value: (disk.usedPercent ?? 0) / 100, tint: metric.tint)

                    HStack {
                        Text("\(bytes(disk.used)) đã dùng")
                        Spacer()
                        Text("\(bytes((disk.total ?? 0) - (disk.used ?? 0))) trống")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.bottom, 3)
            }

            if let io = snapshot?.diskIO {
                Divider().padding(.vertical, 3)
                KeyValueRow(label: "Đọc", value: RateFormatter.string((io.readRate ?? 0) / 1_000_000))
                KeyValueRow(label: "Ghi", value: RateFormatter.string((io.writeRate ?? 0) / 1_000_000))
            }
        }
    }

    private var networkDetail: some View {
        let active = (snapshot?.network ?? []).filter {
            ($0.rxRateMBs ?? 0) > 0 || ($0.txRateMBs ?? 0) > 0 || ($0.ip?.isEmpty == false)
        }
        let rates = snapshot?.networkRates

        return Group {
            KeyValueRow(
                label: "Tải xuống",
                value: RateFormatter.string(rates?.down ?? 0),
                tint: metric.tint
            )
            KeyValueRow(label: "Tải lên", value: RateFormatter.string(rates?.up ?? 0))

            if !active.isEmpty {
                Divider().padding(.vertical, 3)
                SectionHeading(text: "Từng giao diện")

                ForEach(active) { iface in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(iface.name ?? "—")
                                .font(.callout.weight(.medium))
                            if let ip = iface.ip, !ip.isEmpty {
                                Text(ip)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            Text("↓ " + RateFormatter.string(iface.rxRateMBs ?? 0))
                            Text("↑ " + RateFormatter.string(iface.txRateMBs ?? 0))
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                KeyValueRow(label: "CPU", value: String(format: "%.0f°C", temp), tint: metric.tint)
            }
            if let temp = positive(thermal?.gpuTemp) {
                KeyValueRow(label: "GPU", value: String(format: "%.0f°C", temp))
            }
            if let temp = positive(thermal?.batteryTemp) {
                KeyValueRow(
                    label: "Pin",
                    value: String(format: "%.0f°C", temp),
                    tint: positive(thermal?.cpuTemp) == nil ? metric.tint : nil
                )
            }
            if let speed = thermal?.fanSpeed, speed > 0 {
                KeyValueRow(label: "Quạt", value: "\(speed) vòng/phút")
            }

            // On Apple silicon the CPU sensor needs elevated access, so the
            // reading shown is the battery's. Say so instead of letting the
            // number look like a CPU temperature.
            if positive(thermal?.cpuTemp) == nil {
                footnote("macOS không mở cảm biến CPU cho app thường — số hiển thị là nhiệt độ pin.")
            }

            if let power = thermal?.systemPower, power > 0 {
                Divider().padding(.vertical, 3)
                KeyValueRow(label: "Điện năng hệ thống", value: String(format: "%.1f W", power))
            }

            if let battery {
                Divider().padding(.vertical, 3)
                KeyValueRow(label: "Pin", value: "\(battery.percent ?? 0)%")
                if let health = battery.health, !health.isEmpty {
                    KeyValueRow(label: "Tình trạng", value: health)
                }
                if let cycles = battery.cycleCount {
                    KeyValueRow(label: "Chu kỳ sạc", value: "\(cycles)")
                }
                if let left = battery.timeLeft, !left.isEmpty, left != "0:00" {
                    KeyValueRow(label: "Còn dùng được", value: left)
                }
            }
        }
    }

    // MARK: - Pieces

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Per-core meters, four to a row.
    private func coreGrid(_ cores: [Double]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
            spacing: 5
        ) {
            ForEach(Array(cores.enumerated()), id: \.offset) { index, usage in
                VStack(spacing: 2) {
                    Meter(value: min(usage, 100) / 100, tint: Theme.loadTint(usage))
                    Text("\(index + 1)")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    // MARK: - Formatting

    private func trimmed(_ values: [Double]) -> [Double]? {
        values.count > 1 ? Array(values.suffix(40)) : nil
    }

    private func positive(_ value: Double?) -> Double? {
        guard let value, value > 0 else { return nil }
        return value
    }

    private func percent(_ value: Double?) -> String {
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
