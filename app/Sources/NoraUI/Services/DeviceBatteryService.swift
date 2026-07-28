import Foundation
import IOKit.ps

/// Collects battery levels for the Mac, paired Bluetooth accessories, and any
/// iPhone/iPad reachable over USB or Wi-Fi.
///
/// Each source runs on its own cadence because they cost wildly different
/// amounts: IOKit is free, `system_profiler` takes seconds, and `ideviceinfo`
/// depends on the network.
final class DeviceBatteryService: ObservableObject {
    @Published private(set) var devices: [DeviceBattery] = []
    @Published private(set) var iPhoneAvailable = false
    @Published private(set) var phoneStatus: PhoneStatus = .noDeviceReachable

    private var bluetoothTimer: Timer?
    private var phoneTimer: Timer?

    private var macBattery: DeviceBattery?
    private var bluetoothDevices: [DeviceBattery] = []
    private var phoneDevices: [DeviceBattery] = []

    /// `system_profiler SPBluetoothDataType` takes seconds and `ideviceinfo`
    /// costs three subprocesses per device, so neither runs on a tight loop
    /// while nobody is looking. The popover refreshes both on open, which is
    /// the only moment the numbers are actually read; the background cadence
    /// exists solely so the low-battery alert still fires.
    private var bluetoothInterval: TimeInterval = 300
    private var phoneInterval: TimeInterval = 300

    func start() {
        refreshMac()
        Task { await refreshBluetooth() }
        Task { await refreshPhones() }
        scheduleTimers()
    }

    /// Poll quickly only while the popover is on screen.
    func setActive(_ active: Bool) {
        let bluetooth: TimeInterval = active ? 30 : 300
        let phone: TimeInterval = active ? 30 : 300
        guard bluetooth != bluetoothInterval || phone != phoneInterval else { return }
        bluetoothInterval = bluetooth
        phoneInterval = phone
        scheduleTimers()
    }

    private func scheduleTimers() {
        bluetoothTimer?.invalidate()
        phoneTimer?.invalidate()

        let bluetooth = Timer(timeInterval: bluetoothInterval, repeats: true) { [weak self] _ in
            Task { await self?.refreshBluetooth() }
        }
        let phone = Timer(timeInterval: phoneInterval, repeats: true) { [weak self] _ in
            Task { await self?.refreshPhones() }
        }
        // A wide tolerance lets macOS coalesce these wake-ups with other timers
        // instead of waking the CPU on their own schedule.
        bluetooth.tolerance = bluetoothInterval * 0.25
        phone.tolerance = phoneInterval * 0.25
        RunLoop.main.add(bluetooth, forMode: .common)
        RunLoop.main.add(phone, forMode: .common)

        bluetoothTimer = bluetooth
        phoneTimer = phone
    }

    func stop() {
        bluetoothTimer?.invalidate()
        phoneTimer?.invalidate()
        bluetoothTimer = nil
        phoneTimer = nil
    }

    /// Cheap enough to call on every status frame.
    func refreshMac() {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return }

