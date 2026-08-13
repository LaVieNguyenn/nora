import AppKit
import SwiftUI

/// `NoraUI --snapshot <path>` renders the main window to a PNG and exits.
///
/// The machine this is developed on does not grant screen recording, so
/// `screencapture` returns nothing and layout bugs — a clipped sidebar, a card
/// wrapping onto its own line — could only be found by asking the user to look.
/// Rendering the view tree offscreen makes the layout checkable here.
enum LayoutSnapshot {
    static func render(to path: String, tab: MainTab, size: NSSize) {
        AppState.shared.selectedTab = tab

        // `NORA_CLEANUP_LEDGER=1` populates the cleanup tab from the ledger a
        // previous scan left on disk, so its full list — the densest screen in
        // the app — can be laid out and measured without waiting minutes for a
        // real scan.
        if tab == .cleanup,
           Foundation.ProcessInfo.processInfo.environment["NORA_CLEANUP_LEDGER"] == "1" {
            AppState.shared.cleanup.loadCachedLedger()
        }

        let root = MainWindow()
            .environmentObject(AppState.shared)
            .environmentObject(AppState.shared.stream)
            .environmentObject(AppState.shared.batteries)
            .environmentObject(AppState.shared.settings)
            .environmentObject(AppState.shared.cleanup)

        capture(AnyView(root), to: path, size: size)
    }

    /// The popover is the surface the app is used through, and until this
    /// existed it was the one surface that could not be checked here at all —
    /// `render` only ever built the main window.
    ///
    /// The metric names which detail panel to open, so the panels get exercised
    /// too; `nil` shows the bare metric list.
    static func renderPopover(to path: String, metric: Metric?) {
        let root = MenuBarPopover()
            .environmentObject(AppState.shared)
            .environmentObject(AppState.shared.stream)
            .environmentObject(AppState.shared.batteries)
            .environmentObject(AppState.shared.settings)

        if let metric {
            setenv("NORA_POPOVER_OPEN", metric.rawValue, 1)
        }

        // The popover paints no background of its own — on screen `NSPopover`
        // draws the system material behind it. Offscreen there is nothing
        // there, so the capture came out as dark-appearance text on the
        // bitmap's blank white, i.e. invisible. The backdrop exists only for
        // this capture; nothing in the popover itself draws it.
        let backed = ZStack {
            Color(nsColor: .windowBackgroundColor)
            root
        }

        // The popover sizes itself; give it its fixed width and let the height
        // come from the content, the same way `NSPopover` does.
        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.frame = NSRect(x: 0, y: 0, width: 330, height: 2000)
        hosting.layoutSubtreeIfNeeded()
        let fitted = hosting.fittingSize

        capture(
            AnyView(backed),
            to: path,
            size: NSSize(width: 330, height: max(fitted.height, 320))
        )
    }

    private static func capture(_ root: AnyView, to path: String, size: NSSize) {
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()

        // A hosting view only produces content once it belongs to a window.
        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()

        // Let the run loop turn so the work `onAppear` kicks off — the process
        // list, which is a subprocess — lands before the capture. Without this
        // every snapshot showed that card in its loading state.
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            FileHandle.standardError.write("không tạo được bitmap\n".data(using: .utf8)!)
            return
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)

        guard let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("không mã hoá được PNG\n".data(using: .utf8)!)
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("đã ghi \(path)")
    }
}
