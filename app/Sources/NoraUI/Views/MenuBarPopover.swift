import SwiftUI
import AppKit

/// Everything that appears when the menubar item is clicked.
struct MenuBarPopover: View {
    @EnvironmentObject var stream: StatusStream
    @EnvironmentObject var batteries: DeviceBatteryService
    @EnvironmentObject var settings: AppSettings

    /// Whether the popover is actually on screen. Animations and the finer
    /// collection cadence are gated on this — a menubar app spends almost all
    /// its life with nobody looking at it.
    @State private var visible = false
    /// Which bubble's detail panel is open, if any.
    @State private var openMetric: MetricKind?

    var body: some View {
        VStack(spacing: 0) {
            if let problem = NoraLocator.setupProblem {
                setupBanner(problem)
            }

            MetricsBubbleField(
                snapshot: stream.snapshot,
                cpuHistory: stream.cpuHistory,
                animates: visible,
                selected: openMetric,
                onSelect: { metric in
                    // Tapping the open bubble closes it, so the same gesture
                    // both opens and dismisses.
                    withAnimation(.easeOut(duration: 0.18)) {
                        openMetric = (openMetric == metric) ? nil : metric
                    }
                }
            )
            .frame(height: 178)
            .background(Theme.void)

            if let openMetric {
                Divider().overlay(Theme.hairline)
                MetricDetailPanel(
                    kind: openMetric,
                    snapshot: stream.snapshot,
                    cpuHistory: stream.cpuHistory,
                    ramHistory: stream.ramHistory,
                    onClose: {
                        withAnimation(.easeOut(duration: 0.18)) { self.openMetric = nil }
                    }
                )
            }

            Divider().overlay(Theme.hairline)

            DeviceBatteryList(
                devices: batteries.devices,
                phoneStatus: batteries.phoneStatus
            )
            .padding(.horizontal, 13)
            .padding(.top, 10)
            .padding(.bottom, 8)

            Divider().overlay(Theme.hairline)

            footer
        }
        .frame(width: 340)
        .background(Theme.panel)
        .onAppear {
            visible = true
            // `NORA_POPOVER_OPEN=<metric>` opens one detail panel on show. The
            // regression probe cannot synthesise a tap on a SwiftUI shape, so
            // this is how the panels get exercised without a human.
            if let requested = Foundation.ProcessInfo.processInfo
                .environment["NORA_POPOVER_OPEN"] {
                openMetric = MetricKind(rawValue: requested)
            }
            AppState.shared.popoverDidOpen()
        }
        .onDisappear {
            visible = false
            // Reset so the next open starts on the constellation rather than
            // whatever panel happened to be open when it was dismissed.
            openMetric = nil
            AppState.shared.popoverDidClose()
        }
    }

    private func setupBanner(_ message: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(Theme.heat)
            Text(message)
                .font(.system(size: 10))
                .foregroundStyle(Theme.heatLight)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 13)
        .padding(.vertical, 8)
        .background(Theme.heatDeep)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 7) {
                PopoverButton(title: "Dọn dẹp", symbol: "sparkles", tint: Theme.cpuLight) {
                    MainWindowPresenter.shared.open(tab: .cleanup)
                }
                PopoverButton(title: "Phân tích", symbol: "chart.pie", tint: Theme.diskLight) {
                    MainWindowPresenter.shared.open(tab: .analyze)
                }
                PopoverButton(symbol: "gearshape", tint: Theme.textSecondary) {
                    MainWindowPresenter.shared.open(tab: .settings)
                }
            }

            HStack {
                Text(uptimeLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Button("Thoát") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var uptimeLabel: String {
        guard let snapshot = stream.snapshot else { return "Đang kết nối…" }
        var parts: [String] = []
        if let uptime = snapshot.uptime, !uptime.isEmpty { parts.append("Bật máy \(uptime)") }
        if let procs = snapshot.procs { parts.append("\(procs) tiến trình") }
        return parts.joined(separator: " · ")
    }
}

/// Flat button matching the popover's dark surface. The stock macOS button
/// chrome reads as a light-mode control against this background.
struct PopoverButton: View {
    var title: String?
    let symbol: String
    let tint: Color
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11))
                if let title {
                    Text(title).font(.system(size: 11))
                }
            }
            .foregroundStyle(tint)
            .frame(maxWidth: title == nil ? nil : .infinity)
            .padding(.horizontal, title == nil ? 9 : 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovering ? Theme.border : Theme.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
