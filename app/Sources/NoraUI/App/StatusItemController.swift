import AppKit
import SwiftUI
import Combine

/// Owns the menubar item and the popover hung off it.
///
/// Deliberately **not** `@MainActor`, and it touches no main-actor state on the
/// click path.
///
/// Measured in this process: a `Task { @MainActor }` created from an AppKit
/// target/action or a `Timer` callback never executes, `Task.sleep` never
/// resumes, and `MainActor.assumeIsolated` segfaults. So the click handler
/// cannot hop to the main actor, cannot await, and cannot assert isolation —
/// every one of those routes is a silent no-op or a crash.
///
/// `@unchecked Sendable` because every member is touched from the main thread
/// only — AppKit callbacks, the launch task, and the collector's Combine sink
/// all run there. The compiler cannot see that, and the usual way to prove it
/// (main-actor isolation) is exactly what breaks in this process.
final class StatusItemController: NSObject, @unchecked Sendable {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    /// Alive only while the popover is on screen; released in `popoverDidClose`.
    private var popover: NSPopover?

    /// True when macOS actually gave the item a place on the menubar.
    var isVisible: Bool {
        guard let button = statusItem?.button, let window = button.window else { return false }
        return window.frame.width > 0 && button.frame.width > 0
    }

    /// Append one diagnostic line to `~/Library/Logs/NoraUI.log`.
    static func trace(_ message: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/NoraUI.log")
        let line = "\(Date()) \(message)\n"

        // Read-modify-write rather than an appending FileHandle: the handle
        // path silently dropped every write after the first, which cost a whole
        // debugging round by making working timers look dead. Keep only the
        // tail so the file cannot grow without bound across months of
        // launches.
        var existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        if existing.count > 64_000 {
            existing = String(existing.suffix(32_000))
        }
        try? (existing + line).write(to: url, atomically: true, encoding: .utf8)
    }

    /// Called once during launch, from a context where the main actor works.
    @MainActor
    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        // macOS persists per-item visibility: an item the user once ⌘-dragged
        // off the menubar stays hidden on every later launch.
        item.isVisible = true

        guard let button = item.button else {
            Self.trace("install: KHÔNG có button")
            return
        }

        button.target = self
        button.action = #selector(handleClick)
        button.imagePosition = .imageLeading

