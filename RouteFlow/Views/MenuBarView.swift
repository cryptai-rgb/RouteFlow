import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MenuBarView: View {
    @EnvironmentObject var viewModel: MenuBarViewModel
    @State private var exportFeedback: String?
    @State private var exportError: String?

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                headerSection

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        interfaceAndDetailSection
                        routeRuleSection
                    }
                    .padding(.vertical, 12)
                }
                
                Divider()

                footerSection
            }
            .frame(width: 680, height: 520)
            .disabled(viewModel.isShowingAddRouteSheet)

            if viewModel.isShowingAddRouteSheet {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()

                AddRouteRuleView(
                    preferredInterfaceID: viewModel.selectedInterfaceID,
                    onClose: { viewModel.isShowingAddRouteSheet = false }
                )
                .environmentObject(viewModel)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 24, y: 12)
                .padding(24)
            }
        }
        .onAppear {
            viewModel.handleMenuPresented()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Text("RouteFlow")
                .font(.headline)
            Spacer()
            Toggle("", isOn: Binding(
                get: { viewModel.isGloballyActive },
                set: { _ in viewModel.toggleGlobalActive() }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .disabled(viewModel.isGlobalToggleInFlight)
            Text(viewModel.isGloballyActive ? L10n.tr("common.active") : L10n.tr("common.inactive"))
                .font(.caption)
                .foregroundColor(viewModel.isGloballyActive ? .green : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Main Content

    private var interfaceAndDetailSection: some View {
        HStack(alignment: .top, spacing: 16) {
            interfaceSection
                .frame(width: 290, alignment: .topLeading)

            detailSection
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 12)
    }

    private var interfaceSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(L10n.tr("menu.interfaces"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { viewModel.refreshInterfaces() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            ForEach(viewModel.interfaces) { iface in
                InterfaceRow(
                    interface: iface,
                    isSelected: viewModel.selectedInterfaceID == iface.id,
                    routeCount: viewModel.manualRoutesForInterface(iface).count,
                    onTap: {
                        viewModel.selectedInterfaceID = viewModel.selectedInterfaceID == iface.id ? nil : iface.id
                    }
                )
            }
            .padding(.horizontal, 12)

            if viewModel.interfaces.isEmpty {
                Text(L10n.tr("menu.no_interfaces"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
        }
        .padding(.bottom, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.tr("menu.selected_routes"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                if let interface = viewModel.selectedInterface {
                    Button {
                        exportRoutes(for: interface)
                    } label: {
                        Label(L10n.tr("menu.export_routes"), systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.exportableNetworkRoutes(for: interface).isEmpty)

                    Text(interface.hardwarePort)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let interface = viewModel.selectedInterface {
                interfaceDetailCard(for: interface)
            } else {
                emptySelectionView
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func interfaceDetailCard(for interface: NetworkInterface) -> some View {
        let routes = viewModel.manualRoutesForInterface(interface)
        let exportableRoutes = viewModel.exportableNetworkRoutes(for: interface)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(interface.hardwarePort) (\(interface.deviceName))")
                    .font(.headline)

                HStack(spacing: 8) {
                    statusPill(
                        title: interface.isActive ? L10n.tr("common.online") : L10n.tr("common.offline"),
                        color: interface.isActive ? .green : .secondary
                    )
                    if interface.isValidRouteTarget {
                        statusPill(title: L10n.tr("common.route_target"), color: .blue)
                    }
                    if interface.serviceOrder == 1 && interface.isActive {
                        statusPill(title: L10n.tr("common.default_service"), color: .orange)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                infoRow(label: L10n.tr("common.ipv4"), value: interface.ipAddress ?? L10n.tr("common.unavailable"))
                infoRow(label: L10n.tr("common.gateway"), value: interface.gateway ?? L10n.tr("common.unavailable"))
                infoRow(label: L10n.tr("common.subnet"), value: interface.subnetMask ?? L10n.tr("common.unavailable"))
                infoRow(label: "UGS", value: L10n.routeCount(routes.count))
                infoRow(label: "Export", value: L10n.networkRouteCount(exportableRoutes.count))
            }

            Divider()

            if let exportError {
                Text(exportError)
                    .font(.caption)
                    .foregroundColor(.red)
            } else if let exportFeedback {
                Text(exportFeedback)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if routes.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.tr("menu.routes_empty_title"))
                        .font(.callout)
                    Text(L10n.tr("menu.routes_empty_detail"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.fmt("menu.routes_showing", interface.deviceName))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if exportableRoutes.isEmpty {
                        Text(L10n.tr("menu.routes_export_note"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    ForEach(routes) { route in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(route.destination)
                                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                Spacer()
                                if viewModel.isManagedRoute(route) {
                                    Button(role: .destructive) {
                                        Task {
                                            await viewModel.removeManagedRoute(route)
                                        }
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                }
                                statusPill(
                                    title: route.routeKindTitle,
                                    color: .accentColor
                                )
                                statusPill(title: route.flags, color: .green)
                            }

                            HStack(spacing: 12) {
                                Text(L10n.fmt("common.via", route.gateway))
                                Text(L10n.fmt("common.netif", route.interfaceName))
                                if let expire = route.expire, expire != "-" {
                                    Text(L10n.fmt("common.expire", expire))
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)

                            Text(viewModel.isManagedRoute(route) ? L10n.tr("menu.route_saved") : L10n.tr("menu.route_unmanaged"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }

    private var emptySelectionView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.tr("menu.empty_selection_title"))
                .font(.callout)
            Text(L10n.tr("menu.empty_selection_detail"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 12, design: .monospaced))
        }
    }

    private func exportRoutes(for interface: NetworkInterface) {
        let destinations = viewModel.exportableNetworkRoutes(for: interface).map(\.destination)
        guard !destinations.isEmpty else {
            exportFeedback = nil
            exportError = L10n.fmt("menu.export_none", interface.deviceName)
            return
        }

        let savePanel = NSSavePanel()
        savePanel.title = L10n.tr("menu.export_title")
        savePanel.message = L10n.fmt("menu.export_message", interface.hardwarePort, interface.deviceName)
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = L10n.fmt("menu.export_filename", interface.deviceName)
        savePanel.allowedContentTypes = [.plainText]

        NSApplication.shared.activate(ignoringOtherApps: true)

        guard savePanel.runModal() == .OK, let url = savePanel.url else {
            return
        }

        do {
            let content = destinations.joined(separator: "\n") + "\n"
            try content.write(to: url, atomically: true, encoding: .utf8)
            exportError = nil
            if L10n.isChinese {
                exportFeedback = L10n.fmt("menu.export_success", destinations.count, url.lastPathComponent)
            } else {
                exportFeedback = L10n.fmt(
                    "menu.export_success",
                    destinations.count,
                    destinations.count == 1 ? "" : "s",
                    url.lastPathComponent
                )
            }
        } catch {
            exportFeedback = nil
            exportError = L10n.fmt("menu.export_failed", error.localizedDescription)
        }
    }

    // MARK: - Route Rules

    private var routeRuleSection: some View {
        RouteRuleListView()
            .environmentObject(viewModel)
            .padding(.horizontal, 12)
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Spacer()

            Button(L10n.tr("common.quit")) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.subheadline)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
