import Foundation

/// Mirrors the JSON emitted by `nora status --json` / `--watch`.
/// Every field is optional because the collector degrades gracefully when a
/// probe is denied or unavailable, and a missing key must not drop the frame.
struct StatusSnapshot: Decodable {
    var collectedAt: String?
    var host: String?
    var uptime: String?
    var procs: Int?
    var hardware: Hardware?
    var healthScore: Int?
    var healthScoreMsg: String?
    var cpu: CPU?
    var memory: Memory?
    var disks: [Disk]?
    var diskIO: DiskIO?
    var network: [NetworkInterface]?
    var batteries: [Battery]?
    var thermal: Thermal?
    var bluetooth: [BluetoothEntry]?
    var topProcesses: [ProcessInfo]?

    enum CodingKeys: String, CodingKey {
        case collectedAt = "collected_at"
        case host, uptime, procs, hardware
        case healthScore = "health_score"
        case healthScoreMsg = "health_score_msg"
        case cpu, memory, disks
        case diskIO = "disk_io"
        case network, batteries, thermal, bluetooth
        case topProcesses = "top_processes"
    }

    struct Hardware: Decodable {
        var model: String?
        var cpuModel: String?
        var totalRAM: String?
        var osVersion: String?

        enum CodingKeys: String, CodingKey {
            case model
            case cpuModel = "cpu_model"
            case totalRAM = "total_ram"
            case osVersion = "os_version"
        }
    }

    struct CPU: Decodable {
        var usage: Double?
        var perCore: [Double]?
        var load1: Double?
        var load5: Double?
        var load15: Double?
        var coreCount: Int?
        var pCoreCount: Int?
        var eCoreCount: Int?

        enum CodingKeys: String, CodingKey {
            case usage, load1, load5, load15
            case perCore = "per_core"
            case coreCount = "core_count"
            case pCoreCount = "p_core_count"
            case eCoreCount = "e_core_count"
        }
    }

    struct Memory: Decodable {
        var used: Int64?
        var total: Int64?
        var available: Int64?
        var cached: Int64?
        var usedPercent: Double?
        var swapUsed: Int64?
        var swapTotal: Int64?
        var pressure: String?

        enum CodingKeys: String, CodingKey {
            case used, total, available, cached, pressure
            case usedPercent = "used_percent"
            case swapUsed = "swap_used"
            case swapTotal = "swap_total"
        }
    }

    struct Disk: Decodable, Identifiable {
        var mount: String?
        var device: String?
        var used: Int64?
        var total: Int64?
        var usedPercent: Double?
        var fstype: String?
        var external: Bool?
        var smartStatus: String?

        // Stable even when both fields are nil: a UUID fallback minted a new
        // identity on every read, so those rows rebuilt every frame.
        var id: String { mount ?? device ?? "disk" }

        enum CodingKeys: String, CodingKey {
            case mount, device, used, total, fstype, external
            case usedPercent = "used_percent"
            case smartStatus = "smart_status"
        }
    }

    struct DiskIO: Decodable {
        var readRate: Double?
        var writeRate: Double?

        enum CodingKeys: String, CodingKey {
            case readRate = "read_rate"
            case writeRate = "write_rate"
        }
    }

    struct NetworkInterface: Decodable, Identifiable {
        var id: String { name ?? ip ?? "interface" }
        var name: String?
        var rxRateMBs: Double?
        var txRateMBs: Double?
        var ip: String?

        enum CodingKeys: String, CodingKey {
            case name, ip
            case rxRateMBs = "rx_rate_mbs"
            case txRateMBs = "tx_rate_mbs"
        }
    }

    struct Battery: Decodable {
        var percent: Int?
        var status: String?
        var timeLeft: String?
        var health: String?
        var cycleCount: Int?

        enum CodingKeys: String, CodingKey {
            case percent, status, health
            case timeLeft = "time_left"
            case cycleCount = "cycle_count"
        }
    }

    struct Thermal: Decodable {
        var cpuTemp: Double?
        var gpuTemp: Double?
        var batteryTemp: Double?
        var fanSpeed: Int?
        var fanCount: Int?
        var systemPower: Double?
        var adapterPower: Double?
        var batteryPower: Double?

        enum CodingKeys: String, CodingKey {
            case cpuTemp = "cpu_temp"
            case gpuTemp = "gpu_temp"
            case batteryTemp = "battery_temp"
            case fanSpeed = "fan_speed"
            case fanCount = "fan_count"
            case systemPower = "system_power"
            case adapterPower = "adapter_power"
            case batteryPower = "battery_power"
        }
    }

    /// Nora's own Bluetooth section. Its parser flattens the battery lines into
    /// one string and mis-reports `connected`, so the app reads Bluetooth from
    /// `system_profiler -json` directly and keeps this only as a fallback.
    struct BluetoothEntry: Decodable {
        var name: String?
        var connected: Bool?
        var battery: String?
    }

    struct ProcessInfo: Decodable, Identifiable {
        var pid: Int
        var name: String?
        var cpu: Double?
        var memoryBytes: Int64?

        var id: Int { pid }

        enum CodingKeys: String, CodingKey {
            case pid, name, cpu
            case memoryBytes = "memory_bytes"
        }
    }
}

extension StatusSnapshot {
    /// Primary volume, preferring the boot mount over external disks.
    var primaryDisk: Disk? {
        disks?.first { $0.mount == "/" } ?? disks?.first
    }

    /// Aggregate throughput across every active interface, in MB/s.
    var networkRates: (down: Double, up: Double) {
        guard let network else { return (0, 0) }
        return network.reduce(into: (0.0, 0.0)) { acc, iface in
            acc.0 += iface.rxRateMBs ?? 0
            acc.1 += iface.txRateMBs ?? 0
        }
    }

    var macBattery: Battery? { batteries?.first }
}