        // The popover is built on first click and torn down when it closes —
        // see `handleClick`. Building it here left a live SwiftUI view graph
        // subscribed to the collector for the whole session: every snapshot
        // re-laid-out bubbles nobody was looking at. Measured after three days
        // of that: 12% CPU and 93 MB, against 0.07% and 47 MB at launch.
        apply(title: AppState.shared.menubarText, tint: NSColor(AppState.shared.menubarTint))
        Self.trace("install: status item đã tạo, visible=\(item.isVisible)")
    }

    /// Update the button from values the caller already computed.
    ///
    /// Takes plain `String`/`NSColor` rather than reading `AppState`, so it is
    /// safe to call from anywhere without an isolation check.
    private var lastApplied: (title: String, tint: NSColor)?
    private var markCache: [String: NSImage] = [:]

    func apply(title: String, tint: NSColor) {
        guard let button = statusItem?.button else { return }

        // A frame arrives every 2s; redrawing the mark and reassigning the
        // image forced a status-bar relayout each time even when nothing
        // changed. The tint only has a handful of values, so cache by tint and
        // skip entirely when both parts are unchanged.
        if let last = lastApplied, last.title == title, last.tint == tint { return }
        lastApplied = (title, tint)

        let key = tint.description
        let mark: NSImage
        if let cached = markCache[key] {
            mark = cached
        } else {
            mark = Self.orbitMark(tint: tint)
            markCache[key] = mark
        }
        button.image = mark
        // Never leave both image and title empty: a zero-width button takes no
        // menubar space and simply never appears.
        button.title = title.isEmpty ? "" : " \(title)"
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }

    /// Nora's menubar mark: a filled body with an orbit ring around it.
    ///
    /// Drawn rather than taken from SF Symbols. The stock glyph that was here
    /// belonged to no particular app, and a template symbol renders in the
    /// menubar's own foreground colour — black on a light bar — which threw
    /// away the one thing the mark carries: the colour of whichever metric is
    /// running hottest.
    private static func orbitMark(tint: NSColor) -> NSImage {
        let side: CGFloat = 16
        let image = NSImage(size: NSSize(width: side, height: side))

        image.lockFocus()
        defer { image.unlockFocus() }

        guard let context = NSGraphicsContext.current?.cgContext else { return image }
        context.setShouldAntialias(true)

        let centre = CGPoint(x: side / 2, y: side / 2)

        // Orbit: a flattened ellipse, tilted — Nora's mark.
        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: -.pi / 7)
        context.setStrokeColor(tint.withAlphaComponent(0.85).cgColor)
        context.setLineWidth(1.1)
        context.strokeEllipse(in: CGRect(x: -7, y: -3.1, width: 14, height: 6.2))
        context.restoreGState()

        // Body: solid, so the mark still reads at a glance when the ring is
        // reduced to a couple of pixels.
        context.setFillColor(tint.cgColor)
        context.fillEllipse(in: CGRect(
            x: centre.x - 3.1, y: centre.y - 3.1, width: 6.2, height: 6.2))

        image.isTemplate = false
        return image
    }

    /// AppKit calls this on the main thread, outside any task. It touches only
    /// the cached AppKit objects — no main-actor state, no hop, no await.
    @objc private func handleClick() {
        guard let button = statusItem?.button else { return }

        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        // Built here, not at install time: the view tree should exist only
        // while it is on screen.
        let popover = makePopover()
        self.popover = popover

        NSApp.activate(ignoringOtherApps: true)
        // `.minY` is the button's bottom edge — the popover hangs directly
        // under the menubar. `.maxY` asks for it *above* the item, where there
        // is no screen, so AppKit relocates it and it lands far from the edge.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false

        let root = MenuBarPopover()
            .environmentObject(AppState.shared)
            .environmentObject(AppState.shared.stream)
            .environmentObject(AppState.shared.batteries)
            .environmentObject(AppState.shared.settings)

        let hosting = NSHostingController(rootView: root)
        // Let SwiftUI report its own height instead of pinning a guess: the
        // device list grows and shrinks with what is paired, and a fixed height
        // leaves either dead space or a clipped footer.
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.delegate = self
        return popover
    }

    /// Regression probe: open and close the popover repeatedly, reporting
    /// resident memory each round.
    ///
    /// Closing an NSPopover does not free its hosting controller by itself, and
    /// a view tree that outlives the popover keeps re-rendering off every
    /// snapshot. A cycle test is the only way to see that: a single open, or a
    /// long hold, both look fine.
    func cycleForTest(rounds: Int = 6) {
        var round = 0
        let timer = Timer(timeInterval: 3, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            if round >= rounds * 2 {
                Self.trace("cycletest: xong \(rounds) vòng, RSS=\(Self.residentMB()) MB")
                t.invalidate()
                return
            }
            self.statusItem?.button?.performClick(nil)
            if round % 2 == 1 {
                Self.trace("cycletest: sau vòng \((round + 1) / 2), RSS=\(Self.residentMB()) MB")
            }
            round += 1
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// This process's resident size, in MB.
    static func residentMB() -> Int { MemoryRelief.residentMB() }
}

extension StatusItemController: NSPopoverDelegate {
    /// Drop the view tree the moment the popover closes.
    ///
    /// Closing an NSPopover only hides it; the hosting controller, its SwiftUI
    /// view graph and every `@EnvironmentObject` subscription stay alive. That
    /// left the collector re-laying-out invisible bubbles on every snapshot for
    /// as long as the app ran, which is where the drift from 0.07% to 12% CPU
    /// came from.
    func popoverDidClose(_ notification: Notification) {
        popover?.contentViewController = nil
        popover = nil
        // Every open builds a fresh view tree and its backing store; hand the
        // pages back rather than accumulating a high-water mark across a day of
        // glancing at the menubar.
        MemoryRelief.release()
    }
}
