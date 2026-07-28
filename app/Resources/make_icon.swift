// Renders Nora's application icon and writes an .iconset ready for iconutil.
//
//   swift Resources/make_icon.swift Resources/Nora.iconset
//
// The artwork is drawn rather than shipped as a binary asset so it can be
// regenerated at any size and stays reviewable in the diff.

import AppKit
import Foundation

// MARK: - Palette
//
// The same hues the popover uses, so the icon reads as this app: the metric
// bubbles keep their identity from Finder all the way into the detail panels.

let void = NSColor(srgbRed: 0.043, green: 0.043, blue: 0.071, alpha: 1)
let voidLift = NSColor(srgbRed: 0.094, green: 0.090, blue: 0.145, alpha: 1)
let ring = NSColor(srgbRed: 0.180, green: 0.176, blue: 0.259, alpha: 1)
let star = NSColor(srgbRed: 0.541, green: 0.541, blue: 0.647, alpha: 1)

struct Bubble {
    let x: CGFloat        // centre, as a fraction of the canvas
    let y: CGFloat
    let r: CGFloat        // radius, as a fraction of the canvas
    let fill: NSColor
    let stroke: NSColor
}

// Fills are the metric's own mid-tone, not the popover's near-black "deep"
// shade. In the app those sit on a dark panel a few inches from your eyes; an
// icon has to survive 16px in a Finder list, where the deep fills turned into
// three indistinct dark discs.
let bubbles = [
    // CPU — the largest, mirroring its place in the constellation.
    Bubble(x: 0.355, y: 0.455, r: 0.190,
           fill: NSColor(srgbRed: 0.400, green: 0.365, blue: 0.800, alpha: 1),
           stroke: NSColor(srgbRed: 0.686, green: 0.663, blue: 0.925, alpha: 1)),
    // RAM
    Bubble(x: 0.605, y: 0.630, r: 0.145,
           fill: NSColor(srgbRed: 0.114, green: 0.660, blue: 0.480, alpha: 1),
           stroke: NSColor(srgbRed: 0.365, green: 0.792, blue: 0.647, alpha: 1)),
    // Disk
    Bubble(x: 0.665, y: 0.360, r: 0.125,
           fill: NSColor(srgbRed: 0.180, green: 0.520, blue: 0.880, alpha: 1),
           stroke: NSColor(srgbRed: 0.522, green: 0.718, blue: 0.922, alpha: 1)),
]

let stars: [(CGFloat, CGFloat, CGFloat)] = [
    (0.19, 0.75, 0.011), (0.80, 0.79, 0.008), (0.24, 0.24, 0.009),
    (0.78, 0.19, 0.011), (0.50, 0.855, 0.007), (0.135, 0.50, 0.008),
]

// MARK: - Drawing

/// Render at an exact pixel size.
///
/// Deliberately not `NSImage.lockFocus`: that renders at the current display's
/// backing scale, so on a Retina machine every file came out at twice its
/// nominal size and `iconutil` produced a set macOS would not use.
func drawIcon(size: CGFloat) -> NSBitmapImageRep {
    let pixels = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ) else {
        fatalError("không tạo được bitmap \(pixels)px")
    }
    rep.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let graphics = NSGraphicsContext(bitmapImageRep: rep) else { return rep }
    NSGraphicsContext.current = graphics
    let context = graphics.cgContext

    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    // macOS icons sit inside their canvas rather than filling it; roughly a
    // tenth of the tile on each side is transparent margin.
    let inset = size * 0.094
    let plate = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    // Squircle-ish: Big Sur's continuous curve is close to 22% of the tile.
    let radius = plate.width * 0.2237
    let platePath = CGPath(roundedRect: plate, cornerWidth: radius, cornerHeight: radius,
                           transform: nil)

    context.saveGState()
    context.addPath(platePath)
    context.clip()

    // A soft vertical lift keeps the plate from reading as flat black at small
    // sizes without introducing a visible gradient band.
    if let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [voidLift.cgColor, void.cgColor] as CFArray,
        locations: [0, 1]
    ) {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: plate.midX, y: plate.maxY),
            end: CGPoint(x: plate.midX, y: plate.minY),
            options: []
        )
    }

    // Orbit ellipse, the same cue the popover's starfield uses.
    context.setStrokeColor(ring.cgColor)
    context.setLineWidth(max(1, size * 0.0075))
    let orbit = CGRect(
        x: plate.minX + plate.width * 0.075,
        y: plate.minY + plate.height * 0.285,
        width: plate.width * 0.85,
        height: plate.height * 0.44
    )
    context.strokeEllipse(in: orbit)

    // Stars go under the bubbles so nothing pokes through them.
    for (sx, sy, sr) in stars {
        context.setFillColor(star.withAlphaComponent(0.55).cgColor)
        let r = plate.width * sr
        context.fillEllipse(in: CGRect(
            x: plate.minX + plate.width * sx - r,
            y: plate.minY + plate.height * sy - r,
            width: r * 2, height: r * 2
        ))
    }

    for bubble in bubbles {
        let r = plate.width * bubble.r
        let rect = CGRect(
            x: plate.minX + plate.width * bubble.x - r,
            y: plate.minY + plate.height * bubble.y - r,
            width: r * 2, height: r * 2
        )
        context.setFillColor(bubble.fill.cgColor)
        context.fillEllipse(in: rect)
        context.setStrokeColor(bubble.stroke.cgColor)
        context.setLineWidth(max(1, size * 0.016))
        context.strokeEllipse(in: rect.insetBy(dx: size * 0.008, dy: size * 0.008))
    }

    context.restoreGState()
    return rep
}

// MARK: - Write the iconset

let outputDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Nora.iconset"

try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

// The set iconutil expects: each logical size at 1x and 2x.
let variants: [(name: String, pixels: CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]

for variant in variants {
    let rep = drawIcon(size: variant.pixels)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("không dựng được \(variant.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let path = "\(outputDir)/\(variant.name).png"
    try? png.write(to: URL(fileURLWithPath: path))
}

print("đã ghi \(variants.count) ảnh vào \(outputDir)")
