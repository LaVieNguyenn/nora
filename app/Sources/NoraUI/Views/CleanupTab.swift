import SwiftUI

struct CleanupTab: View {
    @EnvironmentObject var cleanup: CleanupService
    @State private var expanded: Set<UUID> = []
    @State private var confirming = false

    var body: some View {
        TabScaffold(title: "Dọn dẹp", subtitle: subtitle) {
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
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm"
                return " · quét lúc \(formatter.string(from: date))"
            } ?? ""
            return "\(cleanup.allItems.count) mục trong \(cleanup.groups.count) nhóm\(scanned)"
        case .cleaning: return "Đang xử lý"
        case .finished: return "Đã xong"
        }
    }

    private var confirmMessage: String {
        let count = cleanup.selectedItems.count
        let size = ByteFormatter.string(cleanup.selectedBytes)
        return cleanup.moveToTrash
            ? "\(count) mục (\(size)) sẽ được chuyển vào Thùng rác. Bạn có thể khôi phục từ Finder."
            : "\(count) mục (\(size)) sẽ bị xóa vĩnh viễn. Thao tác này không hoàn tác được."
    }

    // MARK: - States

    private var idleView: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 34))
                .foregroundStyle(Theme.cpu)
            Text("Chưa có danh sách")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Text("Quét thử chạy `nora clean --dry-run` và chỉ liệt kê, không xóa gì.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            AccentButton(title: "Quét thử", symbol: "magnifyingglass") { cleanup.scan() }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text(cleanup.scanProgress.isEmpty ? "Đang chuẩn bị…" : cleanup.scanProgress)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
            Text("Lần quét đầu có thể mất vài phút vì phải đo dung lượng từng thư mục.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textMuted)
            Button("Dừng quét") { cleanup.cancelScan() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var readyView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(cleanup.groups) { group in
                        groupCard(group)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 14)
            }

            actionBar
        }
    }

    private func groupCard(_ group: CleanupGroup) -> some View {
        let state = cleanup.selectionState(of: group)
        let isOpen = expanded.contains(group.id)

        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                TriStateCheckbox(checked: state.checked, partial: state.partial) {
                    cleanup.toggle(group: group)
                }

                Button {
                    if isOpen { expanded.remove(group.id) } else { expanded.insert(group.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 10)
                        Circle()
                            .fill(groupColor(group))
                            .frame(width: 8, height: 8)
                        Text(group.vietnameseName)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("· \(group.items.count) mục")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textMuted)
                        Spacer()
                        if group.hasUnknownSizes {
                            Text("một số mục chưa đo được")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textMuted)
                        }
                        Text(ByteFormatter.string(group.totalBytes))
                            .font(.system(size: 11))
                            .foregroundStyle(groupColor(group))
                            .monospacedDigit()
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(group.items) { item in
                        itemRow(item)
                    }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.hairline, lineWidth: 0.5))
    }

    private func itemRow(_ item: CleanupItem) -> some View {
        HStack(spacing: 9) {
            TriStateCheckbox(
                checked: cleanup.selection.contains(item.id),
                partial: false
            ) { cleanup.toggle(item) }

            Text(item.displayPath)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(cleanup.selection.contains(item.id) ? Theme.textPrimary : Theme.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(item.path)

            if item.itemCount > 1 {
                Text("\(item.itemCount) mục")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
            }

            Text(item.sizeBytes.map { ByteFormatter.string($0) } ?? "—")
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textMuted)
                .monospacedDigit()
                .frame(width: 66, alignment: .trailing)

            Button {
                cleanup.revealInFinder(item)
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
        .padding(.leading, 34)
        .padding(.trailing, 12)
        .padding(.vertical, 5)
        .background(Theme.void.opacity(0.35))
    }

    private func groupColor(_ group: CleanupGroup) -> Color {
        switch group.name {
        case "Developer tools": return Theme.cpu
        case "Browsers": return Theme.ram
        case "App caches": return Theme.disk
        case "User essentials": return Theme.net
        case "Application Support": return Theme.heat
        default: return Theme.good
        }
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.hairline)
            HStack(spacing: 12) {
                Toggle(isOn: $cleanup.moveToTrash) {
                    Text("Chuyển vào Thùng rác")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                }
                .toggleStyle(.checkbox)
                .help("Có thể khôi phục từ Finder. Bỏ chọn để xóa hẳn.")

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("\(cleanup.selectedItems.count) mục được chọn")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted)
                    Text(ByteFormatter.string(cleanup.selectedBytes))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ramLight)
                        .monospacedDigit()
                }

                Button("Quét lại") { cleanup.scan() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))

                AccentButton(
                    title: "Dọn \(ByteFormatter.string(cleanup.selectedBytes))",
                    symbol: "sparkles",
                    disabled: cleanup.selectedItems.isEmpty
                ) { confirming = true }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Theme.panel)
        }
    }

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                if cleanup.phase == .cleaning {
                    ProgressView().controlSize(.small)
                    Text("Đang xử lý — \(cleanup.itemsProcessed)/\(cleanup.selectedItems.count) mục")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textPrimary)
                } else {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(Theme.good)
                    Text("Hoàn tất")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                }
                Spacer()
                Text(ByteFormatter.string(cleanup.bytesFreed))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.ramLight)
                    .monospacedDigit()
            }

            ProgressView(
                value: Double(cleanup.itemsProcessed),
                total: Double(max(cleanup.selectedItems.count, 1))
            )
            .tint(Theme.accent)

            LogView(lines: cleanup.log)

            HStack {
                Text(cleanup.moveToTrash
                     ? "Các mục nằm trong Thùng rác — dọn Thùng rác để lấy lại dung lượng."
                     : "Đã xóa vĩnh viễn.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                Spacer()
                Button("Sao chép log") { cleanup.copyLog() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))

                if cleanup.phase == .cleaning {
                    Button("Dừng") { cleanup.requestCancel() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dangerLight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.dangerDeep))
                } else {
                    AccentButton(title: "Quét lại", symbol: "arrow.clockwise") { cleanup.scan() }
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 20)
    }
}

