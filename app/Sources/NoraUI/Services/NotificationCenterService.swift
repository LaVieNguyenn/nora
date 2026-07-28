import Foundation
import UserNotifications

/// Low-battery and low-disk alerts.
///
/// Each condition fires once per crossing: re-notifying every poll while a
/// device sits at 15% would train you to ignore the alert entirely.
final class NotificationCenterService: ObservableObject {
    private var notifiedDevices: Set<String> = []
    private var notifiedLowDisk = false
    private var authorized = false

    func requestAuthorization() {
        // `UNUserNotificationCenter.current()` raises an Objective-C exception
        // — not a catchable Swift error — when the process has no bundle
        // identifier, which is the case for the bare SwiftPM executable and for
        // any launch outside the .app wrapper. The exception aborts the process
        // before the UI is ever shown, so the guard has to come first.
        guard Bundle.main.bundleIdentifier != nil else {
            notificationsUnavailable = "Thông báo cần chạy app từ bản .app đã đóng gói"
            return
        }

        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { granted, error in
                DispatchQueue.main.async {
                    self.authorized = granted
                    if let error {
                        self.notificationsUnavailable = error.localizedDescription
                    }
                }
            }
    }

    /// Non-nil when notifications cannot be used, with the reason.
    @Published private(set) var notificationsUnavailable: String?

    func evaluate(devices: [DeviceBattery], snapshot: StatusSnapshot?, settings: AppSettings) {
        if settings.notifyLowBattery { checkBatteries(devices) }
        if settings.notifyLowDisk { checkDisk(snapshot, threshold: settings.lowDiskThresholdGB) }
    }

    private func checkBatteries(_ devices: [DeviceBattery]) {
        for device in devices {
            guard device.isConnected, !device.isCharging, let level = device.effectivePercent else {
                // Charging or gone: arm the alert again for the next drain.
                notifiedDevices.remove(device.id)
                continue
            }

            if level <= 20 {
                guard !notifiedDevices.contains(device.id) else { continue }
                notifiedDevices.insert(device.id)
                send(
                    title: "\(device.name) sắp hết pin",
                    body: "Còn \(level)%."
                )
            } else if level > 25 {
                // Hysteresis: only re-arm above the threshold so a reading that
                // hovers at the boundary does not alert repeatedly.
                notifiedDevices.remove(device.id)
            }
        }
    }

    private func checkDisk(_ snapshot: StatusSnapshot?, threshold: Int) {
        guard let disk = snapshot?.primaryDisk,
              let total = disk.total, let used = disk.used, total > 0
        else { return }

        let freeGB = Double(total - used) / 1_000_000_000

        if freeGB < Double(threshold) {
            guard !notifiedLowDisk else { return }
            notifiedLowDisk = true
            send(
                title: "Ổ đĩa sắp đầy",
                body: String(format: "Chỉ còn %.1f GB trống. Mở Nora để dọn dẹp.", freeGB)
            )
        } else if freeGB > Double(threshold) * 1.25 {
            notifiedLowDisk = false
        }
    }

    private func send(title: String, body: String) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
