import SwiftUI

struct OverviewTab: View {
    @EnvironmentObject var stream: StatusStream
    @EnvironmentObject var batteries: DeviceBatteryService

    /// Only read while this tab is on screen.
    @StateObject private var processMemory = ProcessMemoryService()

    private var snapshot: StatusSnapshot? { stream.snapshot }

    var body: some View {
        TabScaffold(title: "Tổng quan", subtitle: hardwareLine) {
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
    }

    private var hardwareLine: String {
        guard let hardware = snapshot?.hardware else { return "Đang kết nối…" }
        return [hardware.model, hardware.cpuModel, hardware.totalRAM, hardware.osVersion]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    // MARK: - Headline

    /// Score plus the four live metrics, on one row.
    ///
    /// The ring was 168pt of mostly empty space next to a grid that pushed its
    /// fourth card onto a line of its own — so the one comparison the row
    /// exists for, four metrics side by side, was the thing it broke.
    private var headline: some View {
        HStack(alignment: .top, spacing: 14) {
            healthCard

            // Four fixed columns, not an adaptive grid: adaptive dropped the
            // fourth card onto a row of its own as soon as the window narrowed,
            // and a row of three metrics beside one stranded card is exactly
            // the comparison this strip exists to prevent.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4),
                spacing: 10
            ) {
                MetricCard(
                    title: "CPU",
                    value: "\(Int((snapshot?.cpu?.usage ?? 0).rounded()))%",
                    accent: Theme.cpu,
                    footnote: snapshot?.cpu?.load1.map { String(format: "tải %.2f", $0) },
                    sparkline: stream.cpuHistory
                )
                MetricCard(
                    title: "Bộ nhớ",
                    value: memoryText,
                    accent: Theme.ram,
                    footnote: memoryFootnote,
                    sparkline: stream.ramHistory
                )
                MetricCard(
                    title: "Ổ đĩa",
                    value: diskText,
                    accent: Theme.disk,
                    footnote: diskFootnote,
                    progress: (snapshot?.primaryDisk?.usedPercent ?? 0) / 100
                )
                MetricCard(
                    title: "Mạng",
                    value: "↓ " + RateFormatter.string(snapshot?.networkRates.down ?? 0),
                    accent: Theme.net,
                    footnote: "↑ " + RateFormatter.string(snapshot?.networkRates.up ?? 0)
                )
            }
            // Without this the grid takes its ideal width and leaves the right
            // side of the row empty while its own cards truncate.
            .frame(maxWidth: .infinity)
        }
    }

    private var healthCard: some View {
        VStack(spacing: 7) {
            Text("SỨC KHỎE MÁY")
                .font(.system(size: 9, weight: .medium))
                .tracking(0.5)
                .foregroundStyle(Theme.textSecondary)

            ZStack {
                Circle().stroke(Theme.hairline, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: CGFloat(snapshot?.healthScore ?? 0) / 100)
                    .stroke(healthColor, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.5), value: snapshot?.healthScore)

                VStack(spacing: 0) {
                    Text(snapshot?.healthScore.map(String.init) ?? "—")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(snapshot?.healthScoreMsg ?? "")
                        .font(.system(size: 9))
                        .foregroundStyle(healthColor)
                }
            }
            .frame(width: 112, height: 112)

            if let uptime = snapshot?.uptime, !uptime.isEmpty {
                Text("bật \(uptime) · \(snapshot?.procs ?? 0) tiến trình")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: 152)
        .padding(.top, 2)
    }

    private var healthColor: Color {
        switch snapshot?.healthScore ?? 0 {
        case 80...: return Theme.good
        case 55..<80: return Theme.heat
        case 1..<55: return Theme.danger
        default: return Theme.textMuted
        }
    }

    // MARK: - Breakdown

    /// Per-core load and the memory split — what the headline cards can only
    /// summarise into one number.
    private var breakdownRow: some View {
        HStack(alignment: .top, spacing: 14) {
            Card(title: "Từng nhân CPU", trailing: coreSummary) {
                if let cores = snapshot?.cpu?.perCore, !cores.isEmpty {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 5), count: 5),
                        spacing: 6
                    ) {
                        ForEach(Array(cores.enumerated()), id: \.offset) { index, usage in
                            VStack(spacing: 2) {
                                Capsule()
                                    .fill(Theme.hairline)
                                    .frame(height: 5)
                                    .overlay(alignment: .leading) {
                                        GeometryReader { geo in
                                            Capsule()
                                                .fill(Theme.loadColor(usage))
                                                .frame(width: geo.size.width
                                                       * CGFloat(min(usage, 100) / 100))
                                        }
                                    }
                                    .frame(height: 5)
                                Text("\(index + 1)")
                                    .font(.system(size: 8))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                } else {
                    Text("Chưa có dữ liệu")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted)
                }
            }

            Card(title: "Bộ nhớ", trailing: pressureLabel) {
                VStack(alignment: .leading, spacing: 8) {
                    memoryBar
                    HStack(spacing: 14) {
                        legend("Đang dùng", Theme.ram, bytes(snapshot?.memory?.used))
                        legend("Cache", Theme.ramLight.opacity(0.55), bytes(snapshot?.memory?.cached))
                        legend("Trống", Theme.hairline, bytes(snapshot?.memory?.available))
                    }
                    if let swap = snapshot?.memory?.swapUsed, swap > 0 {
                        Text("Swap \(ByteFormatter.string(swap)) — RAM đang thiếu nên macOS "
                             + "phải đẩy bớt ra ổ đĩa.")
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.heatLight)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    /// Stacked bar: used, then cache, then free.
    private var memoryBar: some View {
        let total = Double(snapshot?.memory?.total ?? 1)
        let used = min(Double(snapshot?.memory?.used ?? 0) / total, 1)
        let cached = min(Double(snapshot?.memory?.cached ?? 0) / total, 1 - used)

        return GeometryReader { geo in
            HStack(spacing: 1) {
                Rectangle().fill(Theme.ram)
                    .frame(width: geo.size.width * CGFloat(used))
                Rectangle().fill(Theme.ramLight.opacity(0.55))
                    .frame(width: geo.size.width * CGFloat(cached))
                Rectangle().fill(Theme.hairline)
            }
            .clipShape(Capsule())
        }
        .frame(height: 9)
    }

    private func legend(_ label: String, _ color: Color, _ value: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.system(size: 9)).foregroundStyle(Theme.textMuted)
                Text(value).font(.system(size: 10)).foregroundStyle(Theme.textPrimary)
                    .monospacedDigit()
            }
        }
    }

    // MARK: - Processes

    /// The two questions this tab exists to answer: what is burning CPU, and
    /// what is holding RAM. Those have different answers, so both are shown —
    /// the busiest process is routinely not the heaviest one.
    private var processRow: some View {
        HStack(alignment: .top, spacing: 14) {
            Card(title: "Ngốn CPU nhất") {
                VStack(spacing: 0) {
                    ForEach((snapshot?.topProcesses ?? []).prefix(6)) { process in
                        HStack(spacing: 10) {
                            Text(process.name ?? "—")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            if let memory = process.memoryBytes, memory > 0 {
                                Text(ByteFormatter.string(memory))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textMuted)
                                    .monospacedDigit()
                            }
                            Text(String(format: "%.0f%%", process.cpu ?? 0))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.loadColor(process.cpu ?? 0))
                                .frame(width: 42, alignment: .trailing)
                                .monospacedDigit()
                        }
                        .padding(.vertical, 4)
                    }

                    if (snapshot?.topProcesses ?? []).isEmpty {
                        Text("Đang chờ dữ liệu…")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }

            Card(title: "Ngốn RAM nhất",
                 trailing: processMemory.isLoading ? "đang đọc…" : "gộp theo app") {
                VStack(spacing: 0) {
                    let top = Array(processMemory.apps.prefix(6))
                    let widest = top.first?.bytes ?? 1

                    ForEach(top) { app in
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(app.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                if app.processCount > 1 {
                                    Text("\(app.processCount)")
                                        .font(.system(size: 9))
                                        .foregroundStyle(Theme.textMuted)
                                }
                                Spacer(minLength: 6)
                                Text(ByteFormatter.string(app.bytes))
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.ramLight)
                                    .monospacedDigit()
                            }
                            Capsule()
                                .fill(Theme.hairline)
                                .frame(height: 3)
                                .overlay(alignment: .leading) {
                                    GeometryReader { geo in
                                        Capsule().fill(Theme.ram).frame(
                                            width: geo.size.width
                                                * CGFloat(Double(app.bytes) / Double(max(widest, 1)))
                                        )
                                    }
                                }
                                .frame(height: 3)
                        }
                        .padding(.vertical, 3)
                    }

                    if top.isEmpty {
                        Text("Đang đọc danh sách tiến trình…")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
    }

    // MARK: - Storage and devices

    private var storageCard: some View {
        Card(title: "Ổ đĩa", trailing: diskIOLabel) {
            VStack(spacing: 10) {
                ForEach(snapshot?.disks ?? []) { disk in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(disk.mount ?? "—")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                            if let fs = disk.fstype, !fs.isEmpty {
                                Text(fs)
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.textMuted)
                            }
                            if disk.external == true {
                                Text("gắn ngoài")
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.diskLight)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Theme.diskDeep))
                            }
                            Spacer()
                            Text("\(ByteFormatter.string((disk.total ?? 0) - (disk.used ?? 0))) trống")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textMuted)
                            Text("\(Int((disk.usedPercent ?? 0).rounded()))%")
                                .font(.system(size: 11))
                                .foregroundStyle(diskColor(disk.usedPercent ?? 0))
                                .monospacedDigit()
                        }
                        Capsule()
                            .fill(Theme.hairline)
                            .frame(height: 6)
                            .overlay(alignment: .leading) {
                                GeometryReader { geo in
                                    Capsule()
                                        .fill(diskColor(disk.usedPercent ?? 0))
                                        .frame(width: geo.size.width
                                               * CGFloat((disk.usedPercent ?? 0) / 100))
                                }
                            }
                            .frame(height: 6)
                    }
                }
            }
        }
    }

    private var devicesCard: some View {
        Card(title: "Pin thiết bị") {
            if batteries.devices.isEmpty {
                Text("Chưa thấy thiết bị nào có báo pin")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
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

    private func diskColor(_ percent: Double) -> Color {
        percent >= 90 ? Theme.danger : (percent >= 75 ? Theme.heat : Theme.disk)
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

    private var memoryText: String {
        guard let used = snapshot?.memory?.used else { return "—" }
        return String(format: "%.1f GB", Double(used) / 1_073_741_824)
    }

    private var memoryFootnote: String? {
        guard let percent = snapshot?.memory?.usedPercent else { return nil }
        // Swap deliberately left out: it did not fit here and was truncated
        // mid-number ("swap 95…"), and the breakdown card below already calls
        // it out in full, with the reason it matters.
        return "\(Int(percent.rounded()))% đã dùng"
    }

    private var diskText: String {
        guard let disk = snapshot?.primaryDisk, let used = disk.used else { return "—" }
        return ByteFormatter.string(used)
    }

    private var diskFootnote: String? {
        guard let disk = snapshot?.primaryDisk,
              let total = disk.total, let used = disk.used else { return nil }
        return "\(ByteFormatter.string(total - used)) trống"
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let accent: Color
    var footnote: String?
    var sparkline: [Double] = []
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(title)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
            }
            Text(value)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            if !sparkline.isEmpty {
                SparklineView(values: sparkline, color: accent)
                    .frame(height: 20)
            } else if let progress {
                Capsule()
                    .fill(Theme.hairline)
                    .frame(height: 5)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Capsule()
                                .fill(accent)
                                .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)))
                        }
                    }
                    .frame(height: 5)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(12)
        // Reserve the same height for every card: two of the four carry a
        // sparkline and two do not, and top-aligning unequal cards left the
        // row with a ragged bottom edge.
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
    }
}

struct Card<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panel))
    }
}
