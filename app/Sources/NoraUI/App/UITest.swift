import AppKit
import Foundation

/// `NoraUI --uitest` opens the main window and clicks its way down the sidebar
/// on its own.
///
/// The app crashed reliably on the first button press, inside SwiftUI's own
/// gesture dispatch, with no frame of this app in the stack. Reproducing that
/// under a sanitizer needs a click, and posting events into our own event queue
/// needs no accessibility grant — unlike driving the app from System Events.
enum UITest {
    static func run() {
        MainWindowPresenter.shared.open(tab: .overview)

        // Let the window and its SwiftUI hosting view settle before poking it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { clickSidebar(row: 0) }
    }

    /// Sidebar geometry from `MainWindow`: 158pt column, title block above the
    /// rows, ~29pt per row.
    private static func clickSidebar(row: Int) {
        guard row < MainTab.allCases.count else {
            NSLog("UITEST: hết hàng, không crash")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            return
        }
        guard let window = NSApp.windows.first(where: { $0.contentView != nil && $0.isVisible }) else {
            NSLog("UITEST: chưa thấy cửa sổ")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            return
        }

        let titleBlockHeight: CGFloat = 62
        let rowHeight: CGFloat = 29
        let fromTop = titleBlockHeight + CGFloat(row) * rowHeight + rowHeight / 2
        let point = NSPoint(x: 80, y: window.frame.height - fromTop)

        NSLog("UITEST: bấm hàng \(row) (\(MainTab.allCases[row].rawValue)) tại \(point.x),\(point.y)")
        post(.leftMouseDown, at: point, in: window)
        post(.leftMouseUp, at: point, in: window)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { clickSidebar(row: row + 1) }
    }

    private static func post(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow) {
        guard let event = NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseDown ? 1 : 0
        ) else { return }

        NSApp.postEvent(event, atStart: false)
    }
}
