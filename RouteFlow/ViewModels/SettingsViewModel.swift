import Foundation
import SwiftUI

@MainActor
class SettingsViewModel: ObservableObject {
    @Published var config: AppConfig = AppConfig()

    var autoApplyOnLaunch: Bool {
        get { config.autoApplyOnLaunch }
        set {
            config.autoApplyOnLaunch = newValue
            saveConfig()
        }
    }

    var cleanRoutesOnExit: Bool {
        get { config.cleanRoutesOnExit }
        set {
            config.cleanRoutesOnExit = newValue
            saveConfig()
        }
    }

    private func saveConfig() {
        try? ConfigManager.shared.saveConfig(config)
    }
}
