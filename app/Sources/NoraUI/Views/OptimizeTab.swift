import SwiftUI

struct OptimizeTab: View {
    @StateObject private var service = OptimizeService()
    @State private var confirming = false

    var body: some View {
        Page(title: "Tối ưu", subtitle: subtitle) {
            VStack(spacing: 0) {
                if service.log.isEmpty {
                    taskList
                } else {
                    runningView
                }
                actionBar
            }
        }
        .alert("Chạy tối ưu?", isPresented: $confirming) {
            Button("Huỷ", role: .cancel) {}
            Button("Chạy") { service.run(dryRun: false) }
        } message: {
            Text("""
            Nora sẽ chạy \(OptimizeTask.all.count) tác vụ bảo trì. Các tác vụ cần \
            quyền quản trị sẽ tự bỏ qua nếu không cấp được quyền.
            """)
        }
    }

    private var subtitle: String {
        switch service.phase {
        case .idle: return "\(OptimizeTask.all.count) tác vụ bảo trì — sửa lỗi vặt và nén dữ liệu phình to"
        case .previewing: return "Đang xem trước — chưa thay đổi gì"
        case .running: return "Đang chạy"
        case .finished: return "Đã xong"
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                Text("""
                Tối ưu không làm máy nhanh hơn một cách kỳ diệu — nó sửa những thứ \
                hỏng vặt và nén những thứ phình to.
                """)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                ForEach(OptimizeTask.grouped, id: \.0) { group, tasks in
                    SectionCard(
                        title: group.label,
                        subtitle: "\(tasks.count) tác vụ",
                        systemImage: group.symbol
                    ) {
                        VStack(spacing: 0) {
                            ForEach(tasks) { task in
                                taskRow(task)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
        }
    }

    private func taskRow(_ task: OptimizeTask) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(task.name)
                    .font(.callout)
                if task.needsAdmin {
                    Text("cần quyền admin")
                        .font(.caption2)
                        .foregroundStyle(Theme.warning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Theme.warning.opacity(0.15), in: Capsule())
                }
                Spacer(minLength: 0)
            }
            Text(task.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if service.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                }
                Text(subtitle).font(.callout)
                Spacer()
            }
            LogPane(lines: service.log)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    private var actionBar: some View {
        ActionBar {
            Text(service.phase == .idle
                 ? "Xem trước chạy `nora optimize --dry-run`, không thay đổi gì."
                 : "Nhật ký được lưu vào lịch sử của Nora.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if service.isBusy {
                Button("Dừng", role: .destructive) { service.cancel() }
            } else {
                if !service.log.isEmpty {
                    Button("Xoá nhật ký") { service.clearLog() }
                }
                Button("Xem trước") { service.run(dryRun: true) }
                Button {
                    confirming = true
                } label: {
                    Label("Chạy tối ưu", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
