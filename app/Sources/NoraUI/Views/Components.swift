import SwiftUI

// The shared vocabulary every screen is built from. Keeping these in one place
// is what makes the app look like one app; it also means the expensive ones
// (the meter and the sparkline appear dozens of times per screen) get optimised
// once rather than per call site.

// MARK: - Meter

/// A horizontal progress bar.
///
/// Hand-built rather than a linear `ProgressView`, because on macOS that is an
/// `NSProgressIndicator` underneath and ignores SwiftUI's `.tint` — every bar
/// came out the same grey, and the colour *is* the information here.
///
/// A `Canvas` was tried instead and measured worse: the overview holds about
/// twenty of these, and it cost ~5 MB more resident than the two capsules do.
/// So this stays shapes, and the shared type is what makes that one measurement
/// apply everywhere instead of to one of twenty hand-written copies.
struct Meter: View {
    let value: Double
    var tint: Color = .accentColor
    var height: CGFloat = 5
    var width: CGFloat?

    var body: some View {
        Capsule()
            .fill(Theme.meterTrack)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    Capsule()
                        .fill(tint)
                        // Never narrower than it is tall: below that the rounded
                        // cap has no room and a small-but-real value renders as
                        // nothing at all.
                        .frame(width: max(geo.size.height, geo.size.width * clamped))
                }
            }
            .frame(width: width, height: height)
            .accessibilityHidden(true)
    }

    private var clamped: Double { min(max(value, 0), 1) }
}

// MARK: - Sparkline

/// Minimal line chart for a rolling series.
///
/// `Canvas` here, unlike in `Meter`: a polyline plus a gradient area fill is
/// drawing rather than layout, and there are only ever three or four of these
/// on screen, so the per-instance cost that ruled Canvas out for the meters
/// does not add up to anything.
struct Sparkline: View {
    let values: [Double]
    var tint: Color
    var lineWidth: CGFloat = 1.5
    /// Fill the area under the line. Reads better at card size; too busy at the
    /// 14pt height the compact rows use.
    var filled: Bool = false

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            guard values.count > 1 else { return }

            let maximum = max(values.max() ?? 1, 1)
            let minimum = min(values.min() ?? 0, 0)
            let span = max(maximum - minimum, 0.001)
            let step = size.width / CGFloat(values.count - 1)

            var line = Path()
            for (index, value) in values.enumerated() {
                let point = CGPoint(
                    x: CGFloat(index) * step,
                    y: size.height - CGFloat((value - minimum) / span) * size.height
                )
                index == 0 ? line.move(to: point) : line.addLine(to: point)
            }

            if filled {
                var area = line
                area.addLine(to: CGPoint(x: size.width, y: size.height))
                area.addLine(to: CGPoint(x: 0, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .linearGradient(
                    Gradient(colors: [tint.opacity(0.28), tint.opacity(0)]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)
                ))
            }

            context.stroke(
                line,
                with: .color(tint),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Cards

/// A titled block of content. The app's only container.
struct SectionCard<Content: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(title)
                    .font(.headline)
                Spacer(minLength: 8)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
    }
}

/// One headline number with an optional trend or meter under it.
struct StatTile: View {
    let metric: Metric
    let value: String
    var caption: String?
    var series: [Double] = []
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(metric.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: metric.symbol)
                    .font(.caption)
                    .foregroundStyle(metric.tint)
            }

            Text(value)
                .font(.system(.title2, design: .rounded, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            if series.count > 1 {
                Sparkline(values: series, tint: metric.tint, filled: true)
                    .frame(height: 24)
            } else if let progress {
                Meter(value: progress, tint: metric.tint)
            }

            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .padding(12)
        // A fixed height so a tile with a sparkline and one without still line
        // up along the bottom of the row.
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .strokeBorder(Theme.separator, lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(metric.title): \(value)")
    }
}

// MARK: - Rows

/// Label on the left, value on the right. The detail panel is built from these.
struct KeyValueRow: View {
    let label: String
    let value: String
    var tint: Color?

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.callout)
                .fontWeight(tint == nil ? .regular : .medium)
                .foregroundStyle(tint ?? Theme.label)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

/// A small caps section heading, the same everywhere it appears.
struct SectionHeading: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.5)
            .foregroundStyle(.secondary)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A named quantity with a bar showing its share of the largest in the list.
struct RankedBarRow: View {
    let name: String
    var badge: String?
    let value: String
    let fraction: Double
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let badge {
                    Text(badge)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 8)
                Text(value)
                    .font(.callout)
                    .foregroundStyle(tint)
                    .monospacedDigit()
            }
            Meter(value: fraction, tint: tint)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(value)")
    }
}

