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
/// every one of those routes is a silent no-op or a crash. What it can do is
/// operate on objects prepared in advance, during launch, where the main actor
/// still works. Everything the click needs is therefore built in `install()`
/// and cached here as plain references.
/// `@unchecked Sendable` because every member is touched from the main thread
/// only — AppKit callbacks, the launch task, and the collector's Combine sink
/// all run there. The compiler cannot see that, and the usual way to prove it
/// (main-actor isolation) is exactly what breaks in this process.
final class StatusItemController: NSObject, @unchecked Sendable {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    /// Built once at install time so the click path never constructs a view.
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
        // debugging round by making working timers look dead.
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
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

        // Build the popover now, while the main actor is usable. Constructing
        // it lazily on click would put SwiftUI view creation on the very path
        // that cannot reach the main actor.
        popover = makePopover()

        apply(title: AppState.shared.menubarText, tint: NSColor(AppState.shared.menubarTint))
        Self.trace("install: status item đã tạo, visible=\(item.isVisible)")
    }

    /// Update the button from values the caller already computed.
    ///
    /// Takes plain `String`/`NSColor` rather than reading `AppState`, so it is
    /// safe to call from anywhere without an isolation check.
    func apply(title: String, tint: NSColor) {
        guard let button = statusItem?.button else { return }

        // A template image renders in the menubar's own foreground colour —
        // black on a light bar, which is what made this unreadable. Bake the
        // metric's colour into the bitmap instead.
        let base = NSImage(
            systemSymbolName: "circle.hexagongrid.fill",
            accessibilityDescription: "Nora"
        )?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))

        button.image = base.map { Self.tinted($0, with: tint) }
        // Never leave both image and title empty: a zero-width button takes no
        // menubar space and simply never appears.
        button.title = title.isEmpty ? (base == nil ? "Nora" : "") : " \(title)"
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
    }

    /// Return a copy of `image` filled with `color`, keeping its alpha shape.
    private static func tinted(_ image: NSImage, with color: NSColor) -> NSImage {
        let copy = NSImage(size: image.size)
        copy.lockFocus()
        image.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        copy.unlockFocus()
        copy.isTemplate = false
        return copy
    }

    /// AppKit calls this on the main thread, outside any task. It touches only
    /// the cached AppKit objects — no main-actor state, no hop, no await.
    @objc private func handleClick() {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        // `.minY` is the button's bottom edge — the popover hangs directly
        // under the menubar. `.maxY` asks for it *above* the item, where there
        // is no screen, so AppKit relocates it and it lands far from the icon.
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    @MainActor
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
        return popover
    }

    /// Regression probe: open the popover the way a click does and hold it.
    ///
    /// The crash only appeared once the popover stayed open while fresh
    /// snapshots re-evaluated its body, so a click-and-close test missed it.
    func showForTest() {
        Self.trace("clicktest: chờ 20s rồi bấm")
        let timer = Timer(timeInterval: 20, repeats: false) { [weak self] _ in
            Self.trace("clicktest: bấm nút menubar")
            self?.statusItem?.button?.performClick(nil)

            let hold = Timer(timeInterval: 70, repeats: false) { _ in
                Self.trace("clicktest: popover mở 70s sau cú bấm, không crash")
            }
            RunLoop.main.add(hold, forMode: .common)
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
