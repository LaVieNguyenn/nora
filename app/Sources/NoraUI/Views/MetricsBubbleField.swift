import SwiftUI

/// The bubble constellation at the top of the popover.
///
/// Layout is a fixed arrangement rather than a physics simulation: the eye
/// learns where CPU lives and stops hunting for it. Only the diameters move.
struct MetricsBubbleField: View {
    let snapshot: StatusSnapshot?
    let cpuHistory: [Double]
    /// Only true while the popover is genuinely on screen; drives whether the
    /// bubbles bob, because a repeating animation pins the render loop.
    var animates: Bool = false
    /// Which bubble is open, so it can be marked as selected.
    var selected: MetricKind?
    /// Tapping a bubble opens its detail panel; tapping the open one closes it.
    var onSelect: ((MetricKind) -> Void)?

    /// Relative slots, as fractions of the field. Ordered by prominence.
    private struct Slot {
        let x: Double
        let y: Double
        let base: CGFloat
    }

    private let slots: [Slot] = [
        Slot(x: 0.19, y: 0.40, base: 96),   // CPU
        Slot(x: 0.49, y: 0.29, base: 76),   // RAM
        Slot(x: 0.79, y: 0.46, base: 88),   // Disk
        Slot(x: 0.38, y: 0.78, base: 58),   // Network
        Slot(x: 0.61, y: 0.80, base: 52),   // Thermal
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                StarfieldView()

                bubble(at: 0, in: geo, kind: .cpu) {
                    BubbleView(
                        title: "CPU",
                        value: percentText(cpuUsage),
                        caption: loadCaption,
                        tint: Theme.loadColor(cpuUsage),
                        deep: Theme.cpuDeep,
                        light: Theme.cpuLight,
                        diameter: diameter(for: 0, load: cpuUsage / 100),
                        fill: cpuUsage / 100,
                        sparkline: cpuHistory,
                        driftSeed: 0.2,
                        animatesDrift: animates
                    )
                }

                bubble(at: 1, in: geo, kind: .memory) {
                    BubbleView(
                        title: "RAM",
                        value: ramText,
                        caption: ramCaption,
                        tint: Theme.ram,
                        deep: Theme.ramDeep,
                        light: Theme.ramLight,
                        diameter: diameter(for: 1, load: ramUsage / 100),
                        fill: ramUsage / 100,
                        driftSeed: 1.3,
                        animatesDrift: animates
                    )
                }

                bubble(at: 2, in: geo, kind: .disk) {
                    BubbleView(
                        title: "Ổ đĩa",
                        value: percentText(diskUsage),
                        caption: diskCaption,
                        tint: Theme.disk,
                        deep: Theme.diskDeep,
                        light: Theme.diskLight,
                        diameter: diameter(for: 2, load: diskUsage / 100),
                        fill: diskUsage / 100,
                        driftSeed: 0.7,
                        animatesDrift: animates
                    )
                }

                bubble(at: 3, in: geo, kind: .network) {
                    BubbleView(
                        title: "Mạng",
                        value: RateFormatter.parts(netDown).value,
                        caption: RateFormatter.parts(netDown).unit,
                        tint: Theme.net,
                        deep: Theme.netDeep,
                        light: Theme.netLight,
                        // Network has no natural ceiling, so treat 10 MB/s as
                        // "busy" for sizing purposes.
                        diameter: diameter(for: 3, load: min(netDown / 10, 1)),
                        fill: min(netDown / 10, 1),
                        driftSeed: 1.8,
                        animatesDrift: animates
                    )
                }

                bubble(at: 4, in: geo, kind: .thermal) {
                    BubbleView(
                        title: "Nhiệt",
                        value: tempText,
                        caption: nil,
                        tint: Theme.heat,
                        deep: Theme.heatDeep,
                        light: Theme.heatLight,
                        diameter: diameter(for: 4, load: min(max(temp - 30, 0) / 50, 1)),
                        fill: min(max(temp - 30, 0) / 50, 1),
                        driftSeed: 0.45,
                        animatesDrift: animates
                    )
                }
            }
        }
    }

    /// Place one bubble, and make *the bubble* the thing you can tap.
    ///
    /// The hit area and the selection ring have to be attached before
    /// `.position`, not after: a positioned view expands to fill its parent, so
    /// a `contentShape(Circle())` applied afterwards covers the whole field.
    /// All five then overlapped and the last one in the ZStack swallowed every
    /// tap — which is why every bubble opened the thermal panel, and why the
    /// ring was drawn the size of the entire constellation.
    private func bubble<Content: View>(
        at index: Int, in geo: GeometryProxy, kind: MetricKind,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .overlay {
                // A ring, not a colour change: the bubble keeps its own hue so
                // the open panel and its bubble stay visibly the pair.
                if selected == kind {
                    Circle()
                        .strokeBorder(Theme.textPrimary.opacity(0.6), lineWidth: 1.5)
                        .padding(-3)
                }
            }
            .contentShape(Circle())
            .onTapGesture { onSelect?(kind) }
            .position(
                x: slots[index].x * geo.size.width,
                y: slots[index].y * geo.size.height
            )
    }

    /// Grow a bubble by up to 18% of its base size as its metric climbs.
    private func diameter(for index: Int, load: Double) -> CGFloat {
        let base = slots[index].base
        return base * (1 + CGFloat(min(max(load, 0), 1)) * 0.18)
    }

    // MARK: - Derived values

    private var cpuUsage: Double { snapshot?.cpu?.usage ?? 0 }
    private var ramUsage: Double { snapshot?.memory?.usedPercent ?? 0 }
    private var diskUsage: Double { snapshot?.primaryDisk?.usedPercent ?? 0 }
    private var netDown: Double { snapshot?.networkRates.down ?? 0 }
    private var temp: Double {
        let thermal = snapshot?.thermal
        // CPU temperature needs elevated access on Apple silicon; battery
        // temperature is always readable and tracks it closely enough.
        for candidate in [thermal?.cpuTemp, thermal?.batteryTemp] {
            if let value = candidate, value > 0 { return value }
        }
        return 0
    }

    private func percentText(_ value: Double) -> String {
        value > 0 ? "\(Int(value.rounded()))%" : "—"
    }

    private var ramText: String {
        guard let used = snapshot?.memory?.used, used > 0 else { return "—" }
        return String(format: "%.1f", Double(used) / 1_073_741_824)
    }

    private var ramCaption: String? {
        guard let total = snapshot?.memory?.total, total > 0 else { return nil }
        return "GB / \(Int((Double(total) / 1_073_741_824).rounded()))"
    }

    private var loadCaption: String? {
        guard let load = snapshot?.cpu?.load1 else { return nil }
        return String(format: "tải %.1f", load)
    }

    private var diskCaption: String? {
        guard let disk = snapshot?.primaryDisk,
              let total = disk.total, let used = disk.used, total > 0
        else { return nil }
        let free = Double(total - used) / 1_000_000_000
        return String(format: "%.0f GB trống", free)
    }

    private var tempText: String {
        temp > 0 ? "\(Int(temp.rounded()))°" : "—"
    }
}
