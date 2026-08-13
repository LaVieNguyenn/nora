import SwiftUI

struct OverviewTab: View {
    @EnvironmentObject var stream: StatusStream
    @EnvironmentObject var batteries: DeviceBatteryService

    /// Only read while this tab is on screen.
    @StateObject private var processMemory = ProcessMemoryService()

    private var snapshot: StatusSnapshot? { stream.snapshot }

    private var readouts: [MetricReadout] {
        MetricReadout.all(
            snapshot: snapshot,
            cpuHistory: stream.cpuHistory,
            ramHistory: stream.ramHistory
        )
    }

    var body: some View {
        Page(title: "Tổng quan", subtitle: hardwareLine) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headline
                    breakdownRow
                    processRow
                    storageCard
                    devicesCard
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 26)
            }
        }
        .onAppear { processMemory.refreshIfStale() }
        .onDisappear { processMemory.discard() }
    }

    private var hardwareLine: String {
        guard let hardware = snapshot?.hardware else { return "Đang kết nối…" }
        return [hardware.model, hardware.cpuModel, hardware.totalRAM, hardware.osVersion]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    // MARK: - Headline

    /// The health score beside the live metrics, on one row.
    private var headline: some View {
        HStack(alignment: .top, spacing: 14) {
            healthCard

            // Four fixed columns, not an adaptive grid: adaptive dropped the
            // fourth tile onto a row of its own as soon as the window narrowed,
            // and a row of three metrics beside one stranded tile is exactly the
            // comparison this strip exists to prevent.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                spacing: 10
            ) {
                ForEach(readouts.prefix(4)) { readout in
                    // Only CPU gets the trend line, matching the popover rows.
                    // Memory barely moves minute to minute, so its series drew
                    // as a filled slab that carried no information; a meter
                    // says "how full" directly, which is the useful question.
                    let trend = readout.metric == .cpu ? readout.series : []
                    StatTile(
                        metric: readout.metric,
                        value: readout.value,
                        caption: readout.caption,
                        series: trend,
                        progress: trend.isEmpty ? readout.fraction : nil
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var healthCard: some View {
        VStack(spacing: 8) {
            SectionHeading(text: "Sức khỏe máy")

            ZStack {
                Circle()
                    .stroke(Theme.separator, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: CGFloat(snapshot?.healthScore ?? 0) / 100)
                    .stroke(healthTint, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: snapshot?.healthScore)

                VStack(spacing: 0) {
                    Text(snapshot?.healthScore.map(String.init) ?? "—")
                        .font(.system(size: 32, weight: .medium, design: .rounded))
                        .monospacedDigit()
                    Text(snapshot?.healthScoreMsg ?? "")
                        .font(.caption2)
                        .foregroundStyle(healthTint)
                }
            }
            .frame(width: 112, height: 112)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Sức khỏe máy")
            .accessibilityValue("\(snapshot?.healthScore ?? 0) trên 100")

            if let uptime = snapshot?.uptime, !uptime.isEmpty {
                Text("bật \(uptime) · \(snapshot?.procs ?? 0) tiến trình")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 152)
        .padding(.top, 2)
    }

    private var healthTint: Color {
        switch snapshot?.healthScore ?? 0 {
        case 80...: return Theme.success
        case 55..<80: return Theme.warning
        case 1..<55: return Theme.danger
        default: return Theme.tertiaryLabel
        }
    }

    // MARK: - Breakdown

    /// Per-core load and the memory split — what the headline tiles can only
    /// summarise into one number.
    private var breakdownRow: some View {
        HStack(alignment: .top, spacing: 14) {
            SectionCard(title: "Từng nhân CPU", subtitle: coreSummary, systemImage: Metric.cpu.symbol) {
                if let cores = snapshot?.cpu?.perCore, !cores.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 5),
                        spacing: 6
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
                } else {
                    Text("Chưa có dữ liệu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            SectionCard(title: "Bộ nhớ", subtitle: pressureLabel, systemImage: Metric.memory.symbol) {
                VStack(alignment: .leading, spacing: 10) {
                    memoryBar
                    HStack(spacing: 16) {
                        legend("Đang dùng", Metric.memory.tint, bytes(snapshot?.memory?.used))
                        legend("Cache", Metric.memory.tint.opacity(0.45), bytes(snapshot?.memory?.cached))
                        legend("Trống", Theme.separator, bytes(snapshot?.memory?.available))
                    }
                    if let swap = snapshot?.memory?.swapUsed, swap > 0 {
                        Text("Swap \(ByteFormatter.string(swap)) — RAM đang thiếu nên macOS "
                             + "phải đẩy bớt ra ổ đĩa.")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Stacked bar: used, then cache, then free.
    ///
    /// The one place a `GeometryReader` earns its keep — three segments have to
    /// share one width, which no stock control expresses.
    private var memoryBar: some View {
        let total = Double(snapshot?.memory?.total ?? 1)
        let used = min(Double(snapshot?.memory?.used ?? 0) / total, 1)
        let cached = min(Double(snapshot?.memory?.cached ?? 0) / total, 1 - used)

        return GeometryReader { geo in
            HStack(spacing: 1) {
                Rectangle().fill(Metric.memory.tint)
                    .frame(width: geo.size.width * CGFloat(used))
                Rectangle().fill(Metric.memory.tint.opacity(0.45))
                    .frame(width: geo.size.width * CGFloat(cached))
                Rectangle().fill(Theme.separator)
            }
            .clipShape(Capsule())
        }
        .frame(height: 9)
        .accessibilityHidden(true)
    }

    private func legend(_ label: String, _ color: Color, _ value: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption2).foregroundStyle(.secondary)
                Text(value).font(.caption).monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Processes

    /// The two questions this tab exists to answer: what is burning CPU, and
    /// what is holding RAM. Those have different answers, so both are shown —
    /// the busiest process is routinely not the heaviest one.
    private var processRow: some View {
        HStack(alignment: .top, spacing: 14) {
            SectionCard(title: "Ngốn CPU nhất", systemImage: "bolt") {
                VStack(spacing: 0) {
                    ForEach((snapshot?.topProcesses ?? []).prefix(6)) { process in
                        HStack(spacing: 10) {
                            Text(process.name ?? "—")
                                .font(.callout)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 6)
                            if let memory = process.memoryBytes, memory > 0 {
                                Text(ByteFormatter.string(memory))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                            Text(String(format: "%.0f%%", process.cpu ?? 0))
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Theme.loadTint(process.cpu ?? 0))
                                .frame(width: 44, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }

                    if (snapshot?.topProcesses ?? []).isEmpty {
                        Text("Đang chờ dữ liệu…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            SectionCard(
                title: "Ngốn RAM nhất",
                subtitle: processMemory.isLoading ? "đang đọc…" : "gộp theo app",
                systemImage: Metric.memory.symbol
            ) {
                VStack(spacing: 0) {
                    let top = Array(processMemory.apps.prefix(6))
                    let widest = max(top.first?.bytes ?? 1, 1)

                    ForEach(top) { app in
                        RankedBarRow(
                            name: app.name,
                            badge: app.processCount > 1 ? "\(app.processCount)" : nil,
                            value: ByteFormatter.string(app.bytes),
                            fraction: Double(app.bytes) / Double(widest),
                            tint: Metric.memory.tint
                        )
                    }

                    if top.isEmpty {
                        Text("Đang đọc danh sách tiến trình…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Storage and devices

    private var storageCard: some View {
        SectionCard(title: "Ổ đĩa", subtitle: diskIOLabel, systemImage: Metric.disk.symbol) {
            VStack(spacing: 10) {
                ForEach(snapshot?.disks ?? []) { disk in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text(disk.mount ?? "—")
                                .font(.callout.weight(.medium))
                            if let fs = disk.fstype, !fs.isEmpty {
                                Text(fs)
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            if disk.external == true {
                                Text("gắn ngoài")
                                    .font(.caption2)
                                    .foregroundStyle(Metric.disk.tint)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Metric.disk.tint.opacity(0.15), in: Capsule())
                            }
                            Spacer()
                            Text("\(ByteFormatter.string((disk.total ?? 0) - (disk.used ?? 0))) trống")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                            Text("\(Int((disk.usedPercent ?? 0).rounded()))%")
                                .font(.callout)
                                .foregroundStyle(diskTint(disk.usedPercent ?? 0))
                                .monospacedDigit()
                        }
                        Meter(
                            value: (disk.usedPercent ?? 0) / 100,
                            tint: diskTint(disk.usedPercent ?? 0)
                        )
                    }
                }
            }
        }
    }

    private var devicesCard: some View {
        SectionCard(title: "Pin thiết bị", systemImage: "battery.100") {
            if batteries.devices.isEmpty {
                Text("Chưa thấy thiết bị nào có báo pin")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(batteries.devices) { device in
                        DeviceBatteryRow(device: device)
                    }
                }
            }
        }
    }

    // MARK: - Derived text

    private func diskTint(_ percent: Double) -> Color {
        percent >= 90 ? Theme.danger : (percent >= 75 ? Theme.warning : Metric.disk.tint)
    }

    private func bytes(_ value: Int64?) -> String {
        guard let value, value > 0 else { return "—" }
        return ByteFormatter.string(value)
    }

    private var coreSummary: String? {
        guard let cpu = snapshot?.cpu, let total = cpu.coreCount else { return nil }
        guard let p = cpu.pCoreCount, let e = cpu.eCoreCount, p > 0, e > 0 else {
            return "\(total) nhân"
        }
        return "\(p) hiệu năng + \(e) tiết kiệm"
    }

    private var pressureLabel: String? {
        guard let percent = snapshot?.memory?.usedPercent else { return nil }
        return "\(Int(percent.rounded()))% đã dùng"
    }

    private var diskIOLabel: String? {
        guard let io = snapshot?.diskIO else { return nil }
        let read = RateFormatter.string((io.readRate ?? 0) / 1_000_000)
        let write = RateFormatter.string((io.writeRate ?? 0) / 1_000_000)
        return "đọc \(read) · ghi \(write)"
    }
}