/// Live activity log. Auto-scrolls to the newest line so the view keeps pace
/// with a run without the pointer having to chase it.
struct LogView: View {
    let lines: [LogLine]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(lines) { line in
                        HStack(alignment: .top, spacing: 7) {
                            Text(line.timeText)
                                .foregroundStyle(Theme.textMuted)
                            Text(symbol(line.level))
                                .foregroundStyle(color(line.level))
                            Text(line.message)
                                .foregroundStyle(Theme.textPrimary)
                            if let detail = line.detail {
                                Text("· \(detail)")
                                    .foregroundStyle(Theme.textMuted)
                            }
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 10.5, design: .monospaced))
                        .id(line.id)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35)))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.hairline, lineWidth: 0.5))
            .onChange(of: lines.count) {
                if let last = lines.last {
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func symbol(_ level: LogLine.Level) -> String {
        switch level {
        case .removed: return "✓"
        case .skipped: return "⚠"
        case .working: return "→"
        case .failed: return "✕"
        case .done: return "◆"
        }
    }

    private func color(_ level: LogLine.Level) -> Color {
        switch level {
        case .removed: return Theme.ramLight
        case .skipped: return Theme.heatLight
        case .working: return Theme.cpuLight
        case .failed: return Theme.dangerLight
        case .done: return Theme.good
        }
    }
}

struct TriStateCheckbox: View {
    let checked: Bool
    let partial: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 3)
                .fill(checked ? Theme.accent : Theme.card)
                .frame(width: 14, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(checked ? Theme.accent : Theme.border, lineWidth: 1)
                )
                .overlay {
                    if partial {
                        Rectangle()
                            .fill(Theme.textPrimary)
                            .frame(width: 7, height: 1.5)
                    } else if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

struct AccentButton: View {
    let title: String
    let symbol: String
    var disabled: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 11))
                Text(title).font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(disabled ? Theme.textMuted : Color.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(disabled ? Theme.card : (hovering ? Theme.cpu : Theme.accent))
            )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .onHover { hovering = $0 }
    }
}
