import AppKit
import SwiftUI

struct AddRouteRuleView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @Environment(\.dismiss) private var dismiss

    let preferredInterfaceID: String?
    let onClose: (() -> Void)?

    @State private var destinationsText: String = ""
    @State private var selectedInterfaceIndex: Int = 0
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var isSubmitting = false

    private var validInterfaces: [NetworkInterface] {
        viewModel.validTargetInterfaces
    }

    private var selectedInterface: NetworkInterface? {
        guard !validInterfaces.isEmpty, selectedInterfaceIndex < validInterfaces.count else { return nil }
        return validInterfaces[selectedInterfaceIndex]
    }

    private var parsedDestinations: ParsedDestinations {
        Self.parseDestinations(destinationsText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("common.add_routes"))
                .font(.headline)

            // Destination
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.tr("add.destinations_title"))
                    .font(.subheadline)
                Text(L10n.tr("add.destinations_detail"))
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextEditor(text: $destinationsText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 180)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )

                HStack(spacing: 12) {
                    summaryPill(title: L10n.validCount(parsedDestinations.valid.count), color: .green)
                    if !parsedDestinations.invalid.isEmpty {
                        summaryPill(title: L10n.invalidCount(parsedDestinations.invalid.count), color: .red)
                    }
                }

                if !parsedDestinations.invalid.isEmpty {
                    Text(L10n.fmt("add.invalid_entries", parsedDestinations.invalid.joined(separator: ", ")))
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            // Interface selector
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("add.interface_title"))
                    .font(.subheadline)

                if validInterfaces.isEmpty {
                    Text(L10n.tr("add.no_valid_interfaces"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Picker(L10n.tr("add.interface_picker"), selection: $selectedInterfaceIndex) {
                        ForEach(Array(validInterfaces.enumerated()), id: \.offset) { index, iface in
                            HStack {
                                Text("\(iface.hardwarePort) (\(iface.deviceName))")
                                if let ip = iface.ipAddress {
                                    Text("- \(ip)")
                                }
                            }
                            .tag(index)
                        }
                    }
                }
            }

            if let iface = selectedInterface {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("add.selected_interface"))
                        .font(.subheadline)
                    Text("\(iface.hardwarePort) (\(iface.deviceName)) \(L10n.fmt("common.via", iface.gateway ?? L10n.tr("common.unavailable")))")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .cornerRadius(6)
                }
            }

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            if let resultMessage {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Buttons
            HStack {
                Spacer()
                Button(L10n.tr("common.cancel")) {
                    closeView()
                }
                .keyboardShortcut(.cancelAction)

                Button(isSubmitting ? L10n.tr("common.adding") : L10n.tr("common.add_routes")) {
                    Task {
                        await addRules()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(parsedDestinations.valid.isEmpty || selectedInterface == nil || isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 560)
        .onAppear {
            syncPreferredInterface()
        }
    }

    private static func isValidIP(_ value: String) -> Bool {
        let parts = value.split(separator: ".")
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard UInt8(part) != nil else { return false }
            return true
        }
    }

    private static func isValidCIDR(_ value: String) -> Bool {
        let parts = value.split(separator: "/")
        guard parts.count == 2 else { return false }
        guard let prefix = UInt8(parts[1]), prefix <= 32 else { return false }
        return isValidIP(String(parts[0]))
    }

    private static func parseDestinations(_ input: String) -> ParsedDestinations {
        let rawTokens = input
            .components(separatedBy: CharacterSet(charactersIn: ",;\n\t "))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var valid: [String] = []
        var invalid: [String] = []
        var seen = Set<String>()

        for token in rawTokens {
            guard seen.insert(token).inserted else { continue }
            if isValidIP(token) || isValidCIDR(token) {
                valid.append(token)
            } else {
                invalid.append(token)
            }
        }

        return ParsedDestinations(valid: valid, invalid: invalid)
    }

    private func syncPreferredInterface() {
        guard let preferredInterfaceID else { return }
        guard let index = validInterfaces.firstIndex(where: { $0.id == preferredInterfaceID }) else { return }
        selectedInterfaceIndex = index
    }

    private func addRules() async {
        guard let iface = selectedInterface else { return }

        isSubmitting = true
        errorMessage = nil
        resultMessage = nil

        let result = await viewModel.addRules(destinations: parsedDestinations.valid, to: iface)

        isSubmitting = false

        if !result.failed.isEmpty {
            errorMessage = result.failed.map { failure in
                failure.destination.isEmpty ? failure.reason : "\(failure.destination): \(failure.reason)"
            }.joined(separator: "\n")
        }

        var messages: [String] = []
        if result.activatedApp {
            messages.append(L10n.tr("add.inactive_activated"))
        }
        if !result.added.isEmpty {
            messages.append(L10n.addedRoutes(result.added.count))
        }
        if !result.imported.isEmpty {
            messages.append(L10n.importedRoutes(result.imported.count))
        }
        if !result.alreadySaved.isEmpty {
            messages.append(L10n.destinationsAlreadySaved(result.alreadySaved.count))
        }
        resultMessage = messages.isEmpty ? nil : messages.joined(separator: " ")

        let remaining = result.alreadySaved + result.failed.map(\.destination).filter { !$0.isEmpty } + parsedDestinations.invalid
        destinationsText = remaining.joined(separator: "\n")

        if result.failed.isEmpty && result.alreadySaved.isEmpty && parsedDestinations.invalid.isEmpty {
            closeView()
        }
    }

    private func closeView() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    private func summaryPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct ParsedDestinations {
    let valid: [String]
    let invalid: [String]
}
