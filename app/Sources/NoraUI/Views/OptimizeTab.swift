import SwiftUI

struct OptimizeTab: View {
    @StateObject private var service = OptimizeService()
    @State private var confirming = false

    var body: some View {
        TabScaffold(title: "Tối ưu", subtitle: subtitle) {
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
            VStack(alignment: .leading, spacing: 10) {
                Text("""
                Tối ưu không làm máy nhanh hơn một cách kỳ diệu — nó sửa những thứ \
                hỏng vặt và nén những thứ phình to.
                """)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 2)

                ForEach(OptimizeTask.grouped, id: \.0) { group, tasks in
                    Card(title: group.label, trailing: "\(tasks.count) tác vụ") {
                        VStack(spacing: 0) {
                            ForEach(tasks) { task in
                                taskRow(task, symbol: group.symbol)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 14)
        }
    }

    private func taskRow(_ task: OptimizeTask, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(Theme.cpu)
                .frame(width: 16)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(task.name)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.textPrimary)
                    if task.needsAdmin {
                        Text("cần quyền admin")
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.heatLight)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Theme.heatDeep))
                    }
                }
                Text(task.detail)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
    }

    private var runningView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                if service.isBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "checkmark.circle").foregroundStyle(Theme.good)
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            LogView(lines: service.log)
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 12)
    }

    private var actionBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Theme.hairline)
            HStack(spacing: 10) {
                Text(service.phase == .idle
                     ? "Xem trước chạy `nora optimize --dry-run`, không thay đổi gì."
                     : "Nhật ký được lưu vào lịch sử của Nora.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)

                Spacer()

                if service.isBusy {
                    Button("Dừng") { service.cancel() }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.dangerLight)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.dangerDeep))
                } else {
                    Button("Xem trước") { service.run(dryRun: true) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))

                    AccentButton(title: "Chạy tối ưu", symbol: "slider.horizontal.3") {
                        confirming = true
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
            .background(Theme.panel)
        }
    }
}
