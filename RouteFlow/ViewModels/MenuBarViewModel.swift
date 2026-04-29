import AppKit
import Foundation
import SwiftUI
import UserNotifications
import Combine

@MainActor
final class PrivilegeExplanationService {
    private var hasShownStartupPrivilegeNotice = false

    func confirmStartupRouteChange(ruleCount: Int) -> Bool {
        guard ruleCount > 0 else { return true }
        guard !hasShownStartupPrivilegeNotice else { return true }
        hasShownStartupPrivilegeNotice = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.tr("startup.privilege.title")
        alert.informativeText = L10n.tr("startup.privilege.message")
        alert.addButton(withTitle: L10n.tr("startup.privilege.continue"))
        alert.addButton(withTitle: L10n.tr("common.cancel"))

        NSApp.activate(ignoringOtherApps: true)

        return alert.runModal() == .alertFirstButtonReturn
    }
}

@MainActor
class MenuBarViewModel: ObservableObject {
    struct BatchAddFailure {
        let destination: String
        let reason: String
    }

    struct BatchAddResult {
        let added: [String]
        let imported: [String]
        let alreadySaved: [String]
        let failed: [BatchAddFailure]
        let activatedApp: Bool
    }

    @Published var config: AppConfig
    @Published var isGloballyActive: Bool = true
    @Published var isGlobalToggleInFlight: Bool = false
    @Published var isShowingAddRouteSheet: Bool = false
    @Published var selectedInterfaceID: String?

    let networkDetector = NetworkDetector()
    let routeManager = RouteManager()
    let settingsViewModel: SettingsViewModel
    private let privilegeExplanationService = PrivilegeExplanationService()

    private var cancellables = Set<AnyCancellable>()
    private var previousInterfaces: [NetworkInterface] = []
    private var debounceTask: Task<Void, Never>?
    private var hasInitialized = false
    private var interfaceObservationTask: Task<Void, Never>?

    var interfaces: [NetworkInterface] {
        networkDetector.interfaces
    }

    var statusIcon: String {
        guard isGloballyActive else { return "link.circle" }
        if !routeManager.failedRules.isEmpty {
            return "exclamationmark.triangle.fill"
        }
        if routeManager.appliedRules.isEmpty && !config.rules.isEmpty {
            return "link.circle"
        }
        return "link.circle.fill"
    }

    var statusColor: Color? {
        guard isGloballyActive else { return nil }
        if !routeManager.failedRules.isEmpty {
            return .orange
        }
        return .green
    }

    var activeRules: [RouteRule] {
        config.rules.filter { $0.isActive }
    }

    var validTargetInterfaces: [NetworkInterface] {
        interfaces.filter { $0.isValidRouteTarget }
    }

    var selectedInterface: NetworkInterface? {
        guard let selectedInterfaceID else { return nil }
        return interfaces.first { $0.id == selectedInterfaceID }
    }

    /// Route rules belonging to a specific interface.
    func rulesForInterface(_ iface: NetworkInterface) -> [RouteRule] {
        config.rules.filter { $0.matches(interface: iface) }
    }

    func manualRoutesForInterface(_ iface: NetworkInterface) -> [SystemRouteEntry] {
        routeManager.manualRoutes.filter { $0.matches(interface: iface) }
    }

    func exportableNetworkRoutes(for iface: NetworkInterface) -> [SystemRouteEntry] {
        manualRoutesForInterface(iface)
            .filter(\.isNetworkRoute)
            .sorted { $0.destination.localizedStandardCompare($1.destination) == .orderedAscending }
    }

    func isManagedRoute(_ route: SystemRouteEntry) -> Bool {
        config.rules.contains { rule in
            RouteCommandBuilder.destinationsEquivalent(rule.destination, route.destination) &&
            rule.interfaceName == route.interfaceName &&
            rule.gateway == route.gateway
        }
    }

    init() {
        let loadedConfig = ConfigManager.shared.loadConfig()
        self.config = loadedConfig
        self.isGloballyActive = loadedConfig.isActive
        self.settingsViewModel = SettingsViewModel()
        self.settingsViewModel.config = loadedConfig

        // Forward child ObservableObject changes so SwiftUI re-renders
        networkDetector.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)

