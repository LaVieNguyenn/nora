import SwiftUI

/// One metric rendered as a floating orb.
///
/// Diameter carries meaning: a bubble grows as its metric climbs, so the
/// busiest subsystem is the largest thing on screen and reads before any digit
/// does.
struct BubbleView: View {
    let title: String
    let value: String
    let caption: String?
    let tint: Color
    let deep: Color
    let light: Color
    let diameter: CGFloat
    /// 0…1, drives the ring that traces the orb's rim.
    let fill: Double
    var sparkline: [Double] = []
    /// Phase offset so sibling bubbles do not bob in lockstep.
    var driftSeed: Double = 0
    /// Off unless the popover is genuinely on screen — see `onAppear`.
    var animatesDrift: Bool = false

    @State private var drift: CGFloat = 0

    private var titleFont: CGFloat { diameter < 62 ? 9 : 10 }
    private var valueFont: CGFloat { max(12, min(26, diameter * 0.24)) }
    /// The network bubble is one of the small ones and its caption carries the
    /// unit, so the threshold has to sit below that bubble's idle size.
    private var showsCaption: Bool { diameter >= 50 && caption != nil }
    private var showsSparkline: Bool { diameter >= 92 && !sparkline.isEmpty }

    var body: some View {
        ZStack {
            Circle().fill(deep)

            Circle()
                .strokeBorder(tint.opacity(0.55), lineWidth: 1.5)

            // Progress rim: the filled arc starts at the top and runs clockwise.
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fill)))
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(1)

            VStack(spacing: 1) {
                Text(title)
                    .font(.system(size: titleFont, weight: .medium))
                    .foregroundStyle(light)
                Text(value)
                    .font(.system(size: valueFont, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if showsCaption, let caption {
                    Text(caption)
                        .font(.system(size: 9))
                        .foregroundStyle(light.opacity(0.85))
                        .lineLimit(1)
                }
                if showsSparkline {
                    SparklineView(values: sparkline, color: light)
                        .frame(width: diameter * 0.58, height: 14)
                }
            }
            .padding(.horizontal, 6)
        }
        .frame(width: diameter, height: diameter)
        .offset(y: drift)
        // Driven by onChange, not onAppear: a child's onAppear fires before
        // its parent's, so `animatesDrift` was still false when the guard ran
        // and the bob never started at all. The repeatForever animation is
        // still cancelled the moment the flag drops — leaving it running cost
        // 12% CPU with the popover closed.
        .onChange(of: animatesDrift) { _, active in
            if active {
                withAnimation(
                    .easeInOut(duration: 3.6 + driftSeed * 1.4).repeatForever(autoreverses: true)
                ) {
                    drift = driftSeed.truncatingRemainder(dividingBy: 2) < 1 ? 4 : -4
                }
            } else {
                withAnimation(.linear(duration: 0)) { drift = 0 }
            }
        }
        .animation(.easeInOut(duration: 0.6), value: diameter)
    }
}

/// Minimal line chart used inside the larger bubbles and on the metric cards.
struct SparklineView: View {
    let values: [Double]
    let color: Color
    var lineWidth: CGFloat = 1.6

    var body: some View {
        GeometryReader { geo in
            let points = normalized(in: geo.size)
            if points.count > 1 {
                Path { path in
                    path.move(to: points[0])
                    for point in points.dropFirst() { path.addLine(to: point) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineJoin: .round))
            }
        }
    }

    private func normalized(in size: CGSize) -> [CGPoint] {
        guard values.count > 1 else { return [] }
        let maximum = max(values.max() ?? 1, 1)
        let minimum = min(values.min() ?? 0, 0)
        let span = max(maximum - minimum, 0.001)
        let step = size.width / CGFloat(values.count - 1)

        return values.enumerated().map { index, value in
            let ratio = (value - minimum) / span
            return CGPoint(
                x: CGFloat(index) * step,
                y: size.height - CGFloat(ratio) * size.height
            )
        }
    }
}

/// Static star backdrop behind the bubbles.
struct StarfieldView: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(Starfield.stars) { star in
                    Circle()
                        .fill(Theme.textMuted.opacity(star.opacity))
                        .frame(width: star.r * 2, height: star.r * 2)
                        .position(x: star.x * geo.size.width, y: star.y * geo.size.height)
                }
                Ellipse()
                    .strokeBorder(Theme.hairline, lineWidth: 1)
                    .frame(width: geo.size.width * 0.88, height: geo.size.height * 0.7)
                    .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
        .allowsHitTesting(false)
    }
}
