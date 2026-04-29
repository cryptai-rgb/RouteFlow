import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        TabView {
            GeneralSettingsView()
                .environmentObject(viewModel)
                .tabItem {
                    Label(L10n.tr("settings.general"), systemImage: "gear")
                }

            RulesSettingsView()
                .environmentObject(viewModel)
                .tabItem {
                    Label(L10n.tr("settings.rules"), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                }

            AboutView()
                .tabItem {
                    Label(L10n.tr("settings.about"), systemImage: "info.circle")
                }
        }
        .frame(width: 450, height: 300)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    @State private var launchAtLogin = false

    private var startupAuthorizationSummary: String {
        if viewModel.autoApplyOnLaunch && launchAtLogin {
            return L10n.tr("settings.summary.login_and_apply")
        }

        if viewModel.autoApplyOnLaunch {
            return L10n.tr("settings.summary.apply_only")
        }

        if launchAtLogin {
            return L10n.tr("settings.summary.login_only")
        }

        return L10n.tr("settings.summary.default")
    }

    var body: some View {
        Form {
            Toggle(L10n.tr("settings.auto_apply"), isOn: Binding(
                get: { viewModel.autoApplyOnLaunch },
                set: { viewModel.autoApplyOnLaunch = $0 }
            ))

            Toggle(L10n.tr("settings.clean_on_exit"), isOn: Binding(
                get: { viewModel.cleanRoutesOnExit },
                set: { viewModel.cleanRoutesOnExit = $0 }
            ))

            Toggle(L10n.tr("settings.launch_at_login"), isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { newValue in
                    do {
                        if newValue {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = !newValue
                        print("Failed to update login item: \(error)")
                    }
                }

            Text(startupAuthorizationSummary)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Section {
                HStack {
                    Text(L10n.tr("common.config_file"))
                        .font(.caption)
                    Spacer()
                    Button(L10n.tr("common.reveal_in_finder")) {
                        let url = ConfigManager.shared.configDirectoryURL
                        NSWorkspace.shared.open(url)
                    }
                    .font(.caption)
                }

                HStack {
                    Button(L10n.tr("common.export_config")) {
                        exportConfig()
                    }
                    Button(L10n.tr("common.import_config")) {
                        importConfig()
                    }
                }
            }
        }
        .padding(20)
        .onAppear {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "RouteFlow-config.json"
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ConfigManager.shared.exportConfig(to: url)
        } catch {
            print("Export failed: \(error)")
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let config = try ConfigManager.shared.importConfig(from: url)
            viewModel.config = config
        } catch {
            print("Import failed: \(error)")
        }
    }
}

// MARK: - Rules Settings

struct RulesSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel

    var body: some View {
        List {
            if viewModel.config.rules.isEmpty {
                Text(L10n.tr("common.no_rules_configured"))
                    .foregroundColor(.secondary)
            }
            ForEach(viewModel.config.rules) { rule in
                HStack {
                    VStack(alignment: .leading) {
                        Text(rule.destination)
                            .font(.system(.body, design: .monospaced))
                        Text("\(rule.hardwarePort) (\(rule.interfaceName)) \(L10n.fmt("common.via", rule.gateway))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(rule.isActive ? L10n.tr("common.active") : L10n.tr("common.inactive"))
                        .font(.caption)
                        .foregroundColor(rule.isActive ? .green : .secondary)
                }
            }
        }
        .padding(20)
    }
}

// MARK: - About

struct AboutView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("RouteFlow")
                .font(.title2)
                .fontWeight(.bold)

            Text(L10n.tr("settings.about_subtitle"))
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text(L10n.tr("common.version"))
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(20)
    }
}
