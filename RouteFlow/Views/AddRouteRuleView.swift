import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AddRouteRuleView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @Environment(\.dismiss) private var dismiss

    let preferredInterfaceID: String?
    let onClose: (() -> Void)?

    @State private var destinationsText: String = ""
    @State private var selectedInterfaceID: String?
    @State private var errorMessage: String?
    @State private var resultMessage: String?
    @State private var isSubmitting = false
    @State private var importedFileURL: URL?

    private var validInterfaces: [NetworkInterface] {
        viewModel.validTargetInterfaces
    }

    private var selectedInterface: NetworkInterface? {
        AddRouteInterfaceSelection.selectedInterface(
            from: validInterfaces,
            selectedInterfaceID: selectedInterfaceID
        )
    }

    private var parsedDestinations: ParsedDestinations {
        RouteDestinationParser.parse(destinationsText)
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

                HStack {
                    Spacer()
                    Button(L10n.tr("add.import_file")) {
                        importDestinationsFromFile()
                    }
                }

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

                if let importedFileURL {
                    Text(L10n.fmt("add.imported_file", importedFileURL.lastPathComponent))
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                    Picker(L10n.tr("add.interface_picker"), selection: Binding(
                        get: { selectedInterfaceID ?? "" },
                        set: { selectedInterfaceID = $0.isEmpty ? nil : $0 }
                    )) {
                        ForEach(validInterfaces) { iface in
                            HStack {
                                Text("\(iface.hardwarePort) (\(iface.deviceName))")
                                if let ip = iface.ipAddress {
                                    Text("- \(ip)")
                                }
                            }
                            .tag(iface.id)
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
        .onChange(of: validInterfaces) { newInterfaces in
            selectedInterfaceID = AddRouteInterfaceSelection.reconciledSelectionID(
                from: newInterfaces,
                preferredInterfaceID: preferredInterfaceID,
                currentSelectionID: selectedInterfaceID
            )
        }
    }

    private func syncPreferredInterface() {
        selectedInterfaceID = AddRouteInterfaceSelection.reconciledSelectionID(
            from: validInterfaces,
            preferredInterfaceID: preferredInterfaceID,
            currentSelectionID: selectedInterfaceID
        )
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

    private func importDestinationsFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text]

        // MenuBarExtra windows can stay non-key while a custom overlay is shown,
        // so bring the app forward before starting a modal open panel.
        NSApplication.shared.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            let parsed = RouteDestinationParser.parse(content)
            guard !parsed.valid.isEmpty else {
                errorMessage = L10n.tr("add.import_no_valid_routes")
                return
            }

            let existing = RouteDestinationParser.parse(destinationsText)
            let merged = existing.valid + parsed.valid
            let deduplicated = Array(NSOrderedSet(array: merged)) as? [String] ?? merged
            destinationsText = deduplicated.joined(separator: "\n")
            importedFileURL = url
            resultMessage = L10n.fmt("add.import_success", parsed.valid.count)
            errorMessage = parsed.invalid.isEmpty
                ? nil
                : L10n.fmt("add.import_invalid_entries", parsed.invalid.joined(separator: ", "))
        } catch {
            errorMessage = L10n.fmt("add.import_failed", error.localizedDescription)
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

struct ParsedDestinations {
    let valid: [String]
    let invalid: [String]
}

enum AddRouteInterfaceSelection {
    static func selectedInterface(
        from validInterfaces: [NetworkInterface],
        selectedInterfaceID: String?
    ) -> NetworkInterface? {
        guard let selectedInterfaceID else { return nil }
        return validInterfaces.first(where: { $0.id == selectedInterfaceID })
    }

    static func reconciledSelectionID(
        from validInterfaces: [NetworkInterface],
        preferredInterfaceID: String?,
        currentSelectionID: String?
    ) -> String? {
        guard !validInterfaces.isEmpty else { return nil }

        if let currentSelectionID,
           validInterfaces.contains(where: { $0.id == currentSelectionID }) {
            return currentSelectionID
        }

        if let preferredInterfaceID,
           validInterfaces.contains(where: { $0.id == preferredInterfaceID }) {
            return preferredInterfaceID
        }

        return validInterfaces.first?.id
    }
}

enum RouteDestinationParser {
    static func parse(_ input: String) -> ParsedDestinations {
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

    static func isValidIP(_ value: String) -> Bool {
        isValidIPv4(value, allowCompressedTrailingZeros: false)
    }

    static func isValidCIDR(_ value: String) -> Bool {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        guard let prefix = UInt8(parts[1]), prefix <= 32 else { return false }
        return isValidIPv4(String(parts[0]), allowCompressedTrailingZeros: true)
    }

    private static func isValidIPv4(_ value: String, allowCompressedTrailingZeros: Bool) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        let expectedCount = allowCompressedTrailingZeros ? 1...4 : 4...4
        guard expectedCount.contains(parts.count) else { return false }
        return parts.allSatisfy { UInt8($0) != nil }
    }
}
