import SwiftUI

/// One entry of `nora history --json`.
struct HistorySession: Decodable, Identifiable {
    struct Actions: Decodable {
        let removed: Int?
        let trashed: Int?
        let skipped: Int?
        let failed: Int?
    }

    let command: String
    let startedAt: String
    let endedAt: String?
    let items: Int?
    let size: String?
    let operationCount: Int?
    let actions: Actions?

    var id: String { command + startedAt }

    enum CodingKeys: String, CodingKey {
        case command, items, size, actions
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case operationCount = "operation_count"
    }
}

struct HistoryResponse: Decodable {
    let sessions: [HistorySession]?
    let logs: [String: String]?
}

final class HistoryService: ObservableObject {
    @Published private(set) var sessions: [HistorySession] = []
    @Published private(set) var hiddenCount = 0
    @Published private(set) var isLoading = false
    @Published private(set) var logPaths: [String: String] = [:]

    func load() {
        guard let entrypoint = NoraLocator.entrypoint else { return }
        isLoading = true

        Task { [weak self] in
            let output = await ProcessRunner.run(
                entrypoint, arguments: ["history", "--json", "--limit", "60"], timeout: 30)

            DispatchQueue.main.async {
                guard let self else { return }
                self.isLoading = false
                guard let start = output.stdout.firstIndex(of: "{"),
                      let data = String(output.stdout[start...]).data(using: .utf8),
                      let decoded = try? JSONDecoder().decode(HistoryResponse.self, from: data)
                else { return }
                // Every CLI invocation logs a session, including `uninstall
                // --list`, which the app itself runs each time the tab opens.
                // Those zero-operation rows outnumbered the real ones twelve to
                // four on a live machine and buried them.
                let all = decoded.sessions ?? []
                self.sessions = all.filter { ($0.operationCount ?? 0) > 0 || ($0.items ?? 0) > 0 }
                self.hiddenCount = all.count - self.sessions.count
                self.logPaths = decoded.logs ?? [:]
            }
        }
    }
}

struct HistoryTab: View {
    @StateObject private var service = HistoryService()

    var body: some View {
        Page(title: "Lịch sử", subtitle: "Các phiên chạy gần đây của Nora") {
            Button {
                service.load()
            } label: {
                Label("Tải lại", systemImage: "arrow.clockwise")
            }
            .disabled(service.isLoading)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if service.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Đang đọc nhật ký…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                } else if service.sessions.isEmpty {
                    Text("Chưa có phiên nào thực sự thay đổi gì.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(service.sessions) { session in
                            sessionRow(session)
                        }
                    }
                }

                if service.hiddenCount > 0 {
                    Text("Đã ẩn \(service.hiddenCount) phiên không thao tác gì (mở app, liệt kê…).")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                if let operations = service.logPaths["operations"] {
                    HStack(spacing: 6) {
                        Text("Nhật ký đầy đủ:")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(operations)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .onAppear { service.load() }
    }

    private func sessionRow(_ session: HistorySession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol(for: session.command))
                .font(.callout)
                .foregroundStyle(tint(for: session.command))
                .frame(width: 18)

            Text(label(for: session.command))
                .font(.callout)
                .frame(width: 104, alignment: .leading)

            Text(session.startedAt)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)

            Spacer()

            if let actions = session.actions {
                HStack(spacing: 10) {
                    counter("đã xóa", actions.removed, Theme.success)
                    counter("vào thùng rác", actions.trashed, Metric.disk.tint)
                    counter("bỏ qua", actions.skipped, Theme.warning)
                    counter("lỗi", actions.failed, Theme.danger)
                }
            }

            Text(session.size ?? "—")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 68, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func counter(_ label: String, _ value: Int?, _ tint: Color) -> some View {
        if let value, value > 0 {
            Text("\(value) \(label)")
                .font(.caption)
                .foregroundStyle(tint)
        }
    }

    private func label(for command: String) -> String {
        switch command {
        case "clean": return "Dọn dẹp"
        case "uninstall": return "Gỡ app"
        case "optimize": return "Tối ưu"
        case "purge": return "Xoá sâu"
        default: return command
        }
    }

    private func symbol(for command: String) -> String {
        switch command {
        case "clean": return "sparkles"
        case "uninstall": return "trash"
        case "optimize": return "slider.horizontal.3"
        case "purge": return "flame"
        default: return "circle"
        }
    }

    private func tint(for command: String) -> Color {
        switch command {
        case "clean": return Metric.cpu.tint
        case "uninstall": return Metric.network.tint
        case "optimize": return Metric.memory.tint
        default: return Theme.tertiaryLabel
        }
    }
}
