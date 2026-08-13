import SwiftUI

struct AnalyzeTab: View {
    @StateObject private var service = AnalyzeService()
    @State private var hoveredPath: String?

    var body: some View {
        Page(title: "Phân tích ổ đĩa", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 12) {
                breadcrumb

                if let error = service.error {
                    NoticeBanner(message: error)
                }

                if service.isScanning && service.result == nil {
                    BusyState(
                        title: "Đang quét \((service.currentPath as NSString?)?.lastPathComponent ?? "")…",
                        message: "Lần đầu quét một cây thư mục lớn có thể mất một lúc."
                    )
                } else if let result = service.result {
                    resultBody(result)
                } else {
                    EmptyState(
                        symbol: "chart.pie",
                        title: "Chọn thư mục để bắt đầu",
                        message: "Nora đo từng thư mục con rồi xếp theo dung lượng, "
                                 + "để chỗ chiếm nhiều nhất nổi lên đầu.",
                        tint: Metric.disk.tint
                    ) {
                        Button("Quét thư mục nhà") { service.scan(AnalyzeService.defaultRoot) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .onAppear {
            if service.result == nil { service.scan(AnalyzeService.defaultRoot) }
        }
        // A scan of a home directory decodes thousands of entries. Nothing reads
        // them once the tab is gone, and the window is opened and closed far
        // more often than it is scanned.
        .onDisappear { service.discard() }
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
            }
            .buttonStyle(.borderless)
            .help("Về thư mục nhà")

            ForEach(Array(service.trail.enumerated()), id: \.offset) { index, path in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
                Button {
                    service.goUp(to: path)
                } label: {
                    Text((path as NSString).lastPathComponent)
                        .font(.callout)
                        .fontWeight(index == service.trail.count - 1 ? .medium : .regular)
                        .foregroundStyle(
                            index == service.trail.count - 1 ? Theme.label : Theme.secondaryLabel
                        )
                }
                .buttonStyle(.plain)
            }

            if service.isScanning {
                ProgressView().controlSize(.small).padding(.leading, 4)
            }

            Spacer()
        }
    }

    private func resultBody(_ result: AnalyzeResult) -> some View {
        // Sort once per result, not per body evaluation: this runs again on
        // every hover, and the entry list of a home directory is not short.
        let entries = service.sortedEntries
        let maximum = entries.first?.size ?? 1

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !entries.isEmpty {
                    SectionCard(title: "Thư mục con", subtitle: "\(entries.count) mục",
                                systemImage: "folder") {
                        VStack(spacing: 1) {
                            ForEach(entries.prefix(24)) { entry in
                                entryRow(entry, maximum: maximum)
                            }
                        }
                    }
                }

                if let large = result.largeFiles, !large.isEmpty {
                    SectionCard(title: "Tệp lớn nhất", subtitle: "\(large.count) tệp",
                                systemImage: "doc") {
                        VStack(spacing: 1) {
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
                    .font(.callout)
                    .foregroundStyle(entry.isDir ? Metric.disk.tint : Theme.tertiaryLabel)
                    .frame(width: 14)

                Text(entry.name)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: 190, alignment: .leading)

                Meter(value: ratio, tint: Metric.disk.tint.opacity(entry.isDir ? 1 : 0.55))

                Text(ByteFormatter.string(entry.size))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 76, alignment: .trailing)

                RevealButton { service.reveal(entry.path) }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Theme.controlRadius)
                    .fill(hovered ? Theme.separator.opacity(0.5) : .clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hoveredPath = $0 ? entry.path : nil }
        .accessibilityLabel("\(entry.name), \(ByteFormatter.string(entry.size))")
    }

    private func largeFileRow(_ file: AnalyzeResult.LargeFile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .frame(width: 14)

            VStack(alignment: .leading, spacing: 1) {
                Text(file.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(file.path)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(ByteFormatter.string(file.size))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            RevealButton { service.reveal(file.path) }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
