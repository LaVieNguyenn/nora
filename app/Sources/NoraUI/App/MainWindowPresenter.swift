import SwiftUI
import AppKit

/// Owns the single main window.
///
/// `MenuBarExtra` apps run as accessory agents, so a SwiftUI `Window` scene
/// cannot reliably be raised from a popover click. Hosting the view in an
/// `NSWindow` gives direct control over ordering and activation.
final class MainWindowPresenter: NSObject {
    static let shared = MainWindowPresenter()

    private var window: NSWindow?

    func open(tab: MainTab) {
        AppState.shared.selectedTab = tab

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: MainWindow()
                .environmentObject(AppState.shared)
                .environmentObject(AppState.shared.stream)
                .environmentObject(AppState.shared.batteries)
                .environmentObject(AppState.shared.settings)
                .environmentObject(AppState.shared.cleanup)
        )

        let window = NSWindow(contentViewController: hosting)
        window.title = "Nora"
        window.setContentSize(NSSize(width: 1020, height: 700))
        // Below this the two-column rows collapse into unreadable slivers, so
        // the window refuses to go there rather than rendering something the
        // user has to guess at.
        window.minSize = NSSize(width: 900, height: 560)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.backgroundColor = NSColor(Theme.void)
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self

        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

extension MainWindowPresenter: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // Drop the reference so the next open builds a fresh view tree rather
        // than resurrecting one whose observers were torn down.
        window = nil
    }
}
