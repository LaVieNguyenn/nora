import Foundation

/// Why the iPhone row is or is not present.
///
/// Deliberately a top-level type. Nesting it inside the `@MainActor`
/// `DeviceBatteryService` made the enum itself main-actor isolated, so every
/// read of `hint` from a SwiftUI body became a runtime isolation check — and
/// that check is what crashed the popover once snapshots started re-evaluating
/// the view. A value describing state needs no isolation of its own.
enum PhoneStatus: Equatable, Sendable {
    case toolMissing
    case noDeviceReachable
    case connected(Int)

    var hint: String? {
        switch self {
        case .toolMissing:
            return "iPhone: cần cài libimobiledevice"
        case .noDeviceReachable:
            // Measured on macOS 26: with Wi-Fi sync enabled and the iPhone
            // actively advertising `_apple-mobdev2._tcp` on the LAN, Apple's
            // usbmuxd still reports zero devices to third-party clients — over
            // USB *and* over the network. Full Disk Access does not change it;
            // the pairing record is not the blocker. The cable is the only
            // path that works, so say that rather than sending the user after
            // a setting that cannot help.
            return "iPhone: cắm cáp để đọc pin — qua Wi-Fi macOS không mở cho app ngoài"
        case .connected:
            return nil
        }
    }
}

/// A battery reading for the Mac itself or any paired device.
struct DeviceBattery: Identifiable, Equatable {
    enum Kind: String {
        case mac, airpods, phone, mouse, keyboard, trackpad, headphones, other

        var symbol: String {
            switch self {
            case .mac: return "laptopcomputer"
            case .airpods: return "airpodspro"
            case .phone: return "iphone"
            case .mouse: return "magicmouse"
            case .keyboard: return "keyboard"
            case .trackpad: return "rectangle.and.hand.point.up.left"
            case .headphones: return "headphones"
            case .other: return "dot.radiowaves.left.and.right"
            }
        }
    }

    let id: String
    var name: String
    var kind: Kind
    var percent: Int?
    /// AirPods report each bud and the case separately; nil for single-cell devices.
    var left: Int?
    var right: Int?
    var caseLevel: Int?
    var isConnected: Bool
    var isCharging: Bool = false
    var detail: String?
    /// When the reading was taken, for devices polled on a slow cadence.
    var lastSeen: Date = Date()

    /// The level that drives the row's colour and sort order. For AirPods this is
    /// the lower of the two buds, because that is the one that dies first.
    var effectivePercent: Int? {
        if let l = left, let r = right { return min(l, r) }
        return percent ?? left ?? right
    }

    var isLow: Bool {
        guard let p = effectivePercent else { return false }
        return p <= 20
    }

    static func == (a: DeviceBattery, b: DeviceBattery) -> Bool {
        a.id == b.id && a.percent == b.percent && a.left == b.left
            && a.right == b.right && a.caseLevel == b.caseLevel
            && a.isConnected == b.isConnected && a.isCharging == b.isCharging
    }
}

extension DeviceBattery.Kind {
    /// Classify from the Bluetooth minor type plus the device name, since
    /// `device_minorType` is coarse (every AirPod is just "Headphones").
    static func classify(name: String, minorType: String?) -> DeviceBattery.Kind {
        let n = name.lowercased()
        if n.contains("airpod") { return .airpods }
        if n.contains("magic mouse") || n.contains("mouse") { return .mouse }
        if n.contains("magic keyboard") || n.contains("keyboard") { return .keyboard }
        if n.contains("trackpad") { return .trackpad }
        if n.contains("iphone") || n.contains("ipad") { return .phone }

        switch minorType?.lowercased() {
        case "headphones": return .headphones
        case "mouse": return .mouse
        case "keyboard": return .keyboard
        default: return .other
        }
    }
}