// MARK: - Controls

/// Checkbox with a mixed state.
///
/// SwiftUI's `Toggle` has no mixed state on macOS, so this is a symbol — one
/// glyph, rather than the stack of rectangles and overlays it replaces.
struct TriStateCheckbox: View {
    let checked: Bool
    let partial: Bool
    let action: () -> Void

    private var symbol: String {
        if partial { return "minus.square.fill" }
        return checked ? "checkmark.square.fill" : "square"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14))
                .foregroundStyle(checked || partial ? Color.accentColor : Theme.secondaryLabel)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(checked ? [.isSelected] : [])
    }
}

/// Empty / first-run state: a glyph, a headline, a line of explanation and the
/// one button that resolves it.
struct EmptyState<Actions: View>: View {
    let symbol: String
    let title: String
    var message: String?
    var tint: Color = .accentColor
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            Image(systemName: symbol)
                .font(.system(size: 34))
                .foregroundStyle(tint)
                .symbolRenderingMode(.hierarchical)
            Text(title)
                .font(.title3.weight(.medium))
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions()
                .padding(.top, 4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Busy state with a spinner and a line of progress text.
struct BusyState: View {
    let title: String
    var message: String?
    var onCancel: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Spacer(minLength: 0)
            ProgressView().controlSize(.large)
            Text(title)
                .font(.callout)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let onCancel {
                Button("Dừng", action: onCancel)
                    .buttonStyle(.link)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Inline warning. Used for setup problems and scan failures.
struct NoticeBanner: View {
    let message: String
    var symbol: String = "exclamationmark.triangle"
    var tint: Color = Theme.warning

    var body: some View {
        Label {
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.controlRadius))
    }
}

/// Reveal-in-Finder button, repeated on every path-bearing row in the app.
struct RevealButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "folder")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .help("Hiện trong Finder")
        .accessibilityLabel("Hiện trong Finder")
    }
}

// MARK: - Log

/// Live activity log, auto-scrolling to the newest line.
///
/// `LazyVStack`, and only the tail is handed to it. A run emits thousands of
/// lines and the eager `VStack` this replaces built a view for every one of
/// them — the single biggest contributor to the app's memory peak during a
/// clean.
struct LogPane: View {
    let lines: [LogLine]
    /// Rows past this are dropped from the *view*, not the model: the full log
    /// is still what "Sao chép log" copies.
    var visibleLimit: Int = 300

    private var tail: ArraySlice<LogLine> { lines.suffix(visibleLimit) }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if lines.count > visibleLimit {
                        Text("… \(lines.count - visibleLimit) dòng trước đó (có trong bản sao chép)")
                            .foregroundStyle(.tertiary)
                            .padding(.bottom, 2)
                    }
                    ForEach(tail) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(line.timeText)
                                .foregroundStyle(.tertiary)
                            Image(systemName: symbol(line.level))
                                .foregroundStyle(tint(line.level))
                                .font(.system(size: 9))
                            Text(line.message)
                            if let detail = line.detail {
                                Text("· \(detail)")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .id(line.id)
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(
                Theme.sunkenBackground,
                in: RoundedRectangle(cornerRadius: Theme.controlRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .strokeBorder(Theme.separator, lineWidth: 0.5)
            )
            .onChange(of: lines.count) {
                guard let last = lines.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func symbol(_ level: LogLine.Level) -> String {
        switch level {
        case .removed: return "checkmark"
        case .skipped: return "minus"
        case .working: return "arrow.right"
        case .failed: return "xmark"
        case .done: return "flag.checkered"
        }
    }

    private func tint(_ level: LogLine.Level) -> Color {
        switch level {
        case .removed: return Theme.success
        case .skipped: return Theme.warning
        case .working: return .accentColor
        case .failed: return Theme.danger
        case .done: return Theme.success
        }
    }
}
