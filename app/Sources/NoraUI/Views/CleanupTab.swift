import SwiftUI

struct CleanupTab: View {
    @EnvironmentObject var cleanup: CleanupService
    @State private var expanded: Set<UUID> = []
    @State private var confirming = false

    var body: some View {
        Page(title: "Dọn dẹp", subtitle: subtitle) {
            switch cleanup.phase {
            case .idle: idleView
            case .scanning: scanningView
            case .ready: readyView
            case .cleaning, .finished: runningView
            }
        }
        .alert("Xác nhận dọn dẹp", isPresented: $confirming) {
            Button("Huỷ", role: .cancel) {}
            Button(cleanup.moveToTrash ? "Chuyển vào Thùng rác" : "Xóa hẳn", role: .destructive) {
                cleanup.performClean()
            }
        } message: {
            Text(confirmMessage)
        }
    }

    private var subtitle: String {
        switch cleanup.phase {
        case .idle: return "Quét thử để xem những gì có thể dọn"
        case .scanning: return "Đang quét — chưa có gì bị xóa"
        case .ready:
            let scanned = cleanup.lastScanDate.map { date in
                " · quét lúc " + date.formatted(date: .omitted, time: .shortened)
            } ?? ""
            return "\(cleanup.itemCount) mục trong \(cleanup.groups.count) nhóm\(scanned)"
        case .cleaning: return "Đang xử lý"
        case .finished: return "Đã xong"
        }
    }

    private var confirmMessage: String {
        let size = ByteFormatter.string(cleanup.selectedBytesCached)
        return cleanup.moveToTrash
            ? "\(cleanup.selectedCount) mục (\(size)) sẽ được chuyển vào Thùng rác. "
              + "Bạn có thể khôi phục từ Finder."
            : "\(cleanup.selectedCount) mục (\(size)) sẽ bị xóa vĩnh viễn. "
              + "Thao tác này không hoàn tác được."
    }

    // MARK: - States

    private var idleView: some View {
        EmptyState(
            symbol: "sparkles",
            title: "Chưa có danh sách",
            message: "Quét thử chạy `nora clean --dry-run` và chỉ liệt kê, không xóa gì."
        ) {
            Button("Quét thử") { cleanup.scan() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
    }

    private var scanningView: some View {
        BusyState(
            title: cleanup.scanProgress.isEmpty ? "Đang chuẩn bị…" : cleanup.scanProgress,
            message: "Lần quét đầu có thể mất vài phút vì phải đo dung lượng từng thư mục.",
            onCancel: { cleanup.cancelScan() }
        )
    }

    /// One flat, lazily built list of headers and item rows.
    ///
    /// Nesting `ForEach(group.items)` inside each group's card meant expanding a
    /// group instantiated a view for every one of its rows at once — a real scan
    /// runs to a few thousand items, and building them all is where the app's
    /// memory peak came from. Flattening lets a single `LazyVStack` materialise
    /// only the rows actually on screen.
    private var readyView: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(cleanup.groups) { group in
                        Section {
                            if expanded.contains(group.id) {
                                ForEach(group.items) { item in
                                    itemRow(item)
                                }
                            }
                        } header: {
                            groupHeader(group)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 14)
            }

            actionBar
        }
        .onAppear {
            // `NORA_CLEANUP_EXPAND=1` opens every group, so the densest state
            // this screen can reach — a few thousand rows — is reachable
            // offscreen for layout checks and memory measurement.
            if ProcessInfo.processInfo.environment["NORA_CLEANUP_EXPAND"] == "1" {
                expanded = Set(cleanup.groups.map(\.id))
            }
        }
    }

    private func groupHeader(_ group: CleanupGroup) -> some View {
        let state = cleanup.selectionState(of: group)
        let isOpen = expanded.contains(group.id)

        return HStack(spacing: 10) {
            TriStateCheckbox(checked: state.checked, partial: state.partial) {
                cleanup.toggle(group: group)
            }

            Button {
                if isOpen { expanded.remove(group.id) } else { expanded.insert(group.id) }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                        .frame(width: 10)
                    Text(group.vietnameseName)
                        .font(.callout.weight(.medium))
                    Text("\(group.items.count) mục")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if group.hasUnknownSizes {
                        Text("một số mục chưa đo được")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text(ByteFormatter.string(group.totalBytes))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.bar)
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
        .padding(.top, 6)
    }

    private func itemRow(_ item: CleanupItem) -> some View {
        HStack(spacing: 9) {
            TriStateCheckbox(
                checked: cleanup.selection.contains(item.id),
                partial: false
            ) { cleanup.toggle(item) }

            Text(item.displayPath)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(cleanup.selection.contains(item.id) ? Theme.label : Theme.secondaryLabel)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(item.path)

            if item.itemCount > 1 {
                Text("\(item.itemCount) mục")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(item.sizeBytes.map { ByteFormatter.string($0) } ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 68, alignment: .trailing)

            RevealButton { cleanup.revealInFinder(item) }
        }
        .padding(.leading, 34)
        .padding(.trailing, 8)
        .padding(.vertical, 3)
    }

    private var actionBar: some View {
        ActionBar {
            Toggle("Chuyển vào Thùng rác", isOn: $cleanup.moveToTrash)
                .toggleStyle(.checkbox)
                .help("Có thể khôi phục từ Finder. Bỏ chọn để xóa hẳn.")

            Spacer()

            VStack(alignment: .trailing, spacing: 0) {
                Text("\(cleanup.selectedCount) mục được chọn")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(ByteFormatter.string(cleanup.selectedBytesCached))
                    .font(.callout.weight(.medium))
                    .monospacedDigit()
            }

            Button("Quét lại") { cleanup.scan() }

            Button {
                confirming = true
            } label: {
                Label("Dọn \(ByteFormatter.string(cleanup.selectedBytesCached))",
                      systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(cleanup.selectedCount == 0)
        }
    }

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if cleanup.phase == .cleaning {
                    ProgressView().controlSize(.small)
                    Text("Đang xử lý — \(cleanup.itemsProcessed)/\(cleanup.selectedCount) mục")
                        .font(.callout)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.success)
                    Text("Hoàn tất")
                        .font(.callout.weight(.medium))
                }
                Spacer()
                Text(ByteFormatter.string(cleanup.bytesFreed))
                    .font(.callout)
                    .monospacedDigit()
            }

            ProgressView(
                value: Double(cleanup.itemsProcessed),
                total: Double(max(cleanup.selectedCount, 1))
            )

            LogPane(lines: cleanup.log)

            HStack {
                Text(cleanup.moveToTrash
                     ? "Các mục nằm trong Thùng rác — dọn Thùng rác để lấy lại dung lượng."
                     : "Đã xóa vĩnh viễn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Sao chép log") { cleanup.copyLog() }

                if cleanup.phase == .cleaning {
                    Button("Dừng", role: .destructive) { cleanup.requestCancel() }
                } else {
                    Button {
                        cleanup.scan()
                    } label: {
                        Label("Quét lại", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
    }
}
