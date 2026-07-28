import SwiftUI

struct UninstallTab: View {
    @StateObject private var service = UninstallService()
    @State private var pendingApp: InstalledApp?

    var body: some View {
        TabScaffold(title: "Gỡ ứng dụng", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 12) {
                if let error = service.error {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.heat)
                        Text(error).font(.system(size: 11)).foregroundStyle(Theme.heatLight)
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.heatDeep))
                }

                switch service.phase {
                case .idle, .loading:
                    loadingView
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

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Đang đọc danh sách ứng dụng…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func removingView(_ name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Đang gỡ \(name)…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            LogView(lines: service.log)
        }
    }

    private var listView: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                TextField("Tìm ứng dụng", text: $service.search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Button("Tải lại") { service.loadApps() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(service.filteredApps) { app in
                        appRow(app)
                    }
                }
            }

            if !service.log.isEmpty {
                LogView(lines: service.log).frame(height: 110)
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
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary)
                    if app.isAppleApp {
                        Text("hệ thống")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.heatLight)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.heatDeep))
                    }
                }
                Text(app.bundleId)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(app.sizeBytes.map { ByteFormatter.string($0) } ?? "—")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(width: 74, alignment: .trailing)

            Button {
                service.reveal(app)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.card))
            }
            .buttonStyle(.plain)
            .help("Hiện trong Finder")

            Button {
                service.preview(app)
                pendingApp = app
            } label: {
                Text("Gỡ")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dangerLight)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.dangerDeep))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
    }

    private func confirmSheet(_ app: InstalledApp) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppIconView(path: app.path).frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Gỡ \(app.name)?")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(app.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.textMuted)
                }
                Spacer()
            }

            if app.isAppleApp {
                HStack(spacing: 7) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(Theme.heat)
                    Text("Đây là ứng dụng hệ thống của Apple. Gỡ có thể ảnh hưởng tới macOS.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.heatLight)
                }
                .padding(9)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.heatDeep))
            }

            Text("Những gì sẽ bị xóa (xem trước)")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    if service.previewLines.isEmpty {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Đang xem trước…")
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.textMuted)
                        }
                    } else {
                        ForEach(Array(service.previewLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(9)
            }
            .frame(height: 220)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))

            HStack {
                Text("Nora chuyển app vào Thùng rác, có thể khôi phục.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Button("Huỷ") { pendingApp = nil }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))

                Button {
                    let target = app
                    pendingApp = nil
                    service.uninstall(target)
                } label: {
                    Text("Gỡ \(app.name)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.danger))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(width: 560)
        .background(Theme.void)
    }
}

/// Renders a real app icon from its bundle path.
struct AppIconView: View {
    let path: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
    }
}