        for source in sources {
            guard let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue()
                    as? [String: Any] else { continue }
            guard let current = info[kIOPSCurrentCapacityKey] as? Int,
                  let max = info[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }

            let charging = (info[kIOPSIsChargingKey] as? Bool) ?? false
            let percent = Int((Double(current) / Double(max) * 100).rounded())

            macBattery = DeviceBattery(
                id: "mac",
                name: hostModelName(),
                kind: .mac,
                percent: percent,
                isConnected: true,
                isCharging: charging,
                detail: charging ? "đang sạc" : nil
            )
            break
        }
        rebuild()
    }

    private func hostModelName() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var raw = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &raw, &size, nil, 0)
        let model = String(cString: raw)
        if model.hasPrefix("Mac") && model.contains("Book") { return "MacBook" }
        return model.hasPrefix("Mac") ? "Mac" : model
    }

    func refreshBluetooth() async {
        guard let profiler = ProcessRunner.which("system_profiler") else { return }
        let result = await ProcessRunner.run(
            profiler, arguments: ["SPBluetoothDataType", "-json"], timeout: 10)
        guard result.succeeded, let data = result.stdout.data(using: .utf8) else { return }

        var parsed = Self.parseBluetooth(data)

        // A device that walks out of range stops reporting entirely. Keep its
        // last known level so the row reads "89% · 10 phút trước" instead of
        // disappearing the moment you take the AirPods out.
        for index in parsed.indices {
            if parsed[index].isConnected, parsed[index].effectivePercent != nil {
                LastKnownBattery.store(parsed[index])
            } else if !parsed[index].isConnected,
                      let remembered = LastKnownBattery.load(id: parsed[index].id) {
                parsed[index].percent = remembered.percent
                parsed[index].left = remembered.left
                parsed[index].right = remembered.right
                parsed[index].caseLevel = remembered.caseLevel
                parsed[index].lastSeen = remembered.date
                parsed[index].detail = "lần cuối \(Self.relativeTime(remembered.date))"
            }
        }

        // Drop disconnected devices we have never had a reading for — a paired
        // speaker that never reports battery is noise in a battery list.
        bluetoothDevices = parsed.filter { $0.isConnected || $0.effectivePercent != nil }
        rebuild()
    }

    nonisolated static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "vi_VN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Parse `system_profiler SPBluetoothDataType -json`.
    ///
    /// Each device is a single-key dictionary whose key is the device name, so
    /// the shape cannot be expressed with `Codable` structs.
    nonisolated static func parseBluetooth(_ data: Data) -> [DeviceBattery] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sections = root["SPBluetoothDataType"] as? [[String: Any]]
        else { return [] }

        var out: [DeviceBattery] = []

        for section in sections {
            for (key, connected) in [("device_connected", true), ("device_not_connected", false)] {
                guard let list = section[key] as? [[String: Any]] else { continue }
                for wrapper in list {
                    for (name, value) in wrapper {
                        guard let info = value as? [String: Any] else { continue }
                        if let device = device(name: name, info: info, connected: connected) {
                            out.append(device)
                        }
                    }
                }
            }
        }

        // Connected first, then lowest battery — the row you need to act on
        // should never be the one scrolled out of view.
        return out.sorted { a, b in
            if a.isConnected != b.isConnected { return a.isConnected }
            return (a.effectivePercent ?? 101) < (b.effectivePercent ?? 101)
        }
    }

    private nonisolated static func device(
        name: String, info: [String: Any], connected: Bool
    ) -> DeviceBattery? {
        let left = percent(info["device_batteryLevelLeft"])
        let right = percent(info["device_batteryLevelRight"])
        let caseLevel = percent(info["device_batteryLevelCase"])
        let main = percent(info["device_batteryLevelMain"]) ?? percent(info["device_batteryPercent"])

        let minor = info["device_minorType"] as? String

        // Report whichever cells macOS actually gave us. AirPods do not always
        // report all three: while they are being worn only the buds in use
        // report, and the case only reports while it is itself communicating —
        // in the case with the lid open, or charging. Requiring left *and*
        // right before showing anything hid the one reading that existed.
        var cells: [String] = []
        if let left { cells.append("T \(left)%") }
        if let right { cells.append("P \(right)%") }
        if let caseLevel { cells.append("hộp \(caseLevel)%") }

        var detail: String? = cells.isEmpty ? nil : cells.joined(separator: " · ")
        // Say why a cell is missing rather than letting it look like 0%.
        if Self.kindIsAirPods(name: name, minorType: minor), caseLevel == nil, !cells.isEmpty {
            detail = (detail ?? "") + " · hộp chỉ báo khi mở nắp"
        }

        return DeviceBattery(
            id: (info["device_address"] as? String) ?? name,
            name: name,
            kind: .classify(name: name, minorType: minor),
            percent: main,
            left: left,
            right: right,
            caseLevel: caseLevel,
            isConnected: connected,
            detail: connected ? detail : "ngắt kết nối"
        )
    }

    private nonisolated static func kindIsAirPods(name: String, minorType: String?) -> Bool {
        DeviceBattery.Kind.classify(name: name, minorType: minorType) == .airpods
    }

    /// Levels arrive as `"89%"`; a few firmware versions report a bare number.
    private nonisolated static func percent(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let number = value as? Int { return number }
        guard let text = value as? String else { return nil }
        let digits = text.trimmingCharacters(in: CharacterSet(charactersIn: "% "))
        return Int(digits)
    }

    /// Query paired iPhones/iPads through libimobiledevice, when installed.
    func refreshPhones() async {
        guard let listTool = ProcessRunner.which("idevice_id"),
              let infoTool = ProcessRunner.which("ideviceinfo")
        else {
            iPhoneAvailable = false
            phoneStatus = .toolMissing
            return
        }
        iPhoneAvailable = true

        // `-l` lists devices on USB; `-n` lists ones reachable over Wi-Fi. A
        // phone that is only on Wi-Fi is invisible to the first, so both have
        // to be asked before concluding nothing is there.
        let usb = await ProcessRunner.run(listTool, arguments: ["-l"], timeout: 6)
        let network = await ProcessRunner.run(listTool, arguments: ["-n"], timeout: 6)

        let udids = Set(
            (usb.stdout + "\n" + network.stdout)
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        ).sorted()

        var found: [DeviceBattery] = []
        for udid in udids {
            let name = await ProcessRunner.run(
                infoTool, arguments: ["-u", udid, "-k", "DeviceName"], timeout: 8)
            let level = await ProcessRunner.run(
                infoTool,
                arguments: ["-u", udid, "-q", "com.apple.mobile.battery", "-k", "BatteryCurrentCapacity"],
                timeout: 8)
            let charging = await ProcessRunner.run(
                infoTool,
                arguments: ["-u", udid, "-q", "com.apple.mobile.battery", "-k", "BatteryIsCharging"],
                timeout: 8)

            guard level.succeeded,
                  let percent = Int(level.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
            else { continue }

            let deviceName = name.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let isCharging = charging.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "true"

            found.append(DeviceBattery(
                id: "idevice-\(udid)",
                name: deviceName.isEmpty ? "iPhone" : deviceName,
                kind: .phone,
                percent: percent,
                isConnected: true,
                isCharging: isCharging,
                detail: isCharging ? "đang sạc" : nil
            ))
        }

        phoneStatus = found.isEmpty ? .noDeviceReachable : .connected(found.count)

        // Keep a device that has gone out of range visible with its last
        // reading rather than having the row vanish from under the pointer.
        if found.isEmpty {
            phoneDevices = phoneDevices.map {
                var stale = $0
                stale.isConnected = false
                stale.detail = "ngoài vùng phủ sóng"
                return stale
            }
        } else {
            phoneDevices = found
        }
        rebuild()
    }

    private func rebuild() {
        var all: [DeviceBattery] = []
        if let macBattery { all.append(macBattery) }
        all.append(contentsOf: phoneDevices)
        all.append(contentsOf: bluetoothDevices)
        devices = all
    }
}
