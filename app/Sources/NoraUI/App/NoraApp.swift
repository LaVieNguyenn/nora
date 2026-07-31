import SwiftUI
import AppKit

/// Plain AppKit entry point.
///
/// SwiftUI's `App` lifecycle does not work for this app. With no real scene —
/// a menubar utility has none, so the only option was `Settings { EmptyView() }`
/// — the process ends up with a run loop that services RunLoop timers but never
/// drains the main dispatch queue. Measured consequences: `Task { @MainActor }`
/// bodies enqueued after launch never execute, `Task.sleep` never resumes,
/// `DispatchQueue.main.asyncAfter` never fires, and `swift_task_isCurrentExecutor`
/// faults because the main executor was never properly started — which is the
/// segfault every click produced. Driving `NSApplication` directly gives a
/// normally running app.
@main
enum NoraUIMain {
    static func main() {
        // `--selftest` exercises the parsers against this machine's real data
        // and exits without ever reaching the menubar.
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest.run())
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // Menubar-only: no Dock tile, no menu bar of its own.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            AppState.shared.start()
            StatusItemController.shared.install()

            // A full menubar means macOS silently declines to place the item.
            // Say so rather than leaving the user hunting for an icon that was
            // never drawn.
            if !StatusItemController.shared.isVisible {
                NSLog("Nora: menubar không còn chỗ trống — dùng nora-window.sh để mở cửa sổ chính")
            }

            // Handled here, not in `App.init`: the probe clicks the status
            // item, which does not exist until `install()` above has run.
            if CommandLine.arguments.contains("--popovertest") {
                StatusItemController.shared.showForTest()
            }

            if CommandLine.arguments.contains("--popovercycle") {
                StatusItemController.shared.cycleForTest()
            }

            // `--snapshot=<path>[:<tab>]` renders the window offscreen and
            // quits. Give the collector a moment first, so the shot shows real
            // numbers rather than every card in its placeholder state.
            if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--snapshot=") }) {
                let spec = arg.replacingOccurrences(of: "--snapshot=", with: "")
                let parts = spec.split(separator: ":", maxSplits: 2).map(String.init)
                let path = parts[0]
                let tab = parts.count > 1 ? (MainTab(rawValue: parts[1]) ?? .overview) : .overview

                let timer = Timer(timeInterval: 6, repeats: false) { _ in
                    // `--snapshot=<path>:<tab>:<width>` so the narrow end of
                    // the supported range can be checked too.
                    let width = parts.count > 2 ? (Double(parts[2]) ?? 1020) : 1020
                    LayoutSnapshot.render(
                        to: path, tab: tab, size: NSSize(width: width, height: 700))
                    NSApp.terminate(nil)
                }
                RunLoop.main.add(timer, forMode: .common)
            }
        }

        // On a notched Mac with a crowded menubar the status item can end up
        // behind the notch and be unreachable. `--window` gives a way in that
        // does not depend on finding the icon.
        if CommandLine.arguments.contains("--window") {
            // `--window=<tab>` opens straight onto one tab. Building a tab
            // without a click separates "constructing this view crashes" from
            // "dispatching the button crashes"; the stack trace cannot, because
            // SwiftUI builds the new tab inside the button's own dispatch.
            let requested = CommandLine.arguments
                .first { $0.hasPrefix("--window=") }?
                .replacingOccurrences(of: "--window=", with: "")
            let tab = requested.flatMap(MainTab.init(rawValue:)) ?? .overview
            DispatchQueue.main.async { MainWindowPresenter.shared.open(tab: tab) }
        }

        if CommandLine.arguments.contains("--uitest") {
            DispatchQueue.main.async { UITest.run() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        DispatchQueue.main.async { AppState.shared.stop() }
    }

    /// The main window is created on demand, so a re-open click should surface
    /// it rather than doing nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        DispatchQueue.main.async { MainWindowPresenter.shared.open(tab: .overview) }
        return true
    }
}
