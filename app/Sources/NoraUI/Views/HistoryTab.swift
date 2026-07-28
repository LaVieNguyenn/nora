import SwiftUI

/// One entry of `mo history --json`.
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
    let actions: Actions?

    var id: String { command + startedAt }

    enum CodingKeys: String, CodingKey {
        case command, items, size, actions
        case startedAt = "started_at"
        case endedAt = "ended_at"
    }
}

struct HistoryResponse: Decodable {
    let sessions: [HistorySession]?
    let logs: [String: String]?
}

final class HistoryService: ObservableObject {
    @Published private(set) var sessions: [HistorySession] = []
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
                self.sessions = decoded.sessions ?? []
                self.logPaths = decoded.logs ?? [:]
            }
        }
    }
}

struct HistoryTab: View {
    @StateObject private var service = HistoryService()

    var body: some View {
        TabScaffold(title: "Lịch sử", subtitle: "Các phiên chạy gần đây của Nora") {
            VStack(alignment: .leading, spacing: 10) {
                if service.isLoading {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Đang đọc nhật ký…")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                } else if service.sessions.isEmpty {
                    Text("Chưa có phiên nào được ghi lại.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                }

                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(service.sessions) { session in
                            sessionRow(session)
                        }
                    }
                }

                if let operations = service.logPaths["operations"] {
                    HStack(spacing: 6) {
                        Text("Nhật ký đầy đủ:")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textMuted)
                        Text(operations)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textSecondary)
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
            Circle()
                .fill(color(for: session.command))
                .frame(width: 8, height: 8)

            Text(label(for: session.command))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 110, alignment: .leading)

            Text(session.startedAt)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textMuted)

            Spacer()

            if let actions = session.actions {
                HStack(spacing: 10) {
                    counter("đã xóa", actions.removed, Theme.ramLight)
                    counter("vào thùng rác", actions.trashed, Theme.diskLight)
                    counter("bỏ qua", actions.skipped, Theme.heatLight)
                    counter("lỗi", actions.failed, Theme.dangerLight)
                }
            }

            Text(session.size ?? "—")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(width: 66, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
    }

    @ViewBuilder
    private func counter(_ label: String, _ value: Int?, _ tint: Color) -> some View {
        if let value, value > 0 {
            Text("\(value) \(label)")
                .font(.system(size: 10))
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

    private func color(for command: String) -> Color {
        switch command {
        case "clean": return Theme.cpu
        case "uninstall": return Theme.net
        case "optimize": return Theme.ram
        default: return Theme.textMuted
        }
    }
}
