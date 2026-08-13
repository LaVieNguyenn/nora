import SwiftUI

struct UninstallTab: View {
    @StateObject private var service = UninstallService()
    @State private var pendingApp: InstalledApp?

    var body: some View {
        Page(title: "Gỡ ứng dụng", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 12) {
                if let error = service.error {
                    NoticeBanner(message: error)
                }

                switch service.phase {
                case .idle, .loading:
                    BusyState(title: "Đang đọc danh sách ứng dụng…")
                case .removing(let name):
                    removingView(name)
                default:
                    listView
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .onAppear { if service.apps.isEmpty { service.loadApps() } }
        .sheet(item: $pendingApp) { app in
            confirmSheet(app)
        }
    }

    private var subtitle: String {
        service.apps.isEmpty
            ? "Gỡ app kèm mọi tệp còn sót lại"
            : "\(service.apps.count) ứng dụng · sắp xếp theo dung lượng"
    }

    private func removingView(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Đang gỡ \(name)…").font(.callout)
                Spacer()
            }
            LogPane(lines: service.log)
        }
    }

    private var listView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                TextField("Tìm ứng dụng", text: $service.search)
                    .textFieldStyle(.roundedBorder)
                Button("Tải lại") { service.loadApps() }
            }

            ScrollView {
                // Lazy: the machine this was measured on lists 180 apps, each
                // row carrying a real bundle icon. Building them all up front
                // was pure cost for the eight that fit on screen.
                LazyVStack(spacing: 2) {
                    ForEach(service.filteredApps) { app in
                        appRow(app)
                    }
                }
            }

            if !service.log.isEmpty {
                LogPane(lines: service.log).frame(height: 110)
            }
        }
    }

    private func appRow(_ app: InstalledApp) -> some View {
        HStack(spacing: 10) {
            AppIconView(path: app.path)
                .frame(width: 26, height: 26)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(app.name)
                        .font(.callout)
                    if app.isAppleApp {
                        Text("hệ thống")
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Theme.warning.opacity(0.15), in: Capsule())
                    }
                }
                Text(app.bundleId)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(app.sizeBytes.map { ByteFormatter.string($0) } ?? "—")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 76, alignment: .trailing)

            RevealButton { service.reveal(app) }

            Button("Gỡ", role: .destructive) {
                service.preview(app)
                pendingApp = app
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
    }

    private func confirmSheet(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppIconView(path: app.path).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gỡ \(app.name)?")
                        .font(.headline)
                    Text(app.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            if app.isAppleApp {
                NoticeBanner(
                    message: "Đây là ứng dụng hệ thống của Apple. Gỡ có thể ảnh hưởng tới macOS."
                )
            }

            SectionHeading(text: "Những gì sẽ bị xóa (xem trước)")

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if service.previewLines.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Đang xem trước…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(Array(service.previewLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(9)
            }
            .frame(height: 220)
            .background(
                Theme.sunkenBackground,
                in: RoundedRectangle(cornerRadius: Theme.controlRadius)
            )

            HStack {
                Text("Nora chuyển app vào Thùng rác, có thể khôi phục.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Huỷ", role: .cancel) { pendingApp = nil }
                Button("Gỡ \(app.name)", role: .destructive) {
                    let target = app
                    pendingApp = nil
                    service.uninstall(target)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 560)
    }
}

/// Renders a real app icon from its bundle path.
struct AppIconView: View {
    let path: String

    /// `icon(forFile:)` hits the icon services daemon; uncached it ran per row
    /// per keystroke while filtering the list. Bounded, so a long session
    /// browsing a large /Applications cannot pin every icon it ever drew.
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 120
        return cache
    }()

    var body: some View {
        Image(nsImage: Self.icon(for: path))
            .resizable()
            .interpolation(.high)
            .accessibilityHidden(true)
    }

    private static func icon(for path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let icon = NSWorkspace.shared.icon(forFile: path)
        // The daemon hands back a multi-representation image sized for Finder's
        // largest thumbnail; these rows draw it at 26pt. Keeping the full set
        // pinned a few megabytes per screenful of apps for nothing.
        icon.size = NSSize(width: 64, height: 64)
        cache.setObject(icon, forKey: path as NSString)
        return icon
    }
}
