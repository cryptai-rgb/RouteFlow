import Foundation
import SystemConfiguration

@MainActor
class NetworkDetector: ObservableObject {
    @Published var interfaces: [NetworkInterface] = []

    private var store: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?
    private var monitoringThread: Thread?

    func startMonitoring() {
        guard monitoringThread == nil else {
            refreshInterfaces()
            return
        }

        refreshInterfaces()
        setupDynamicStoreMonitoring()
    }

    func stopMonitoring() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
        runLoopSource = nil
        store = nil
        monitoringThread = nil
    }

    func refreshInterfaces() {
        Task {
            let detected = await detectAllInterfaces()
            if detected != interfaces {
                interfaces = detected
            }
        }
    }

    // MARK: - Detection

    private func detectAllInterfaces() async -> [NetworkInterface] {
        let portInfos = await parseHardwarePorts()
        let serviceOrder = await fetchServiceOrder()

        var result: [NetworkInterface] = []
        for portInfo in portInfos {
            var iface = portInfo
            let ifconfigInfo = await parseIfConfig(iface.deviceName)
            iface.isActive = ifconfigInfo.isActive
            iface.ipAddress = ifconfigInfo.ipAddress
            iface.subnetMask = ifconfigInfo.subnetMask

            let gatewayInfo = await parseGateway(iface.hardwarePort)
            iface.gateway = gatewayInfo

            // Apply system service order priority
            iface.serviceOrder = serviceOrder[iface.hardwarePort] ?? Int.max

            result.append(iface)
        }

        // Sort by system service order (highest priority first)
        result.sort { $0.serviceOrder < $1.serviceOrder }

        return result
    }

    // MARK: - networksetup -listnetworkserviceorder

    private func fetchServiceOrder() async -> [String: Int] {
        do {
            let output = try await runCommand("/usr/sbin/networksetup", arguments: ["-listnetworkserviceorder"])
            return parseServiceOrderOutput(output)
        } catch {
            print("Failed to get service order: \(error)")
            return [:]
        }
    }

    /// Parse output like:
    /// (1) Wi-Fi
    /// (Hardware Port: Wi-Fi, Device: en1)
    /// (2) Ethernet
    /// (Hardware Port: Ethernet, Device: en0)
    private func parseServiceOrderOutput(_ output: String) -> [String: Int] {
        var order: [String: Int] = [:]
        var currentIndex: Int?

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Match "(1) Wi-Fi"
            if trimmed.hasPrefix("(") && trimmed.contains(")") {
                let open = trimmed.firstIndex(of: "(")!
                let close = trimmed.firstIndex(of: ")")!
                let numStr = String(trimmed[trimmed.index(after: open)..<close])
                if let num = Int(numStr) {
                    currentIndex = num
                }
            }

            // Match "(Hardware Port: Wi-Fi, Device: en1)"
            if let idx = currentIndex, trimmed.contains("Hardware Port:") {
                let portName = trimmed
                    .components(separatedBy: ",")
                    .first?
                    .replacingOccurrences(of: "(", with: "")
                    .replacingOccurrences(of: "Hardware Port:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if let port = portName {
                    order[port] = idx
                }
                currentIndex = nil
            }
        }

        return order
    }

    // MARK: - networksetup -listallhardwareports

    private func parseHardwarePorts() async -> [NetworkInterface] {
        do {
            let output = try await runCommand("/usr/sbin/networksetup", arguments: ["-listallhardwareports"])
            return parseHardwarePortsOutput(output)
        } catch {
            print("Failed to list hardware ports: \(error)")
            return []
        }
    }

    private func parseHardwarePortsOutput(_ output: String) -> [NetworkInterface] {
        var result: [NetworkInterface] = []
        var currentPort: String?
        var currentDevice: String?
        var currentMac: String?

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Hardware Port:") {
                currentPort = trimmed.replacingOccurrences(of: "Hardware Port:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Device:") {
                currentDevice = trimmed.replacingOccurrences(of: "Device:", with: "").trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("Ethernet Address:") {
                currentMac = trimmed.replacingOccurrences(of: "Ethernet Address:", with: "").trimmingCharacters(in: .whitespaces)
            }

            if let port = currentPort, let device = currentDevice, let mac = currentMac {
                if device.hasPrefix("en") || device.hasPrefix("utun") || device == "lo0" {
                    result.append(NetworkInterface(
                        id: device,
                        deviceName: device,
                        hardwarePort: port,
                        macAddress: mac,
                        isActive: false
                    ))
                }
                currentPort = nil
                currentDevice = nil
                currentMac = nil
            }
        }

        return result
    }

    // MARK: - ifconfig

    private func parseIfConfig(_ device: String) async -> IfConfigInfo {
        do {
            let output = try await runCommand("/sbin/ifconfig", arguments: [device])
            return parseIfConfigOutput(output)
        } catch {
            return IfConfigInfo()
        }
    }

    private func parseIfConfigOutput(_ output: String) -> IfConfigInfo {
        var info = IfConfigInfo()

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.contains("status: active") {
                info.isActive = true
            }

            if trimmed.hasPrefix("inet ") {
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count >= 4 {
                    info.ipAddress = parts[1]
                    let netmaskHex = parts[3]
                    info.subnetMask = convertHexNetmask(netmaskHex)
                }
            }
        }

        return info
    }

    // MARK: - networksetup -getinfo

    private func parseGateway(_ hardwarePort: String) async -> String? {
        do {
            let output = try await runCommand("/usr/sbin/networksetup", arguments: ["-getinfo", hardwarePort])
            return parseGatewayOutput(output)
        } catch {
            return nil
        }
    }

    private func parseGatewayOutput(_ output: String) -> String? {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Router:") {
                let router = trimmed.replacingOccurrences(of: "Router:", with: "").trimmingCharacters(in: .whitespaces)
                return router.isEmpty ? nil : router
            }
        }
        return nil
    }

    // MARK: - SCDynamicStore Monitoring

    private func setupDynamicStoreMonitoring() {
        // Run SCDynamicStore on a background thread with its own run loop
        let thread = Thread {
            var storeContext = SCDynamicStoreContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )

            guard let store = SCDynamicStoreCreate(nil, "RouteFlow" as CFString, { (_, _, context) in
                guard let context = context else { return }
                let detector = Unmanaged<NetworkDetector>.fromOpaque(context).takeUnretainedValue()
                Task { @MainActor in
                    detector.refreshInterfaces()
                }
            }, &storeContext) else {
                print("Failed to create SCDynamicStore")
                return
            }

            let keys: [CFString] = [
                "State:/Network/Interface" as CFString,
                "State:/Network/Global/IPv4" as CFString,
            ]

            let patterns: [CFString] = [
                "State:/Network/Interface/.*/IPv4" as CFString,
            ]

            if !SCDynamicStoreSetNotificationKeys(store, keys as CFArray, patterns as CFArray) {
                print("Failed to set notification keys")
                return
            }

            let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)

            // Store references on main actor
            DispatchQueue.main.async {
                self.store = store
                self.runLoopSource = source
            }

            CFRunLoopRun()
        }

        thread.name = "com.routeflow.networkmonitor"
        thread.start()
        self.monitoringThread = thread
    }

    // MARK: - Helpers

    private func runCommand(_ command: String, arguments: [String]) async throws -> String {
        let executor = PrivilegedExecutor()
        return try await executor.executeCommand(command, arguments: arguments)
    }

    private func convertHexNetmask(_ hex: String) -> String? {
        var hexValue = hex
        if hexValue.hasPrefix("0x") || hexValue.hasPrefix("0X") {
            hexValue.removeFirst(2)
        }

        guard hexValue.count == 8, let fullValue = UInt32(hexValue, radix: 16) else {
            return nil
        }

        let b1 = (fullValue >> 24) & 0xFF
        let b2 = (fullValue >> 16) & 0xFF
        let b3 = (fullValue >> 8) & 0xFF
        let b4 = fullValue & 0xFF

        return "\(b1).\(b2).\(b3).\(b4)"
    }
}

private struct IfConfigInfo {
    var isActive: Bool = false
    var ipAddress: String?
    var subnetMask: String?
}
