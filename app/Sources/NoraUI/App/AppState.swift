import SwiftUI
import Combine

/// Tabs of the main window.
enum MainTab: String, CaseIterable, Identifiable {
    case overview, cleanup, analyze, uninstall, optimize, history, settings

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overview: return "Tổng quan"
        case .cleanup: return "Dọn dẹp"
        case .analyze: return "Phân tích"
        case .uninstall: return "Gỡ app"
        case .optimize: return "Tối ưu"
        case .history: return "Lịch sử"
        case .settings: return "Cài đặt"
        }
    }

    var symbol: String {
        switch self {
        case .overview: return "circle.hexagongrid"
        case .cleanup: return "sparkles"
        case .analyze: return "chart.pie"
        case .uninstall: return "trash"
        case .optimize: return "slider.horizontal.3"
        case .history: return "clock.arrow.circlepath"
        case .settings: return "gearshape"
        }
    }
}

/// Single owner of every long-lived service, so the menubar and the main
/// window read the same live data instead of each spawning their own collector.
final class AppState: ObservableObject {
    static let shared = AppState()

    let stream = StatusStream()
    let batteries = DeviceBatteryService()
    let settings = AppSettings()
    let cleanup = CleanupService()
    let notifications = NotificationCenterService()

    @Published var selectedTab: MainTab = .overview

    private var macBatteryTimer: Timer?
    private var forwarders: Set<AnyCancellable> = []
    /// Held for the process lifetime; releasing it re-enables App Nap.
    private var appNapAssertion: NSObjectProtocol?

    private init() {
        // The menubar label reads through `AppState`, so changes in the
        // services it wraps have to surface as changes to `AppState` itself.
        for publisher in [stream.objectWillChange, settings.objectWillChange] {
            publisher
                .sink { [weak self] in self?.objectWillChange.send() }
                .store(in: &forwarders)
        }
    }

    func start() {
        // A menubar-only app has no windows, so macOS puts it under App Nap —
        // which suspends dispatch timers. `DispatchQueue.main.asyncAfter` and
        // `Task.sleep` then never fire, silently dropping the collector restart
        // and the post-wake recovery. RunLoop timers survive it, but the honest
        // fix is to declare that this process needs to keep running.
        appNapAssertion = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep],
            reason: "Nora theo dõi chỉ số hệ thống liên tục"
        )

        stream.start(interval: settings.refreshInterval)
        batteries.start()
        notifications.requestAuthorization()
        observeSleepWake()

        // The Mac's own battery comes from IOKit and costs nothing, but the
        // timer still wakes the CPU — a minute is plenty for a battery meter,
        // and the tolerance lets the system coalesce the wake-up.
        let timer = Timer(timeInterval: 60, repeats: true) { _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.batteries.refreshMac()
                self.notifications.evaluate(
                    devices: self.batteries.devices,
                    snapshot: self.stream.snapshot,
                    settings: self.settings
                )
            }
        }
        // Redraw the menubar button on the collector's own cadence, pushing
        // plain values across rather than letting the controller read
        // main-actor state from an AppKit callback.
        stream.$snapshot
            .sink { [weak self] _ in
                guard let self else { return }
                StatusItemController.shared.apply(
                    title: self.menubarText,
                    tint: NSColor(self.menubarTint)
                )
            }
            .store(in: &forwarders)
        timer.tolerance = 15
        RunLoop.main.add(timer, forMode: .common)
        macBatteryTimer = timer
    }

    func stop() {
        stream.stop()
        batteries.stop()
        macBatteryTimer?.invalidate()
    }

    /// Tear the collector down before the machine sleeps and rebuild it on
    /// wake.
    ///
    /// Across a sleep the child's pipe and the rate baselines are both stale,
    /// and every probe the app shells out to (Bluetooth, Wi-Fi, the iPhone
    /// bridge) is briefly slow or absent while the hardware comes back. Doing
    /// this explicitly beats discovering it through a timeout.
    private func observeSleepWake() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main
        ) { _ in
            DispatchQueue.main.async {
                AppState.shared.stream.stop()
                AppState.shared.batteries.stop()
            }
        }

        center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { _ in
            // Give the Bluetooth and network stacks a moment to come back
            // before asking them anything.
            //
            // A GCD timer, not `Task.sleep`: a suspended task never resumes in
            // this process, so a sleeping task here would silently never
            // restart the collector after the lid opened.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                DispatchQueue.main.async {
                    let state = AppState.shared
                    state.stream.start(interval: state.settings.refreshInterval)
                    state.batteries.start()
                }
            }
        }
    }

    /// While the popover is open the numbers should move at the rate the user
    /// chose; while it is closed the menubar only shows one figure, so a much
    /// slower cadence is indistinguishable and costs far less.
    func popoverDidOpen() {
        isPopoverOpen = true
        batteries.setActive(true)
        // The accessory batteries are the reason the popover was opened often
        // enough to be worth a fresh read on the way in.
        Task { await batteries.refreshBluetooth() }
        batteries.refreshMac()
    }

    func popoverDidClose() {
        isPopoverOpen = false
        batteries.setActive(false)
    }

    /// The collector runs at one cadence for the whole session and is never
    /// restarted to follow the popover.
    ///
    /// Throughput is a rate between two samples, so a restart throws away the
    /// baseline and reports 0 for the first two frames — which landed exactly
    /// when the popover opened, making the network bubble read 0.0 every time
    /// it was looked at. Its measured cost is a fraction of a percent of one
    /// core, so there is nothing to win by cycling it.
    private(set) var isPopoverOpen = false

    /// Text shown next to the menubar icon.
    var menubarText: String {
        guard settings.showValueInMenubar, let snapshot = stream.snapshot else { return "" }

        switch settings.menubarMetric {
        case .cpu:
            return "\(Int((snapshot.cpu?.usage ?? 0).rounded()))%"
        case .memory:
            return "\(Int((snapshot.memory?.usedPercent ?? 0).rounded()))%"
        case .disk:
            return "\(Int((snapshot.primaryDisk?.usedPercent ?? 0).rounded()))%"
        case .temperature:
            let temp = snapshot.thermal?.cpuTemp ?? snapshot.thermal?.batteryTemp ?? 0
            return temp > 0 ? "\(Int(temp.rounded()))°" : "—"
        case .hottest:
            let hottest = hottestMetric
            return "\(hottest.label) \(Int(hottest.value.rounded()))%"
        }
    }

    /// Whichever of CPU / memory / disk is running highest right now.
    var hottestMetric: (label: String, value: Double, color: Color) {
        let candidates: [(String, Double, Color)] = [
            ("CPU", stream.snapshot?.cpu?.usage ?? 0, Theme.cpu),
            ("RAM", stream.snapshot?.memory?.usedPercent ?? 0, Theme.ram),
            ("Đĩa", stream.snapshot?.primaryDisk?.usedPercent ?? 0, Theme.disk),
        ]
        let top = candidates.max { $0.1 < $1.1 } ?? candidates[0]
        return (top.0, top.1, top.2)
    }

    /// Colour of the menubar dot: the hue of whatever is hottest, or red once
    /// anything crosses into trouble.
    var menubarTint: Color {
        let hottest = hottestMetric
        if hottest.value >= 85 { return Theme.danger }
        switch settings.menubarMetric {
        case .cpu: return Theme.cpu
        case .memory: return Theme.ram
        case .disk: return Theme.disk
        case .temperature: return Theme.heat
        case .hottest: return hottest.color
        }
    }
}
