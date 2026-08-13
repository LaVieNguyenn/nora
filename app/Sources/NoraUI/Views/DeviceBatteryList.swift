import SwiftUI

/// The "pin thiết bị" block in the popover and on the overview.
struct DeviceBatteryList: View {
    let devices: [DeviceBattery]
    var phoneStatus: PhoneStatus = .noDeviceReachable

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: "Pin thiết bị")
                .padding(.bottom, 6)

            if devices.isEmpty {
                Text("Chưa có thiết bị nào đang báo pin")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(devices) { device in
                    DeviceBatteryRow(device: device)
                }
            }

            // Say why the iPhone row is missing rather than leaving a gap the
            // user has to guess at.
            if let hint = phoneStatus.hint {
                Label {
                    Text(hint)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "iphone.slash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 6)
            }
        }
    }
}

struct DeviceBatteryRow: View {
    let device: DeviceBattery

    private var level: Int? { device.effectivePercent }
    private var tint: Color {
        device.isConnected ? Theme.batteryTint(level) : Theme.tertiaryLabel
    }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: device.kind.symbol)
                .font(.callout)
                .foregroundStyle(tint)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.callout)
                    .foregroundStyle(device.isConnected ? Theme.label : Theme.secondaryLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail = device.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(device.isLow && device.isConnected ? tint : Theme.tertiaryLabel)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let level {
                Meter(value: Double(level) / 100, tint: tint, width: 46)

                Text("\(level)%")
                    .font(.callout)
                    .fontWeight(device.isLow ? .medium : .regular)
                    .foregroundStyle(tint)
                    .frame(width: 34, alignment: .trailing)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .opacity(device.isConnected ? 1 : 0.6)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(device.name): \(level.map { "\($0)%" } ?? "không rõ")")
    }
}
