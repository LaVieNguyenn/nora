import SwiftUI
import AppKit

/// Everything that appears when the menubar item is clicked.
///
/// The popover paints no background of its own: `NSPopover` already draws the
/// system's vibrant material behind it, and the opaque panel colour that used
/// to be here covered it up and left the popover looking like a foreign window
/// in light mode.
struct MenuBarPopover: View {
    @EnvironmentObject var stream: StatusStream
    @EnvironmentObject var batteries: DeviceBatteryService

    /// Which metric's detail panel is open, if any.
    @State private var openMetric: Metric?

    private var readouts: [MetricReadout] {
        MetricReadout.all(
            snapshot: stream.snapshot,
            cpuHistory: stream.cpuHistory,
            ramHistory: stream.ramHistory
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if let problem = NoraLocator.cachedSetupProblem {
                NoticeBanner(message: problem)
                    .padding(.horizontal, 10)
                    .padding(.top, 10)
            }

            MetricList(
                readouts: readouts,
                selected: openMetric,
                onSelect: { metric in
                    // Tapping the open row closes it, so one gesture both opens
                    // and dismisses.
                    withAnimation(.easeOut(duration: 0.15)) {
                        openMetric = (openMetric == metric) ? nil : metric
                    }
                }
            )

            if let openMetric {
                Divider()
                MetricDetailPanel(
                    metric: openMetric,
                    snapshot: stream.snapshot,
                    cpuHistory: stream.cpuHistory,
                    ramHistory: stream.ramHistory,
                    onClose: {
                        withAnimation(.easeOut(duration: 0.15)) { self.openMetric = nil }
                    }
                )
            }

            Divider()

            DeviceBatteryList(
                devices: batteries.devices,
                phoneStatus: batteries.phoneStatus
            )
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            footer
        }
        .frame(width: 330)
        .onAppear {
            // `NORA_POPOVER_OPEN=<metric>` opens one detail panel on show. The
            // regression probe cannot synthesise a click on a SwiftUI row, so
            // this is how the panels get exercised without a human.
            if let requested = Foundation.ProcessInfo.processInfo
                .environment["NORA_POPOVER_OPEN"] {
                openMetric = Metric(rawValue: requested)
            }
            AppState.shared.popoverDidOpen()
        }
        .onDisappear {
            // Reset so the next open starts on the list rather than whatever
            // panel happened to be showing when it was dismissed.
            openMetric = nil
            AppState.shared.popoverDidClose()
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    MainWindowPresenter.shared.open(tab: .cleanup)
                } label: {
                    Label("Dọn dẹp", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    MainWindowPresenter.shared.open(tab: .analyze)
                } label: {
                    Label("Phân tích", systemImage: "chart.pie")
                        .frame(maxWidth: .infinity)
                }

                Button {
                    MainWindowPresenter.shared.open(tab: .settings)
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Cài đặt")
                .accessibilityLabel("Cài đặt")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            HStack {
                Text(uptimeLabel)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Thoát") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.link)
                    .font(.caption2)
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
