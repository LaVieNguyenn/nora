import SwiftUI

/// The space palette. Each metric owns one hue and keeps it everywhere it
/// appears — the CPU bubble, the CPU card, and the CPU dot in the cleanup list
/// are all `Theme.cpu`, so colour alone identifies a metric.
enum Theme {
    static let void = Color(red: 0.043, green: 0.043, blue: 0.071)      // #0b0b12
    static let panel = Color(red: 0.071, green: 0.071, blue: 0.106)     // #12121b
    static let card = Color(red: 0.086, green: 0.086, blue: 0.133)      // #161622
    static let hairline = Color(red: 0.133, green: 0.133, blue: 0.184)  // #22222f
    static let border = Color(red: 0.169, green: 0.169, blue: 0.239)    // #2b2b3d

    static let textPrimary = Color(red: 0.910, green: 0.910, blue: 0.941)
    static let textSecondary = Color(red: 0.541, green: 0.541, blue: 0.647)
    static let textMuted = Color(red: 0.431, green: 0.431, blue: 0.533)

    static let cpu = Color(red: 0.498, green: 0.467, blue: 0.867)       // #7F77DD
    static let cpuLight = Color(red: 0.686, green: 0.663, blue: 0.925)  // #AFA9EC
    static let cpuDeep = Color(red: 0.165, green: 0.145, blue: 0.318)   // #2a2551

    static let ram = Color(red: 0.114, green: 0.620, blue: 0.459)       // #1D9E75
    static let ramLight = Color(red: 0.365, green: 0.792, blue: 0.647)  // #5DCAA5
    static let ramDeep = Color(red: 0.071, green: 0.227, blue: 0.188)   // #123a30

    static let disk = Color(red: 0.216, green: 0.541, blue: 0.867)      // #378ADD
    static let diskLight = Color(red: 0.522, green: 0.718, blue: 0.922) // #85B7EB
    static let diskDeep = Color(red: 0.059, green: 0.188, blue: 0.329)  // #0f3054

    static let net = Color(red: 0.847, green: 0.353, blue: 0.188)       // #D85A30
    static let netLight = Color(red: 0.941, green: 0.600, blue: 0.482)  // #F0997B
    static let netDeep = Color(red: 0.290, green: 0.129, blue: 0.075)   // #4a2113

    static let heat = Color(red: 0.937, green: 0.624, blue: 0.153)      // #EF9F27
    static let heatLight = Color(red: 0.980, green: 0.780, blue: 0.459) // #FAC775
    static let heatDeep = Color(red: 0.239, green: 0.165, blue: 0.020)  // #3d2a05

    static let good = Color(red: 0.592, green: 0.769, blue: 0.349)      // #97C459
    static let goodLight = Color(red: 0.753, green: 0.867, blue: 0.592) // #C0DD97
    static let goodDeep = Color(red: 0.102, green: 0.239, blue: 0.035)  // #1a3d09

    static let danger = Color(red: 0.886, green: 0.294, blue: 0.290)    // #E24B4A
    static let dangerLight = Color(red: 0.941, green: 0.584, blue: 0.584)
    static let dangerDeep = Color(red: 0.314, green: 0.075, blue: 0.075)

    static let accent = Color(red: 0.325, green: 0.290, blue: 0.718)    // #534AB7

    /// Colour ramp for a battery level: green above 50, amber to 20, red below.
    static func batteryColor(_ percent: Int?) -> Color {
        guard let p = percent else { return textMuted }
        if p <= 20 { return danger }
        if p <= 50 { return heat }
        return good
    }

    static func batteryDeep(_ percent: Int?) -> Color {
        guard let p = percent else { return card }
        if p <= 20 { return dangerDeep }
        if p <= 50 { return heatDeep }
        return goodDeep
    }

    /// Colour for a load percentage: calm below 60, warm to 85, hot above.
    static func loadColor(_ percent: Double) -> Color {
        if percent >= 85 { return danger }
        if percent >= 60 { return heat }
        return cpu
    }
}

/// A single star in the popover backdrop. Positions are fractions of the
/// container so the field scales with the popover instead of being clipped.
struct Star: Identifiable {
    let id: Int
    let x: Double
    let y: Double
    let r: Double
    let opacity: Double
}

enum Starfield {
    /// A fixed field — regenerating it every render would make the sky twinkle
    /// at frame rate, which reads as noise rather than space.
    static let stars: [Star] = {
        var generator = SeededGenerator(seed: 0x5EED_1234)
        return (0..<26).map { i in
            Star(
                id: i,
                x: Double.random(in: 0.02...0.98, using: &generator),
                y: Double.random(in: 0.03...0.97, using: &generator),
                r: Double.random(in: 0.6...1.5, using: &generator),
                opacity: Double.random(in: 0.25...0.75, using: &generator)
            )
        }
    }()
}

/// Deterministic RNG so the starfield is identical on every launch.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
