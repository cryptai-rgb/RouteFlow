import SwiftUI
import UserNotifications

@main
struct RouteFlowApp: App {
    @StateObject private var menuBarViewModel: MenuBarViewModel

    init() {
        let viewModel = MenuBarViewModel()
        _menuBarViewModel = StateObject(wrappedValue: viewModel)

        // Request notification authorization
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                print("Notification auth error: \(error)")
            }
        }

        Task { @MainActor in
            viewModel.initializeIfNeeded()
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(menuBarViewModel)
        } label: {
            Image(systemName: menuBarViewModel.statusIcon)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(menuBarViewModel.settingsViewModel)
        }
    }
}
