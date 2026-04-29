import Foundation

struct RouteCommandBuilder {

    /// Build a route add command arguments
    /// - Parameters:
    ///   - destination: IP address or CIDR (e.g. "10.0.0.5" or "192.168.1.0/24")
    ///   - interfaceName: Device name (e.g. "en1")
    ///   - gateway: Gateway IP (e.g. "10.65.72.1")
    /// - Returns: Array of arguments for `/sbin/route add`
    static func buildAddCommand(destination: String, interfaceName: String, gateway: String) -> [String] {
        var args = ["add"]
        let normalizedDestination = canonicalDestination(destination)

        if normalizedDestination.contains("/") {
            // CIDR notation → network route
            args += ["-net", normalizedDestination]
        } else {
            // Single IP → host route
            args += ["-host", normalizedDestination]
        }

        _ = interfaceName
        args.append(gateway)
        return args
    }

    /// Build a route delete command arguments
    /// - Parameters:
    ///   - destination: IP address or CIDR
    ///   - gateway: Gateway IP used when the route was created
    /// - Returns: Array of arguments for `/sbin/route delete`
    static func buildDeleteCommand(destination: String, gateway: String? = nil) -> [String] {
        var args = ["delete"]
        let normalizedDestination = canonicalDestination(destination)

        if normalizedDestination.contains("/") {
            args += ["-net", normalizedDestination]
        } else {
            args += ["-host", normalizedDestination]
        }

        if let gateway, !gateway.isEmpty {
            args.append(gateway)
        }
        return args
    }

    /// Build a legacy scoped route delete command for migrating old `-ifscope` routes.
    static func buildScopedDeleteCommand(destination: String, interfaceName: String, gateway: String? = nil) -> [String] {
        var args = buildDeleteCommand(destination: destination)
        args += ["-ifscope", interfaceName]
        if let gateway, !gateway.isEmpty {
            args.append(gateway)
        }
        return args
    }

    /// Build a route get command arguments (no privileges needed)
    /// - Parameter destination: IP address
    /// - Returns: Array of arguments for `/sbin/route get`
    static func buildGetCommand(destination: String) -> [String] {
        return ["get", destination]
    }

    /// Parse the output of `route get <destination>` to extract the interface name
    static func parseRouteGetOutput(_ output: String) -> RouteGetResult? {
        var interface: String?
        var gateway: String?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("interface:") {
                interface = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("gateway:") {
                gateway = trimmed.components(separatedBy: ":").dropFirst().joined(separator: ":").trimmingCharacters(in: .whitespaces)
            }
        }

        guard let interface = interface else { return nil }
        return RouteGetResult(interface: interface, gateway: gateway)
    }

    /// Parse `netstat -nr -f inet` output and keep only manually scoped gateway routes.
    static func parseManualRouteTableOutput(_ output: String) -> [SystemRouteEntry] {
        output
            .components(separatedBy: .newlines)
            .compactMap(parseRouteTableLine)
            .filter { hasRequiredGatewayFlags($0.flags) }
    }

    static func hasRequiredGatewayFlags(_ flags: String) -> Bool {
        let requiredFlags: Set<Character> = ["U", "G", "S"]
        return requiredFlags.isSubset(of: Set(flags))
    }

    static func destinationsEquivalent(_ lhs: String, _ rhs: String) -> Bool {
        if let lhsCIDR = parseCIDR(lhs), let rhsCIDR = parseCIDR(rhs) {
            return lhsCIDR.prefixLength == rhsCIDR.prefixLength && lhsCIDR.networkAddress == rhsCIDR.networkAddress
        }
        return lhs == rhs
    }

    static func routeMatches(rule: RouteRule, entry: SystemRouteEntry) -> Bool {
        routeIdentityMatches(rule: rule, entry: entry) && !entry.isInterfaceScoped
    }

    static func routeIdentityMatches(rule: RouteRule, entry: SystemRouteEntry) -> Bool {
        destinationsEquivalent(rule.destination, entry.destination) &&
        rule.interfaceName == entry.interfaceName &&
        rule.gateway == entry.gateway
    }

    static func canonicalDestination(_ destination: String) -> String {
        guard let cidr = parseCIDR(destination) else { return destination }
        return "\(string(from: cidr.networkAddress))/\(cidr.prefixLength)"
    }

    private static func parseRouteTableLine(_ line: String) -> SystemRouteEntry? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.hasPrefix("Routing tables"),
              !trimmed.hasPrefix("Internet:"),
              !trimmed.hasPrefix("Destination") else {
            return nil
        }

        let columns = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        guard columns.count >= 4 else { return nil }

        return SystemRouteEntry(
            destination: columns[0],
            gateway: columns[1],
            flags: columns[2],
            interfaceName: columns[3],
            expire: columns.count > 4 ? columns[4] : nil
        )
    }

    private struct IPv4CIDR {
        let networkAddress: UInt32
        let prefixLength: Int
    }

    private static func parseCIDR(_ destination: String) -> IPv4CIDR? {
        let components = destination.split(separator: "/", omittingEmptySubsequences: false)
        guard components.count == 2, let prefixLength = Int(components[1]), (0...32).contains(prefixLength) else {
            return nil
        }
        guard let address = parseIPv4Address(String(components[0]), allowCompressedTrailingZeros: true) else {
            return nil
        }

        let mask: UInt32 = prefixLength == 0 ? 0 : UInt32.max << (32 - UInt32(prefixLength))
        return IPv4CIDR(networkAddress: address & mask, prefixLength: prefixLength)
    }

    private static func parseIPv4Address(_ raw: String, allowCompressedTrailingZeros: Bool) -> UInt32? {
        let components = raw.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty else { return nil }

        let expectedCount = allowCompressedTrailingZeros ? 1...4 : 4...4
        guard expectedCount.contains(components.count) else { return nil }

        var octets = components.compactMap { UInt8($0) }
        guard octets.count == components.count else { return nil }

        if allowCompressedTrailingZeros {
            octets.append(contentsOf: repeatElement(0, count: 4 - octets.count))
        }

        guard octets.count == 4 else { return nil }

        return octets.reduce(UInt32(0)) { partialResult, octet in
            (partialResult << 8) | UInt32(octet)
        }
    }

    private static func string(from address: UInt32) -> String {
        let octets: [UInt32] = [
            (address >> 24) & 0xff,
            (address >> 16) & 0xff,
            (address >> 8) & 0xff,
            address & 0xff
        ]
        return octets.map(String.init).joined(separator: ".")
    }
}

struct RouteGetResult {
    let interface: String
    let gateway: String?
}

struct SystemRouteEntry: Identifiable, Equatable {
    let destination: String
    let gateway: String
    let flags: String
    let interfaceName: String
    let expire: String?

    var id: String {
        [destination, gateway, flags, interfaceName, expire ?? ""].joined(separator: "|")
    }

    var isDefaultRoute: Bool {
        destination == "default"
    }

    var isNetworkRoute: Bool {
        destination.contains("/") && !isDefaultRoute
    }

    var isInterfaceScoped: Bool {
        flags.contains("I")
    }

    var routeKindTitle: String {
        if isDefaultRoute {
            return L10n.tr("common.default_route")
        }
        return isNetworkRoute ? L10n.tr("common.network_route") : L10n.tr("common.host_route")
    }

    func matches(interface: NetworkInterface) -> Bool {
        interfaceName == interface.deviceName
    }
}
