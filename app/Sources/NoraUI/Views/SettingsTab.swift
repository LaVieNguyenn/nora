import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var stream: StatusStream
    @EnvironmentObject var batteries: DeviceBatteryService
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        Page(title: "Cài đặt") {
            ScrollView {
                // `Form` in its grouped style is what System Settings itself
                // uses: labels align on their own column, controls get the
                // system's spacing, and none of it has to be hand-tuned.
                Form {
                    Section("Thanh menubar") {
                        Picker("Chỉ số hiển thị", selection: $settings.menubarMetric) {
                            ForEach(MenubarMetric.allCases) { metric in
                                Text(metric.label).tag(metric)
                            }
                        }

                        Toggle("Hiện cả con số bên cạnh chấm màu",
                               isOn: $settings.showValueInMenubar)

                        // Bound straight to the collector: an "Áp dụng" button
                        // for a one-number setting is a step the user has to
                        // remember, and forgetting it looked like the setting
                        // did nothing.
                        Stepper(value: $settings.refreshSeconds, in: 1...10) {
                            Text("Nhịp cập nhật: \(settings.refreshSeconds) giây")
                        }
                        .onChange(of: settings.refreshSeconds) {
                            stream.setInterval(settings.refreshInterval)
                        }

                        Text("Nhịp thưa hơn thì tốn ít pin hơn.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("Khởi động") {
                        Toggle("Chạy Nora khi đăng nhập", isOn: $launchAtLogin)
                            .onChange(of: launchAtLogin) { _, enabled in
                                LoginItem.set(enabled: enabled)
                            }
                    }

                    Section("Thông báo") {
                        if let reason = AppState.shared.notifications.notificationsUnavailable {
                            Text("Thông báo đang tắt: \(reason)")
                                .font(.caption)
                                .foregroundStyle(Theme.warning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Toggle("Báo khi thiết bị sắp hết pin (dưới 20%)",
                               isOn: $settings.notifyLowBattery)
                        Toggle("Báo khi ổ đĩa sắp đầy", isOn: $settings.notifyLowDisk)
                        Stepper(value: $settings.lowDiskThresholdGB, in: 5...200, step: 5) {
                            Text("Ngưỡng cảnh báo ổ đĩa: \(settings.lowDiskThresholdGB) GB")
                        }
                    }

                    Section("Nguồn dữ liệu") {
                        LabeledContent("Bản cài Nora") {
                            Text(NoraLocator.repoRoot?.path ?? "chưa tìm thấy")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        LabeledContent("Bộ thu thập") {
                            Text(NoraLocator.statusBinary?.lastPathComponent ?? "thiếu")
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        LabeledContent("Công cụ iPhone") {
                            Text(batteries.iPhoneAvailable
                                 ? "libimobiledevice đã cài"
                                 : "chưa cài — chạy: brew install libimobiledevice")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("Đường dẫn tuỳ chọn") {
                            VStack(alignment: .leading, spacing: 2) {
                                TextField("Đường dẫn Nora", text: $settings.noraRepoPath)
                                    .textFieldStyle(.roundedBorder)
                                Text("cần mở lại app")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .formStyle(.grouped)
            }
        }
    }
}

/// Login-item registration via a LaunchAgent plist.
///
/// `SMAppService` is the modern route but requires a signed, bundled helper;
/// a plain LaunchAgent works for a locally built app with no signing identity.
enum LoginItem {
    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/LaunchAgents/com.nora.ui.plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func set(enabled: Bool) {
        if enabled {
            guard let appPath = Bundle.main.bundleURL.path
                .removingPercentEncoding else { return }
            let executable = Bundle.main.executableURL?.path ?? appPath

            let plist: [String: Any] = [
                "Label": "com.nora.ui",
                "ProgramArguments": [executable],
                "RunAtLoad": true,
                // Come back after a crash, but respect a deliberate quit:
                // `SuccessfulExit = false` restarts only on abnormal exit, so
                // "Thoát" in the popover still means quit.
                "KeepAlive": ["SuccessfulExit": false],
            ]

            try? FileManager.default.createDirectory(
                at: plistURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try? PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0)
            try? data?.write(to: plistURL)
        } else {
            try? FileManager.default.removeItem(at: plistURL)
        }
    }
}
