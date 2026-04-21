import SwiftUI

struct InterfaceRow: View {
    let interface: NetworkInterface
    let isSelected: Bool
    let routeCount: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Circle()
                    .fill(interface.isActive ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(interface.hardwarePort)
                            .font(.system(size: 12, weight: .medium))
                        Text(interface.deviceName)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.secondary)
                        if interface.serviceOrder == 1 && interface.isActive {
                            Text(L10n.tr("common.default"))
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.blue)
                                .cornerRadius(3)
                        }
                    }

                    HStack(spacing: 6) {
                        Text(interface.ipAddress ?? L10n.tr("interface.no_ipv4"))
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        if let gateway = interface.gateway {
                            Text(L10n.fmt("common.via", gateway))
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer(minLength: 8)

                if routeCount > 0 {
                    Text("\(routeCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor)
                        .cornerRadius(8)
                }

                Image(systemName: isSelected ? "sidebar.right" : "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? .accentColor : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor.opacity(0.35) : Color.secondary.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
