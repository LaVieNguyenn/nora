import SwiftUI

/// Sidebar plus content. The sidebar is a plain list rather than SwiftUI's
/// `NavigationSplitView` so it keeps the dark space surface instead of the
/// system's translucent sidebar material.
struct MainWindow: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.hairline)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(Theme.void)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Nora")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12)
                .padding(.top, 30)
                .padding(.bottom, 14)

            ForEach(MainTab.allCases) { tab in
                SidebarRow(tab: tab, selected: state.selectedTab == tab) {
                    state.selectedTab = tab
                }
            }

            Spacer()
        }
        // Fixed and un-squeezable: in an HStack a flexible sidebar is the
        // first thing SwiftUI compresses when the content asks for more room,
        // which is how it ended up clipped to a sliver.
        .frame(width: 158)
        .padding(.horizontal, 8)
        .frame(width: 174)
        .fixedSize(horizontal: true, vertical: false)
        .background(Theme.panel)
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

struct SidebarRow: View {
    let tab: MainTab
    let selected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 12))
                    .frame(width: 16)
                Text(tab.label)
                    .font(.system(size: 12, weight: selected ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected ? Theme.cpuLight : Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(selected ? Theme.cpuDeep : (hovering ? Theme.card : .clear))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Shared page scaffolding: a title row and a scrolling body.
struct TabScaffold<Content: View>: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if let trailing { trailing }
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
            .padding(.bottom, 16)

            content()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
