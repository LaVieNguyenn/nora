import Foundation
import Combine

/// Which metric the menubar item itself displays.
enum MenubarMetric: String, CaseIterable, Identifiable {
    case cpu, memory, disk, temperature, hottest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Bộ nhớ"
        case .disk: return "Ổ đĩa"
        case .temperature: return "Nhiệt độ"
        case .hottest: return "Chỉ số đang cao nhất"
        }
    }
}

final class AppSettings: ObservableObject {
    @Published var menubarMetric: MenubarMetric {
        didSet { defaults.set(menubarMetric.rawValue, forKey: Keys.menubarMetric) }
    }

    /// Collection cadence for the status stream, in seconds.
    @Published var refreshSeconds: Int {
        didSet { defaults.set(refreshSeconds, forKey: Keys.refreshSeconds) }
    }

    @Published var showValueInMenubar: Bool {
        didSet { defaults.set(showValueInMenubar, forKey: Keys.showValue) }
    }

    @Published var notifyLowBattery: Bool {
        didSet { defaults.set(notifyLowBattery, forKey: Keys.notifyLowBattery) }
    }

    @Published var notifyLowDisk: Bool {
        didSet { defaults.set(notifyLowDisk, forKey: Keys.notifyLowDisk) }
    }

    /// Free-space threshold in GB below which the disk warning fires.
    @Published var lowDiskThresholdGB: Int {
        didSet { defaults.set(lowDiskThresholdGB, forKey: Keys.lowDiskThreshold) }
    }

    @Published var noraRepoPath: String {
        didSet { defaults.set(noraRepoPath, forKey: NoraLocator.repoPathDefaultsKey) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let menubarMetric = "menubarMetric"
        static let refreshSeconds = "refreshSeconds"
        static let showValue = "showValueInMenubar"
        static let notifyLowBattery = "notifyLowBattery"
        static let notifyLowDisk = "notifyLowDisk"
        static let lowDiskThreshold = "lowDiskThresholdGB"
    }

    init() {
        menubarMetric = MenubarMetric(
            rawValue: defaults.string(forKey: Keys.menubarMetric) ?? ""
        ) ?? .cpu
        let stored = defaults.integer(forKey: Keys.refreshSeconds)
        refreshSeconds = stored == 0 ? 2 : stored
        showValueInMenubar = defaults.object(forKey: Keys.showValue) as? Bool ?? true
        notifyLowBattery = defaults.object(forKey: Keys.notifyLowBattery) as? Bool ?? true
        notifyLowDisk = defaults.object(forKey: Keys.notifyLowDisk) as? Bool ?? true
        let threshold = defaults.integer(forKey: Keys.lowDiskThreshold)
        lowDiskThresholdGB = threshold == 0 ? 20 : threshold
        noraRepoPath = defaults.string(forKey: NoraLocator.repoPathDefaultsKey) ?? ""
    }

    var refreshInterval: String { "\(refreshSeconds)s" }
}
