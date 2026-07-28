import SwiftUI

/// The "pin thiết bị" block under the bubbles.
struct DeviceBatteryList: View {
    let devices: [DeviceBattery]
    var phoneStatus: PhoneStatus = .noDeviceReachable

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PIN THIẾT BỊ")
                .font(.system(size: 9, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 6)

            if devices.isEmpty {
                Text("Chưa có thiết bị nào đang báo pin")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .padding(.vertical, 6)
            } else {
                ForEach(devices) { device in
                    DeviceBatteryRow(device: device)
                }
            }

            // Say why the iPhone row is missing rather than leaving a gap the
            // user has to guess at.
            if let hint = phoneStatus.hint {
                HStack(spacing: 7) {
                    Image(systemName: "iphone.slash")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textMuted)
                    Text(hint)
                        .font(.system(size: 9.5))
                        .foregroundStyle(Theme.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
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
        device.isConnected ? Theme.batteryColor(level) : Theme.textMuted
    }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle()
                    .fill(device.isConnected ? Theme.batteryDeep(level) : Theme.card)
                    .overlay(Circle().strokeBorder(tint.opacity(0.7), lineWidth: 1))
                Image(systemName: device.kind.symbol)
                    .font(.system(size: 11))
                    .foregroundStyle(tint)
            }
            .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(device.name)
                    .font(.system(size: 11))
                    .foregroundStyle(device.isConnected ? Theme.textPrimary : Theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail = device.detail {
                    Text(detail)
                        .font(.system(size: 9))
                        .foregroundStyle(device.isLow && device.isConnected ? tint : Theme.textMuted)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let level {
                Capsule()
                    .fill(Theme.hairline)
                    .frame(width: 44, height: 5)
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(tint)
                            .frame(width: 44 * CGFloat(level) / 100, height: 5)
                    }

                Text("\(level)%")
                    .font(.system(size: 11, weight: device.isLow ? .medium : .regular))
                    .foregroundStyle(tint)
                    .frame(width: 32, alignment: .trailing)
                    .monospacedDigit()
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textMuted)
                    .frame(width: 32, alignment: .trailing)
            }
        }
        .padding(.vertical, 4)
        .opacity(device.isConnected ? 1 : 0.6)
    }
}
