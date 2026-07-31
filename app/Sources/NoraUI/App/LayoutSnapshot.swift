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

        let root = MainWindow()
            .environmentObject(AppState.shared)
            .environmentObject(AppState.shared.stream)
            .environmentObject(AppState.shared.batteries)
            .environmentObject(AppState.shared.settings)
            .environmentObject(AppState.shared.cleanup)

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
