import Foundation

class ConfigManager {
    static let shared = ConfigManager()

    private let fileManager = FileManager.default
    private let configDirectoryName = "RouteFlow"
    private let configFileName = "config.json"

    var configDirectoryURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(configDirectoryName)
    }

    var configFilePath: URL {
        configDirectoryURL.appendingPathComponent(configFileName)
    }

    private init() {}

    func loadConfig() -> AppConfig {
        let path = configFilePath
        guard fileManager.fileExists(atPath: path.path) else {
            return AppConfig()
        }

        do {
            let data = try Data(contentsOf: path)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let config = try decoder.decode(AppConfig.self, from: data)
            return config
        } catch {
            print("Failed to load config: \(error)")
            return AppConfig()
        }
    }

    func saveConfig(_ config: AppConfig) throws {
        let dir = configDirectoryURL
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        try data.write(to: configFilePath, options: .atomic)
    }

    func exportConfig(to url: URL) throws {
        let config = loadConfig()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(config)
        try data.write(to: url, options: .atomic)
    }

    func importConfig(from url: URL) throws -> AppConfig {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config = try decoder.decode(AppConfig.self, from: data)
        guard config.version == AppConfig.currentVersion else {
            throw ConfigError.unsupportedVersion(config.version)
        }
        try saveConfig(config)
        return config
    }

    enum ConfigError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                return L10n.fmt("common.unsupported_config_version", v)
            }
        }
    }
}
