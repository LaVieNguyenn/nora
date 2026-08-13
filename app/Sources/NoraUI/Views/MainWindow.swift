import SwiftUI

/// Sidebar plus content.
///
/// The sidebar is a stock `List` in the `.sidebar` style, so it draws the
/// system's own material, row metrics and selection shape — everything the
/// hand-built `VStack` of buttons it replaces was approximating by hand.
///
/// Not a `NavigationSplitView`, which would also give a draggable divider: its
/// sidebar renders nothing at all through `LayoutSnapshot`, so the layout of
/// the one window this app has would stop being checkable here. That is the
/// only tool for it — this machine grants no screen recording, so `screencapture`
/// returns nothing. A verifiable sidebar beats a resizable one.
struct MainWindow: View {
    @EnvironmentObject var state: AppState

    /// `List` wants an optional selection; the app always has a tab open, so a
    /// nil write is ignored rather than allowed to blank the detail pane.
    private var selection: Binding<MainTab?> {
        Binding(
            get: { state.selectedTab },
            set: { if let new = $0 { state.selectedTab = new } }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            List(MainTab.allCases, selection: selection) { tab in
                Label(tab.label, systemImage: tab.symbol)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            // Fixed and un-squeezable: in an `HStack` a flexible sidebar is the
            // first thing SwiftUI compresses when the content asks for more
            // room, which is how the previous one ended up clipped to a sliver.
            .frame(width: 196)
            .fixedSize(horizontal: true, vertical: false)

            Divider()

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Theme.windowBackground)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state.selectedTab {
        case .overview: OverviewTab()
        case .cleanup: CleanupTab()
        case .analyze: AnalyzeTab()
        case .uninstall: UninstallTab()
        case .optimize: OptimizeTab()
        case .history: HistoryTab()
        case .settings: SettingsTab()
        }
    }
}

/// Shared page scaffolding: a title row, an optional action area beside it, and
/// the body underneath.
struct Page<Actions: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    if let subtitle {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 12)
                actions()
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 16)

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

extension Page where Actions == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(title: title, subtitle: subtitle, actions: { EmptyView() }, content: content)
    }
}

/// The bar pinned to the bottom of a page for its primary actions.
///
/// A separator and the window's own chrome colour, so it reads as attached to
/// the window rather than as another floating card.
struct ActionBar<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                content()
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(.bar)
        }
    }
}