        networkDetector.$interfaces
            .sink { [weak self] interfaces in
                self?.syncSelectedInterface(with: interfaces)
                Task {
                    await self?.refreshSystemRoutes()
                }
            }
            .store(in: &cancellables)

        routeManager.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func initializeIfNeeded() {
        guard !hasInitialized else { return }
        hasInitialized = true

        networkDetector.startMonitoring()
        reconcileRoutesOnInitialization()

        // Start observing interface changes
        observeInterfaceChanges()
    }

    func handleMenuPresented() {
        initializeIfNeeded()
        Task {
            await refreshSystemRoutes()
        }
    }

    // MARK: - Interface Change Observation

    private func observeInterfaceChanges() {
        guard interfaceObservationTask == nil else { return }

        // Use a timer to periodically check for interface changes
        // SCDynamicStore callback already triggers refreshInterfaces,
        // so we just need to react to changes in the published property
        interfaceObservationTask = Task {
            for await _ in Timer.publish(every: 5, on: .main, in: .common).autoconnect().values {
                await handleInterfaceChanges()
            }
        }
    }

    private func handleInterfaceChanges() async {
        let current = networkDetector.interfaces
        defer { previousInterfaces = current }

        guard !previousInterfaces.isEmpty else {
            previousInterfaces = current
            return
        }

        guard isGloballyActive else { return }

        // Check for interfaces that went down
        for prevIface in previousInterfaces {
            if prevIface.isActive,
               let currentIface = current.first(where: { $0.id == prevIface.id }),
               !currentIface.isActive {
                // Interface went down - mark affected rules
                await markRulesInvalidForInterface(prevIface.deviceName)
                sendNotification(
                    title: L10n.tr("notify.interface_down.title"),
                    body: L10n.fmt("notify.interface_down.body", prevIface.hardwarePort, prevIface.deviceName)
                )
            }
        }

        // Check for interfaces that came back up
        for currentIface in current {
            if currentIface.isActive,
               let prevIface = previousInterfaces.first(where: { $0.id == currentIface.id }),
               !prevIface.isActive {
                // Interface came back up - restore affected rules
                await restoreRulesForInterface(currentIface.deviceName)
                sendNotification(
                    title: L10n.tr("notify.interface_up.title"),
                    body: L10n.fmt("notify.interface_up.body", currentIface.hardwarePort, currentIface.deviceName)
                )
            }
        }

        await refreshSystemRoutes()
    }

    private func markRulesInvalidForInterface(_ deviceName: String) async {
        let affectedRules = config.rules.filter { $0.interfaceName == deviceName && $0.isActive }
        for rule in affectedRules {
            routeManager.appliedRules.remove(rule.id)
            routeManager.failedRules.insert(rule.id)
        }
    }

    private func restoreRulesForInterface(_ deviceName: String) async {
        let affectedRules = config.rules.filter { $0.interfaceName == deviceName && $0.isActive }
        guard !affectedRules.isEmpty else { return }

        do {
            _ = try await routeManager.applyRules(affectedRules)
        } catch {
            // Will be tracked in routeManager so interface monitoring can continue.
        }
    }

