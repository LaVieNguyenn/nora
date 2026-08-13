import SwiftUI

/// Nora's design tokens.
///
/// Every colour here resolves through an AppKit semantic colour, a SwiftUI
/// material or a system palette colour rather than a fixed hex value. That is
/// the whole point: the app then follows the system appearance, and light mode,
/// Increase Contrast and a changed accent colour all work without a second
/// hand-tuned palette to keep in sync.
enum Theme {

    // MARK: - Surfaces

    /// The ground every stock macOS window sits on.
    static let windowBackground = Color(nsColor: .windowBackgroundColor)

    /// Raised surfaces: cards and grouped rows.
    static let cardBackground = Color(nsColor: .controlBackgroundColor)

    /// Recessed surfaces: log panes and other read-only transcript areas.
    static let sunkenBackground = Color(nsColor: .underPageBackgroundColor)

    static let separator = Color(nsColor: .separatorColor)

    /// The unfilled part of a meter. `separatorColor` is too faint to read as a
    /// track once a bar sits on a card rather than on the window ground.
    static let meterTrack = Color(nsColor: .quaternaryLabelColor)

    // MARK: - Text

    static let label = Color(nsColor: .labelColor)
    static let secondaryLabel = Color(nsColor: .secondaryLabelColor)
    static let tertiaryLabel = Color(nsColor: .tertiaryLabelColor)

    // MARK: - Status

    static let danger = Color(nsColor: .systemRed)
    static let warning = Color(nsColor: .systemOrange)
    static let success = Color(nsColor: .systemGreen)

    // MARK: - Geometry

    /// One radius for cards, one for the controls inside them. Two values, not
    /// the eight different corner radii the previous design accumulated.
    static let cardRadius: CGFloat = 10
    static let controlRadius: CGFloat = 6

    // MARK: - Ramps

    /// Colour for a load percentage: calm below 60, warm to 85, hot above.
    ///
    /// The calm end is the *accent* colour, not a fixed purple — an idle
    /// machine should look like the rest of the user's system, not like Nora.
    static func loadTint(_ percent: Double) -> Color {
        if percent >= 85 { return danger }
        if percent >= 60 { return warning }
        return Metric.cpu.tint
    }

    /// Colour ramp for a battery level: green above 50, amber to 20, red below.
    static func batteryTint(_ percent: Int?) -> Color {
        guard let percent else { return tertiaryLabel }
        if percent <= 20 { return danger }
        if percent <= 50 { return warning }
        return success
    }
}

/// The five things Nora measures.
///
/// One type, used by the menubar rows, the detail panel and the overview cards,
/// so a metric's name, glyph and hue cannot drift apart between them.
enum Metric: String, CaseIterable, Identifiable {
    case cpu, memory, disk, network, thermal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "Bộ nhớ"
        case .disk: return "Ổ đĩa"
        case .network: return "Mạng"
        case .thermal: return "Nhiệt độ"
        }
    }

    /// The short form the compact menubar rows use, where the column is narrow.
    var shortTitle: String {
        switch self {
        case .cpu: return "CPU"
        case .memory: return "RAM"
        case .disk: return "Ổ đĩa"
        case .network: return "Mạng"
        case .thermal: return "Nhiệt"
        }
    }

    var symbol: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .network: return "network"
        case .thermal: return "thermometer.medium"
        }
    }

    /// System palette colours, so each hue tracks the system appearance and the
    /// accessibility contrast settings instead of being frozen at one value.
    var tint: Color {
        switch self {
        case .cpu: return Color(nsColor: .systemPurple)
        case .memory: return Color(nsColor: .systemGreen)
        case .disk: return Color(nsColor: .systemBlue)
        case .network: return Color(nsColor: .systemOrange)
        case .thermal: return Color(nsColor: .systemYellow)
        }
    }
}
