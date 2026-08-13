import SwiftUI

/// One metric, reduced to what a row needs to draw.
///
/// Built once per snapshot and shared by the menubar rows and the overview
/// tiles, so the two cannot disagree about what "45%" means or which colour it
/// is drawn in — the popover and the window used to derive these separately.
struct MetricReadout: Identifiable {
    let metric: Metric
    /// The headline figure, already formatted.
    let value: String
    /// The unit or qualifier that goes under (or after) the value.
    let caption: String?
    /// 0…1, for the meter. Network and temperature have no natural ceiling, so
    /// they are scaled against a "busy" reference rather than a true maximum.
    let fraction: Double
    /// Rolling history, when there is one. Only CPU and memory have one.
    let series: [Double]

    var id: String { metric.rawValue }

    var tint: Color {
        // CPU is the one metric whose colour is allowed to move: it is the one
        // that routinely pegs, and a red row is the point of the warning.
        metric == .cpu ? Theme.loadTint(fraction * 100) : metric.tint
    }

    static func all(
        snapshot: StatusSnapshot?,
        cpuHistory: [Double],
        ramHistory: [Double]
    ) -> [MetricReadout] {
        let cpu = snapshot?.cpu?.usage ?? 0
        let ram = snapshot?.memory?.usedPercent ?? 0
        let disk = snapshot?.primaryDisk?.usedPercent ?? 0
        let down = snapshot?.networkRates.down ?? 0
        let temperature = temperature(snapshot)

        return [
            MetricReadout(
                metric: .cpu,
                value: percent(cpu),
                caption: snapshot?.cpu?.load1.map { String(format: "tải %.2f", $0) },
                fraction: cpu / 100,
                series: cpuHistory
            ),
            MetricReadout(
                metric: .memory,
                value: gigabytes(snapshot?.memory?.used),
                caption: snapshot?.memory?.total.map {
                    "trên \(Int((Double($0) / 1_073_741_824).rounded())) GB · \(percent(ram))"
                },
                fraction: ram / 100,
                series: ramHistory
            ),
            MetricReadout(
                metric: .disk,
                value: percent(disk),
                caption: freeSpace(snapshot?.primaryDisk),
                fraction: disk / 100,
                series: []
            ),
            MetricReadout(
                metric: .network,
                value: RateFormatter.string(down),
                caption: "lên " + RateFormatter.string(snapshot?.networkRates.up ?? 0),
                // 10 MB/s counts as a busy link for sizing purposes.
                fraction: min(down / 10, 1),
                series: []
            ),
            MetricReadout(
                metric: .thermal,
                value: temperature > 0 ? "\(Int(temperature.rounded()))°" : "—",
                caption: snapshot?.thermal?.fanSpeed.flatMap {
                    $0 > 0 ? "quạt \($0) v/p" : nil
                },
                // 30 °C idle to 80 °C hot is the band a laptop actually lives in.
                fraction: min(max(temperature - 30, 0) / 50, 1),
                series: []
            ),
        ]
    }

    /// CPU temperature needs elevated access on Apple silicon; the battery
    /// sensor is always readable and tracks it closely enough.
    private static func temperature(_ snapshot: StatusSnapshot?) -> Double {
        for candidate in [snapshot?.thermal?.cpuTemp, snapshot?.thermal?.batteryTemp] {
            if let value = candidate, value > 0 { return value }
        }
        return 0
    }

    private static func percent(_ value: Double) -> String {
        value > 0 ? "\(Int(value.rounded()))%" : "—"
    }

    private static func gigabytes(_ bytes: Int64?) -> String {
        guard let bytes, bytes > 0 else { return "—" }
        return String(format: "%.1f GB", Double(bytes) / 1_073_741_824)
    }

    private static func freeSpace(_ disk: StatusSnapshot.Disk?) -> String? {
        guard let disk, let total = disk.total, let used = disk.used, total > 0 else { return nil }
        return "\(ByteFormatter.string(total - used)) trống"
    }
}

/// The compact metric list at the top of the popover.
///
/// A list, not the drifting bubble constellation it replaces. Rows put the five
/// numbers on a single reading axis so they can be compared at a glance, and
/// they carry no repeating animation — the bubbles' `repeatForever` bob was
/// both a permanent hold on the render loop and the cause of the selection ring
/// landing off-centre, since `.offset` moves what is drawn but not where the
/// ring was laid out.
struct MetricList: View {
    let readouts: [MetricReadout]
    var selected: Metric?
    var onSelect: (Metric) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(readouts) { readout in
                MetricRow(
                    readout: readout,
                    isSelected: selected == readout.metric,
                    action: { onSelect(readout.metric) }
                )
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }
}

struct MetricRow: View {
    let readout: MetricReadout
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: readout.metric.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(readout.tint)
                    .frame(width: 17)

                Text(readout.metric.shortTitle)
                    .font(.callout)
                    .frame(width: 42, alignment: .leading)

                Text(readout.value)
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 64, alignment: .trailing)

                trailingVisual
                    .frame(maxWidth: .infinity)

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isSelected ? 90 : 0))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .fill(background)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(readout.caption ?? readout.metric.title)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(readout.metric.title): \(readout.value)")
        .accessibilityHint("Mở chi tiết")
    }

    /// A trend line for CPU, a meter for everything else.
    ///
    /// Only CPU earns the sparkline. The others are shares of a known total, so
    /// a meter answers "how full" directly — and memory in particular barely
    /// moves minute to minute, which drew as a flat rule carrying no
    /// information at all.
    @ViewBuilder
    private var trailingVisual: some View {
        if readout.metric == .cpu, readout.series.count > 1 {
            Sparkline(values: Array(readout.series.suffix(48)), tint: readout.tint)
                .frame(height: 15)
        } else {
            Meter(value: readout.fraction, tint: readout.tint)
        }
    }

    private var background: Color {
        if isSelected { return Color.accentColor.opacity(0.15) }
        return hovering ? Theme.separator.opacity(0.5) : .clear
    }
}