    // MARK: - Notifications

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Notification error: \(error)")
            }
        }
    }

    private func reconcileRoutesOnInitialization() {
        Task {
            await refreshSystemRoutes()

            if isGloballyActive {
                guard config.autoApplyOnLaunch else { return }
                let rulesToApply = RouteManager.rulesToApplyOnActivation(config.rules)
                    .filter { !hasMatchingSystemRoute(for: $0) }
                guard !rulesToApply.isEmpty else { return }
                guard await confirmStartupPrivilegePrompt(ruleCount: rulesToApply.count) else { return }
                await routeManager.applyAllRules(rulesToApply)
                await refreshSystemRoutes()
                return
            }

            let rulesToRemove = RouteManager.rulesToRemoveOnGlobalDeactivate(config.rules)
                .filter { hasInstalledSystemRoute(for: $0) }
            guard !rulesToRemove.isEmpty else { return }
            guard await confirmStartupPrivilegePrompt(ruleCount: rulesToRemove.count) else { return }
            await routeManager.removeAllRules(rulesToRemove)
            await refreshSystemRoutes()
        }
    }

    // MARK: - User Actions

    func toggleGlobalActive() {
        guard !isGlobalToggleInFlight else { return }

        let targetState = !isGloballyActive
        isGlobalToggleInFlight = true
        routeManager.lastError = nil

        Task {
            defer { isGlobalToggleInFlight = false }

            do {
                if targetState {
                    _ = try await routeManager.applyRules(
                        RouteManager.rulesToApplyOnActivation(config.rules)
                    )
                } else {
                    await refreshSystemRoutes()

                    let rulesToRemove = RouteManager.rulesToRemoveOnGlobalDeactivate(config.rules)
                        .filter { hasInstalledSystemRoute(for: $0) }

                    if !rulesToRemove.isEmpty {
                        _ = try await routeManager.removeRules(rulesToRemove)
                    }
                }

                isGloballyActive = targetState
                config.isActive = targetState
                saveConfig()
            } catch {
                routeManager.lastError = error.localizedDescription
            }

            await refreshSystemRoutes()
        }
    }

    func addRules(destinations: [String], to iface: NetworkInterface) async -> BatchAddResult {
        guard let gateway = iface.gateway else {
            return BatchAddResult(
                added: [],
                imported: [],
                alreadySaved: [],
                failed: [BatchAddFailure(destination: "", reason: L10n.tr("add.interface_no_gateway"))],
                activatedApp: false
            )
        }

        let normalizedDestinations = destinations.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        var added: [String] = []
        var imported: [String] = []
        var alreadySaved: [String] = []
        var failed: [BatchAddFailure] = []
        var rulesToPersist: [RouteRule] = []
        var rulesToApply: [RouteRule] = []
        let wasInactive = !isGloballyActive

        for destination in normalizedDestinations {
            let rule = RouteRule(
                destination: destination,
                interfaceName: iface.deviceName,
                gateway: gateway,
                hardwarePort: iface.hardwarePort
            )

            if config.rules.contains(where: {
                RouteCommandBuilder.destinationsEquivalent($0.destination, destination) &&
                $0.interfaceName == iface.deviceName &&
                $0.gateway == gateway
            }) {
                alreadySaved.append(destination)
                continue
            }

            if routeManager.manualRoutes.contains(where: {
                RouteCommandBuilder.routeMatches(rule: rule, entry: $0)
            }) {
                imported.append(destination)
                rulesToPersist.append(rule)
                continue
            }

            if routeManager.manualRoutes.contains(where: {
                RouteCommandBuilder.routeIdentityMatches(rule: rule, entry: $0) && $0.isInterfaceScoped
            }) {
                rulesToApply.append(rule)
                continue
            }

            if let existingRoute = routeManager.manualRoutes.first(where: {
                RouteCommandBuilder.destinationsEquivalent($0.destination, destination)
            }) {
                failed.append(
                    BatchAddFailure(
                        destination: destination,
                        reason: L10n.fmt("add.route_exists", existingRoute.interfaceName, existingRoute.gateway)
                    )
                )
                continue
            }

            rulesToApply.append(rule)
        }

        if !rulesToApply.isEmpty {
            do {
                let batchResult = try await routeManager.applyRules(rulesToApply)
                for rule in rulesToApply {
                    if batchResult.succeededRuleIDs.contains(rule.id) {
                        added.append(rule.destination)
                        rulesToPersist.append(rule)
                    } else {
                        failed.append(
                            BatchAddFailure(
                                destination: rule.destination,
                                reason: batchResult.failures[rule.id] ?? L10n.tr("add.failed_add")
                            )
                        )
                    }
                }
            } catch let error as PrivilegedExecutor.PrivilegedError {
                for rule in rulesToApply {
                    failed.append(BatchAddFailure(destination: rule.destination, reason: error.localizedDescription))
                }
            } catch {
                for rule in rulesToApply {
                    failed.append(BatchAddFailure(destination: rule.destination, reason: error.localizedDescription))
                }
            }
        }

        if !rulesToPersist.isEmpty {
            if wasInactive {
                isGloballyActive = true
                config.isActive = true
            }
            config.rules.append(contentsOf: rulesToPersist)
        }

        if !rulesToPersist.isEmpty {
            saveConfig()
        }

        await refreshSystemRoutes()

        return BatchAddResult(
            added: added,
            imported: imported,
            alreadySaved: alreadySaved,
            failed: failed,
            activatedApp: wasInactive
        )
    }

    func removeRule(_ rule: RouteRule) {
        guard Self.shouldRemoveSystemRouteWhenDeletingSavedRule(isGloballyActive: isGloballyActive) else {
            deleteSavedRuleLocally(rule)
            return
        }

        Task {
            do {
                try await routeManager.removeRule(rule)
                deleteSavedRuleLocally(rule)
            } catch {
                routeManager.lastError = error.localizedDescription
            }
            await refreshSystemRoutes()
        }
    }

    func removeManagedRoute(_ route: SystemRouteEntry) async {
        do {
            try await routeManager.removeRoute(
                destination: route.destination,
                interfaceName: route.interfaceName,
                gateway: route.gateway
            )
            config.rules.removeAll {
                RouteCommandBuilder.destinationsEquivalent($0.destination, route.destination) &&
                $0.interfaceName == route.interfaceName &&
                $0.gateway == route.gateway
            }
            saveConfig()
        } catch {
            routeManager.lastError = error.localizedDescription
        }
        await refreshSystemRoutes()
    }

    func toggleRule(_ rule: RouteRule) {
        guard let index = config.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        config.rules[index].isActive.toggle()
        saveConfig()
    }

    func applyRuleNow(_ rule: RouteRule) {
        Task {
            do {
                try await routeManager.applyRule(rule)
            } catch {
                // Error is tracked in routeManager
            }
            await refreshSystemRoutes()
        }
    }

    func refreshInterfaces() {
        networkDetector.refreshInterfaces()
        Task {
            await refreshSystemRoutes()
        }
    }

    func saveConfig() {
        try? ConfigManager.shared.saveConfig(config)
        settingsViewModel.config = config
    }

    /// Called when the app is about to quit
    func onQuit() {
        if config.cleanRoutesOnExit {
            Task {
                await routeManager.removeAllRules(config.rules)
            }
        }
        interfaceObservationTask?.cancel()
        interfaceObservationTask = nil
        networkDetector.stopMonitoring()
    }

    private func syncSelectedInterface(with interfaces: [NetworkInterface]) {
        guard !interfaces.isEmpty else {
            selectedInterfaceID = nil
            return
        }

        if let selectedInterfaceID,
           interfaces.contains(where: { $0.id == selectedInterfaceID }) {
            return
        }

        selectedInterfaceID = interfaces.first(where: \.isActive)?.id ?? interfaces.first?.id
    }

    private func confirmStartupPrivilegePrompt(ruleCount: Int) async -> Bool {
        let confirmed = privilegeExplanationService.confirmStartupRouteChange(ruleCount: ruleCount)

        if !confirmed {
            routeManager.lastError = L10n.tr("startup.privilege.cancelled")
        }

        return confirmed
    }

    private func refreshSystemRoutes() async {
        await routeManager.refreshManualRoutes()
        routeManager.syncAppliedState(with: config.rules)
    }

    private func hasMatchingSystemRoute(for rule: RouteRule) -> Bool {
        routeManager.manualRoutes.contains(where: { RouteCommandBuilder.routeMatches(rule: rule, entry: $0) })
    }

    private func hasInstalledSystemRoute(for rule: RouteRule) -> Bool {
        routeManager.manualRoutes.contains(where: { RouteCommandBuilder.routeIdentityMatches(rule: rule, entry: $0) })
    }

    private func deleteSavedRuleLocally(_ rule: RouteRule) {
        config.rules.removeAll { $0.id == rule.id }
        routeManager.appliedRules.remove(rule.id)
        routeManager.failedRules.remove(rule.id)
        saveConfig()
    }

    static func shouldRemoveSystemRouteWhenDeletingSavedRule(isGloballyActive: Bool) -> Bool {
        isGloballyActive
    }
}
