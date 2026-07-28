import SwiftUI

struct OverviewTab: View {
    @EnvironmentObject var stream: StatusStream
    @EnvironmentObject var batteries: DeviceBatteryService

    private var snapshot: StatusSnapshot? { stream.snapshot }

    var body: some View {
        TabScaffold(title: "Tổng quan", subtitle: hardwareLine) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .top, spacing: 16) {
                        healthRing
                        metricCards
                    }

                    devicesCard
                    processesCard
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 26)
            }
        }
    }

    private var hardwareLine: String {
        guard let hardware = snapshot?.hardware else { return "Đang kết nối…" }
        return [hardware.model, hardware.cpuModel, hardware.totalRAM, hardware.osVersion]
            .compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    private var healthRing: some View {
        ZStack {
            Circle()
                .stroke(Theme.hairline, lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(snapshot?.healthScore ?? 0) / 100)
                .stroke(healthColor, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.5), value: snapshot?.healthScore)

            VStack(spacing: 2) {
                Text("Sức khỏe máy")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                Text(snapshot?.healthScore.map(String.init) ?? "—")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Text(snapshot?.healthScoreMsg ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(healthColor)
            }
        }
        .frame(width: 168, height: 168)
    }

    private var healthColor: Color {
        switch snapshot?.healthScore ?? 0 {
        case 80...: return Theme.good
        case 55..<80: return Theme.heat
        case 1..<55: return Theme.danger
        default: return Theme.textMuted
        }
    }

    private var metricCards: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 158), spacing: 10)],
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
    }

    private var memoryText: String {
        guard let used = snapshot?.memory?.used else { return "—" }
        return String(format: "%.1f GB", Double(used) / 1_073_741_824)
    }

    private var memoryFootnote: String? {
        guard let percent = snapshot?.memory?.usedPercent else { return nil }
        var text = "\(Int(percent.rounded()))% đã dùng"
        if let swap = snapshot?.memory?.swapUsed, swap > 0 {
            text += " · swap \(ByteFormatter.string(swap))"
        }
        return text
    }

    private var diskText: String {
        guard let disk = snapshot?.primaryDisk, let used = disk.used else { return "—" }
        return ByteFormatter.string(used)
    }

    private var diskFootnote: String? {
        guard let disk = snapshot?.primaryDisk,
              let total = disk.total, let used = disk.used else { return nil }
        return "\(ByteFormatter.string(total - used)) trống / \(ByteFormatter.string(total))"
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

    private var processesCard: some View {
        Card(title: "Tiến trình ngốn CPU") {
            VStack(spacing: 0) {
                ForEach((snapshot?.topProcesses ?? []).prefix(6)) { process in
                    HStack(spacing: 10) {
                        Text(process.name ?? "—")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer()
                        if let memory = process.memoryBytes {
                            Text(ByteFormatter.string(memory))
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted)
                                .monospacedDigit()
                        }
                        Text(String(format: "%.0f%%", process.cpu ?? 0))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.loadColor(process.cpu ?? 0))
                            .frame(width: 46, alignment: .trailing)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 5)
                }
            }
        }
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
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()

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
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
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
                        .font(.system(size: 11))
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
