import Foundation

struct RouteRule: Identifiable, Codable, Equatable {
    let id: UUID
    var destination: String      // IP or CIDR, e.g. "10.0.0.5" or "192.168.1.0/24"
    var interfaceName: String    // e.g. "en1"
    var gateway: String          // e.g. "10.65.72.1"
    var hardwarePort: String     // e.g. "Wi-Fi"
    var isActive: Bool
    var createdAt: Date

    /// Whether this rule uses CIDR notation (network route) or a single host
    var routeType: RouteType {
        destination.contains("/") ? .network : .host
    }

    /// A rule belongs to the interface it was created for, keyed by device name.
    func matches(interface: NetworkInterface) -> Bool {
        interfaceName == interface.deviceName
    }

    enum RouteType {
        case host
        case network
    }

    init(
        id: UUID = UUID(),
        destination: String,
        interfaceName: String,
        gateway: String,
        hardwarePort: String,
        isActive: Bool = true,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.destination = destination
        self.interfaceName = interfaceName
        self.gateway = gateway
        self.hardwarePort = hardwarePort
        self.isActive = isActive
        self.createdAt = createdAt
    }
}
