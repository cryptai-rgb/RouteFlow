import Foundation

struct NetworkInterface: Identifiable, Equatable {
    let id: String          // deviceName as id
    let deviceName: String  // e.g. "en0"
    let hardwarePort: String // e.g. "Wi-Fi"
    let macAddress: String
    var isActive: Bool
    var ipAddress: String?
    var subnetMask: String?
    var gateway: String?
    var serviceOrder: Int = Int.max  // from networksetup -listnetworkserviceorder, lower = higher priority

    /// Whether this interface can be used as a route target
    var isValidRouteTarget: Bool {
        isActive && ipAddress != nil && gateway != nil
    }

    init(
        id: String,
        deviceName: String,
        hardwarePort: String,
        macAddress: String,
        isActive: Bool = false,
        ipAddress: String? = nil,
        subnetMask: String? = nil,
        gateway: String? = nil,
        serviceOrder: Int = Int.max
    ) {
        self.id = id
        self.deviceName = deviceName
        self.hardwarePort = hardwarePort
        self.macAddress = macAddress
        self.isActive = isActive
        self.ipAddress = ipAddress
        self.subnetMask = subnetMask
        self.gateway = gateway
        self.serviceOrder = serviceOrder
    }

    static func == (lhs: NetworkInterface, rhs: NetworkInterface) -> Bool {
        lhs.id == rhs.id &&
        lhs.isActive == rhs.isActive &&
        lhs.ipAddress == rhs.ipAddress &&
        lhs.gateway == rhs.gateway
    }
}
