import Foundation

struct AppConfig: Codable, Equatable {
    var version: Int
    var isActive: Bool
    var autoApplyOnLaunch: Bool
    var rules: [RouteRule]
    var cleanRoutesOnExit: Bool

    static let currentVersion = 1

    init(
        version: Int = currentVersion,
        isActive: Bool = true,
        autoApplyOnLaunch: Bool = true,
        rules: [RouteRule] = [],
        cleanRoutesOnExit: Bool = false
    ) {
        self.version = version
        self.isActive = isActive
        self.autoApplyOnLaunch = autoApplyOnLaunch
        self.rules = rules
        self.cleanRoutesOnExit = cleanRoutesOnExit
    }
}
