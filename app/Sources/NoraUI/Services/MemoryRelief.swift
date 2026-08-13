import Foundation

/// Hands pages freed by a burst of work back to the operating system.
///
/// Measured on this app: a clean scan takes the process to a ~420 MB peak and it
/// settles at ~110 MB, of which roughly half is `MALLOC_SMALL` that is free but
/// still resident. malloc keeps those pages on the assumption the next burst
/// wants them, which is right for a compiler and wrong for a menubar utility
/// that scans once and then idles for hours — the user sees a monitoring tool
/// sitting on 100 MB of nothing.
///
/// `malloc_zone_pressure_relief(nil, 0)` is the supported way to ask for them
/// back: it walks every zone and madvises the free spans away. It is not free,
/// so it belongs after a burst finishes rather than on any hot path.
enum MemoryRelief {

    /// Release freed heap pages. Safe to call from any thread; it does its work
    /// off the main queue so a large heap cannot stall the UI.
    static func release() {
        DispatchQueue.global(qos: .utility).async {
            malloc_zone_pressure_relief(nil, 0)
        }
    }

    /// This process's resident size in MB, for the diagnostics in `SelfTest` and
    /// the popover cycle probe.
    static func residentMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size)
            / mach_msg_type_number_t(MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return -1 }
        return Int(info.resident_size / 1024 / 1024)
    }
}
