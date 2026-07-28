import SwiftUI

struct AnalyzeTab: View {
    @StateObject private var service = AnalyzeService()
    @State private var hoveredPath: String?

    var body: some View {
        TabScaffold(title: "Phân tích ổ đĩa", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 12) {
                breadcrumb

                if let error = service.error {
                    errorBanner(error)
                }

                if service.isScanning && service.result == nil {
                    scanningPlaceholder
                } else if let result = service.result {
                    resultBody(result)
                } else {
                    startPlaceholder
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .onAppear {
            if service.result == nil { service.scan(AnalyzeService.defaultRoot) }
        }
    }

    private var subtitle: String {
        guard let result = service.result else { return "Xem thư mục nào đang chiếm nhiều chỗ nhất" }
        let files = result.totalFiles.map { " · \($0.formatted()) tệp" } ?? ""
        return "\(ByteFormatter.string(result.totalSize ?? 0))\(files)"
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button {
                service.reset()
                service.scan(AnalyzeService.defaultRoot)
            } label: {
                Image(systemName: "house")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)

            ForEach(Array(service.trail.enumerated()), id: \.offset) { index, path in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textMuted)
                }
                Button {
                    service.goUp(to: path)
                } label: {
                    Text((path as NSString).lastPathComponent)
                        .font(.system(size: 11, weight: index == service.trail.count - 1 ? .medium : .regular))
                        .foregroundStyle(index == service.trail.count - 1 ? Theme.textPrimary : Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }

            if service.isScanning {
                ProgressView().controlSize(.small).padding(.leading, 4)
            }

            Spacer()
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Theme.heat)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(Theme.heatLight)
            Spacer()
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.heatDeep))
    }

    private var startPlaceholder: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.pie")
                .font(.system(size: 32))
                .foregroundStyle(Theme.disk)
            Text("Chọn thư mục để bắt đầu")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            AccentButton(title: "Quét thư mục nhà", symbol: "house") {
                service.scan(AnalyzeService.defaultRoot)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var scanningPlaceholder: some View {
        VStack(spacing: 10) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Đang quét \((service.currentPath as NSString?)?.lastPathComponent ?? "")…")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
            Text("Lần đầu quét một cây thư mục lớn có thể mất một lúc.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func resultBody(_ result: AnalyzeResult) -> some View {
        let entries = (result.entries ?? []).sorted { $0.size > $1.size }
        let maximum = entries.first?.size ?? 1

        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if !entries.isEmpty {
                    Card(title: "Thư mục con", trailing: "\(entries.count) mục") {
                        VStack(spacing: 2) {
                            ForEach(entries.prefix(24)) { entry in
                                entryRow(entry, maximum: maximum)
                            }
                        }
                    }
                }

                if let large = result.largeFiles, !large.isEmpty {
                    Card(title: "Tệp lớn nhất", trailing: "\(large.count) tệp") {
                        VStack(spacing: 2) {
                            ForEach(large.prefix(15)) { file in
                                largeFileRow(file)
                            }
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: AnalyzeResult.Entry, maximum: Int64) -> some View {
        let ratio = maximum > 0 ? Double(entry.size) / Double(maximum) : 0
        let hovered = hoveredPath == entry.path

        return Button {
            if entry.isDir { service.scan(entry.path) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.isDir ? "folder" : "doc")
                    .font(.system(size: 11))
                    .foregroundStyle(entry.isDir ? Theme.disk : Theme.textMuted)
                    .frame(width: 14)

                Text(entry.name)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .frame(width: 190, alignment: .leading)

                // Proportional bar: the widest row is the biggest child, so
                // relative weight reads without comparing numbers.
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.hairline).frame(height: 6)
                        Capsule()
                            .fill(Theme.disk.opacity(entry.isDir ? 0.9 : 0.5))
                            .frame(width: max(3, geo.size.width * ratio), height: 6)
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                }
                .frame(height: 18)

                Text(ByteFormatter.string(entry.size))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .frame(width: 74, alignment: .trailing)

                Button {
                    service.reveal(entry.path)
                } label: {
                    Image(systemName: "folder")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Theme.card))
                }
                .buttonStyle(.plain)
                .help("Hiện trong Finder")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(hovered ? Theme.card : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredPath = $0 ? entry.path : nil }
    }

    private func largeFileRow(_ file: AnalyzeResult.LargeFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(file.path)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(ByteFormatter.string(file.size))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()

            Button {
                service.reveal(file.path)
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.card))
            }
            .buttonStyle(.plain)
            .help("Hiện trong Finder")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
