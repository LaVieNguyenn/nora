import SwiftUI

struct SettingsTab: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var stream: StatusStream
    @EnvironmentObject var batteries: DeviceBatteryService
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        TabScaffold(title: "Cài đặt") {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Card(title: "Thanh menubar") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Chỉ số hiển thị", selection: $settings.menubarMetric) {
                                ForEach(MenubarMetric.allCases) { metric in
                                    Text(metric.label).tag(metric)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .frame(maxWidth: 240, alignment: .leading)

                            Toggle("Hiện cả con số bên cạnh chấm màu", isOn: $settings.showValueInMenubar)
                                .toggleStyle(.checkbox)

                            HStack(spacing: 10) {
                                Text("Nhịp cập nhật")
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                                Stepper(
                                    "\(settings.refreshSeconds) giây",
                                    value: $settings.refreshSeconds,
                                    in: 1...10
                                )
                                .font(.system(size: 11))
                            }
                            Text("Nhịp thưa hơn thì tốn ít pin hơn. Đổi xong sẽ khởi động lại luồng thu thập.")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.textMuted)

                            Button("Áp dụng nhịp mới") {
                                stream.stop()
                                stream.start(interval: settings.refreshInterval)
                            }
                            .font(.system(size: 11))
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textPrimary)
                    }

                    Card(title: "Khởi động") {
                        Toggle("Chạy Nora khi đăng nhập", isOn: $launchAtLogin)
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textPrimary)
                            .onChange(of: launchAtLogin) { _, enabled in
                                LoginItem.set(enabled: enabled)
                            }
                    }

                    Card(title: "Thông báo") {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Báo khi thiết bị sắp hết pin (dưới 20%)", isOn: $settings.notifyLowBattery)
                                .toggleStyle(.checkbox)
                            Toggle("Báo khi ổ đĩa sắp đầy", isOn: $settings.notifyLowDisk)
                                .toggleStyle(.checkbox)
                            HStack(spacing: 10) {
                                Text("Ngưỡng cảnh báo ổ đĩa")
                                    .foregroundStyle(Theme.textSecondary)
                                Stepper(
                                    "\(settings.lowDiskThresholdGB) GB",
                                    value: $settings.lowDiskThresholdGB,
                                    in: 5...200,
                                    step: 5
                                )
                            }
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textPrimary)
                    }

                    Card(title: "Nguồn dữ liệu") {
                        VStack(alignment: .leading, spacing: 8) {
                            row("Bản cài Nora", NoraLocator.repoRoot?.path ?? "chưa tìm thấy")
                            row("Bộ thu thập", NoraLocator.statusBinary?.lastPathComponent ?? "thiếu")
                            row(
                                "Công cụ iPhone",
                                batteries.iPhoneAvailable
                                    ? "libimobiledevice đã cài"
                                    : "chưa cài — chạy: brew install libimobiledevice"
                            )

                            HStack(spacing: 8) {
                                TextField("Đường dẫn Nora tuỳ chọn", text: $settings.noraRepoPath)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 11))
                                Text("cần mở lại app")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.textMuted)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 26)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
            Spacer()
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
