import XCTest
@testable import RouteFlow

final class RouteCommandBuilderTests: XCTestCase {

    // MARK: - Add Commands

    func testBuildAddHostCommand() {
        let args = RouteCommandBuilder.buildAddCommand(
            destination: "10.0.0.5",
            interfaceName: "en1",
            gateway: "10.65.72.1"
        )

        XCTAssertEqual(args, ["add", "-host", "10.0.0.5", "10.65.72.1"])
    }

    func testBuildAddNetworkCommand() {
        let args = RouteCommandBuilder.buildAddCommand(
            destination: "192.168.1.0/24",
            interfaceName: "en0",
            gateway: "192.168.1.1"
        )

        XCTAssertEqual(args, ["add", "-net", "192.168.1.0/24", "192.168.1.1"])
    }

    // MARK: - Delete Commands

    func testBuildDeleteHostCommand() {
        let args = RouteCommandBuilder.buildDeleteCommand(destination: "10.0.0.5", gateway: "10.65.72.1")
        XCTAssertEqual(args, ["delete", "-host", "10.0.0.5", "10.65.72.1"])
    }

    func testBuildDeleteNetworkCommand() {
        let args = RouteCommandBuilder.buildDeleteCommand(destination: "192.168.1.0/24", gateway: "192.168.1.1")
        XCTAssertEqual(args, ["delete", "-net", "192.168.1.0/24", "192.168.1.1"])
    }

    func testBuildDeleteNetworkCommandCanonicalizesHostBits() {
        let args = RouteCommandBuilder.buildDeleteCommand(destination: "172.21.11.82/24", gateway: "10.65.196.1")
        XCTAssertEqual(args, ["delete", "-net", "172.21.11.0/24", "10.65.196.1"])
    }

    func testBuildScopedDeleteCommandRetainsIfscopeForLegacyCleanup() {
        let args = RouteCommandBuilder.buildScopedDeleteCommand(
            destination: "172.21.11.82/24",
            interfaceName: "en0",
            gateway: "10.65.196.1"
        )

        XCTAssertEqual(args, ["delete", "-net", "172.21.11.0/24", "-ifscope", "en0", "10.65.196.1"])
    }

    // MARK: - Get Commands

    func testBuildGetCommand() {
        let args = RouteCommandBuilder.buildGetCommand(destination: "10.0.0.5")
        XCTAssertEqual(args, ["get", "10.0.0.5"])
    }

    // MARK: - Parse route get output

    func testParseRouteGetOutput() {
        let output = """
           route to: default
        destination: default
               mask: default
            gateway: 10.65.74.1
          interface: en1
             flags: <UP,GATEWAY,DONE,STATIC,PRCLONING>
        """
        let result = RouteCommandBuilder.parseRouteGetOutput(output)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.interface, "en1")
        XCTAssertEqual(result?.gateway, "10.65.74.1")
    }

    func testParseRouteGetOutputNoGateway() {
        let output = """
          interface: en0
             flags: <UP,DONE,CLONING>
        """
        let result = RouteCommandBuilder.parseRouteGetOutput(output)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.interface, "en0")
        XCTAssertNil(result?.gateway)
    }

    func testParseRouteGetOutputEmpty() {
        let result = RouteCommandBuilder.parseRouteGetOutput("")
        XCTAssertNil(result)
    }

    func testParseManualRouteTableOutputKeepsOnlyUGSRoutes() {
        let output = """
        Routing tables

        Internet:
        Destination        Gateway            Flags               Netif Expire
        default            10.65.72.1         UGScg                 en1
        10.65.72/22        link#12            UCS                   en1      !
        172.21.11/24       10.65.196.1        UGSc                  en0
        """

        let result = RouteCommandBuilder.parseManualRouteTableOutput(output)

        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.map(\.destination), ["default", "172.21.11/24"])
        XCTAssertEqual(result.map(\.interfaceName), ["en1", "en0"])
    }

    func testParseManualRouteTableOutputAcceptsRequiredFlagsInAnyOrder() {
        let output = """
        Destination        Gateway            Flags               Netif Expire
        172.16.36.34       10.65.72.1         USGc                 en1
        172.16.36.35       10.65.72.1         SGU                  en1
        172.16.36.36       10.65.72.1         UGc                  en1
        """

        let result = RouteCommandBuilder.parseManualRouteTableOutput(output)

        XCTAssertEqual(result.map(\.destination), ["172.16.36.34", "172.16.36.35"])
    }

    func testDestinationsEquivalentForCIDRWithHostBitsAndNetworkRoute() {
        XCTAssertTrue(RouteCommandBuilder.destinationsEquivalent("172.21.11.82/24", "172.21.11/24"))
    }

    func testDestinationsEquivalentForDifferentCIDRNetworks() {
        XCTAssertFalse(RouteCommandBuilder.destinationsEquivalent("172.21.12.82/24", "172.21.11/24"))
    }

    func testRouteMatchesTreatsCanonicalCIDRAsEquivalent() {
        let rule = RouteRule(
            destination: "172.21.11.82/24",
            interfaceName: "en0",
            gateway: "10.65.196.1",
            hardwarePort: "Ethernet"
        )
        let entry = SystemRouteEntry(
            destination: "172.21.11/24",
            gateway: "10.65.196.1",
            flags: "UGSc",
            interfaceName: "en0",
            expire: nil
        )

        XCTAssertTrue(RouteCommandBuilder.routeMatches(rule: rule, entry: entry))
    }

    func testRouteMatchesRejectsLegacyInterfaceScopedRoute() {
        let rule = RouteRule(
            destination: "172.21.11.82/24",
            interfaceName: "en0",
            gateway: "10.65.196.1",
            hardwarePort: "Ethernet"
        )
        let entry = SystemRouteEntry(
            destination: "172.21.11/24",
            gateway: "10.65.196.1",
            flags: "UGSI",
            interfaceName: "en0",
            expire: nil
        )

        XCTAssertFalse(RouteCommandBuilder.routeMatches(rule: rule, entry: entry))
        XCTAssertTrue(RouteCommandBuilder.routeIdentityMatches(rule: rule, entry: entry))
    }

    func testRouteMatchesRequiresSameInterfaceAndGateway() {
        let rule = RouteRule(
            destination: "8.8.8.8",
            interfaceName: "en1",
            gateway: "10.65.72.1",
            hardwarePort: "Wi-Fi"
        )
        let entry = SystemRouteEntry(
            destination: "8.8.8.8",
            gateway: "10.65.72.254",
            flags: "UGS",
            interfaceName: "en1",
            expire: nil
        )

        XCTAssertFalse(RouteCommandBuilder.routeMatches(rule: rule, entry: entry))
    }

    func testParseManualRouteTableOutputCapturesFlagsAndExpire() {
        let output = """
        Destination        Gateway            Flags               Netif Expire
        8.8.8.8            10.65.72.1         UGS                  en1     88
        """

        let result = RouteCommandBuilder.parseManualRouteTableOutput(output)

        XCTAssertEqual(result.first?.gateway, "10.65.72.1")
        XCTAssertEqual(result.first?.flags, "UGS")
        XCTAssertEqual(result.first?.expire, "88")
    }

    func testSystemRouteEntryIdentifiesExportableNetworkRoutes() {
        let networkRoute = SystemRouteEntry(
            destination: "172.21.11/24",
            gateway: "10.65.196.1",
            flags: "UGSc",
            interfaceName: "en0",
            expire: nil
        )
        let defaultRoute = SystemRouteEntry(
            destination: "default",
            gateway: "10.65.72.1",
            flags: "UGScg",
            interfaceName: "en1",
            expire: nil
        )
        let hostRoute = SystemRouteEntry(
            destination: "8.8.8.8",
            gateway: "10.65.72.1",
            flags: "UGS",
            interfaceName: "en1",
            expire: nil
        )

        XCTAssertTrue(networkRoute.isNetworkRoute)
        XCTAssertFalse(defaultRoute.isNetworkRoute)
        XCTAssertFalse(hostRoute.isNetworkRoute)
    }
}

final class RouteDestinationParserTests: XCTestCase {

    func testParseAcceptsCompressedCIDRFormatFromExportFile() {
        let parsed = RouteDestinationParser.parse("""
        10.36.3/24
        172.22.7/24
        172.22.16/24
        """)

        XCTAssertEqual(parsed.valid, ["10.36.3/24", "172.22.7/24", "172.22.16/24"])
        XCTAssertTrue(parsed.invalid.isEmpty)
    }

    func testParseRejectsCompressedHostIPv4() {
        let parsed = RouteDestinationParser.parse("10.36.3")

        XCTAssertTrue(parsed.valid.isEmpty)
        XCTAssertEqual(parsed.invalid, ["10.36.3"])
    }

    func testParseDeduplicatesMixedSeparators() {
        let parsed = RouteDestinationParser.parse("172.22.7/24, 172.22.7/24\n172.22.16/24")

        XCTAssertEqual(parsed.valid, ["172.22.7/24", "172.22.16/24"])
    }
}

final class AddRouteInterfaceSelectionTests: XCTestCase {

    func testPreferredInterfaceIDResolvesToMatchingInterface() {
        let interfaces = [
            makeInterface(id: "en1", port: "Wi-Fi"),
            makeInterface(id: "en0", port: "Ethernet")
        ]

        let selectedID = AddRouteInterfaceSelection.reconciledSelectionID(
            from: interfaces,
            preferredInterfaceID: "en0",
            currentSelectionID: nil
        )

        XCTAssertEqual(selectedID, "en0")
        XCTAssertEqual(
            AddRouteInterfaceSelection.selectedInterface(from: interfaces, selectedInterfaceID: selectedID)?.hardwarePort,
            "Ethernet"
        )
    }

    func testCurrentSelectionSurvivesArrayRebuildAndReorder() {
        let original = [
            makeInterface(id: "en1", port: "Wi-Fi"),
            makeInterface(id: "en0", port: "Ethernet")
        ]
        let rebuilt = [
            makeInterface(id: "en0", port: "Ethernet"),
            makeInterface(id: "en1", port: "Wi-Fi")
        ]

        let selectedID = AddRouteInterfaceSelection.reconciledSelectionID(
            from: original,
            preferredInterfaceID: "en1",
            currentSelectionID: "en0"
        )
        let reconciledID = AddRouteInterfaceSelection.reconciledSelectionID(
            from: rebuilt,
            preferredInterfaceID: "en1",
            currentSelectionID: selectedID
        )

        XCTAssertEqual(reconciledID, "en0")
        XCTAssertEqual(
            AddRouteInterfaceSelection.selectedInterface(from: rebuilt, selectedInterfaceID: reconciledID)?.hardwarePort,
            "Ethernet"
        )
    }

    func testMissingSelectionFallsBackToFirstValidInterface() {
        let interfaces = [
            makeInterface(id: "en2", port: "USB Ethernet"),
            makeInterface(id: "en1", port: "Wi-Fi")
        ]

        let selectedID = AddRouteInterfaceSelection.reconciledSelectionID(
            from: interfaces,
            preferredInterfaceID: "en9",
            currentSelectionID: "en8"
        )

        XCTAssertEqual(selectedID, "en2")
    }

    func testEmptyInterfaceListClearsSelection() {
        let selectedID = AddRouteInterfaceSelection.reconciledSelectionID(
            from: [],
            preferredInterfaceID: "en0",
            currentSelectionID: "en1"
        )

        XCTAssertNil(selectedID)
        XCTAssertNil(AddRouteInterfaceSelection.selectedInterface(from: [], selectedInterfaceID: selectedID))
    }

    private func makeInterface(id: String, port: String) -> NetworkInterface {
        NetworkInterface(
            id: id,
            deviceName: id,
            hardwarePort: port,
            macAddress: "aa:bb:cc:dd:ee:ff",
            isActive: true,
            ipAddress: "10.0.0.1",
            gateway: "10.0.0.254"
        )
    }
}

final class RouteRuleTests: XCTestCase {

    func testRouteTypeHost() {
        let rule = RouteRule(destination: "10.0.0.5", interfaceName: "en1", gateway: "10.65.72.1", hardwarePort: "Wi-Fi")
        XCTAssertEqual(rule.routeType, .host)
    }

    func testRouteTypeNetwork() {
        let rule = RouteRule(destination: "192.168.1.0/24", interfaceName: "en0", gateway: "192.168.1.1", hardwarePort: "Ethernet")
        XCTAssertEqual(rule.routeType, .network)
    }

    func testRuleEquality() {
        let rule1 = RouteRule(destination: "10.0.0.5", interfaceName: "en1", gateway: "10.65.72.1", hardwarePort: "Wi-Fi")
        let rule2 = RouteRule(destination: "10.0.0.5", interfaceName: "en1", gateway: "10.65.72.1", hardwarePort: "Wi-Fi")
        // Different IDs, so not equal
        XCTAssertNotEqual(rule1, rule2)
    }

    func testRuleMatchesInterfaceByDeviceName() {
        let rule = RouteRule(
            destination: "10.0.0.5",
            interfaceName: "en1",
            gateway: "10.65.72.1",
            hardwarePort: "Wi-Fi"
        )
        let iface = NetworkInterface(
            id: "en1",
            deviceName: "en1",
            hardwarePort: "Wi-Fi",
            macAddress: "aa:bb:cc:dd:ee:ff"
        )

        XCTAssertTrue(rule.matches(interface: iface))
    }

    func testRuleDoesNotMatchDifferentInterfaceEvenWithSameGateway() {
        let rule = RouteRule(
            destination: "10.0.0.5",
            interfaceName: "en1",
            gateway: "10.65.72.1",
            hardwarePort: "Wi-Fi"
        )
        let iface = NetworkInterface(
            id: "en0",
            deviceName: "en0",
            hardwarePort: "Ethernet",
            macAddress: "aa:bb:cc:dd:ee:00",
            gateway: "10.65.72.1"
        )

        XCTAssertFalse(rule.matches(interface: iface))
    }
}

final class NetworkInterfaceTests: XCTestCase {

    func testValidRouteTarget() {
        var iface = NetworkInterface(id: "en0", deviceName: "en0", hardwarePort: "Wi-Fi", macAddress: "aa:bb:cc:dd:ee:ff")
        iface.isActive = true
        iface.ipAddress = "10.0.0.1"
        iface.gateway = "10.0.0.254"
        XCTAssertTrue(iface.isValidRouteTarget)
    }

    func testInvalidRouteTargetInactive() {
        var iface = NetworkInterface(id: "en0", deviceName: "en0", hardwarePort: "Wi-Fi", macAddress: "aa:bb:cc:dd:ee:ff")
        iface.isActive = false
        iface.ipAddress = "10.0.0.1"
        iface.gateway = "10.0.0.254"
        XCTAssertFalse(iface.isValidRouteTarget)
    }

    func testInvalidRouteTargetNoIP() {
        var iface = NetworkInterface(id: "en0", deviceName: "en0", hardwarePort: "Wi-Fi", macAddress: "aa:bb:cc:dd:ee:ff")
        iface.isActive = true
        iface.gateway = "10.0.0.254"
        XCTAssertFalse(iface.isValidRouteTarget)
    }

    func testInvalidRouteTargetNoGateway() {
        var iface = NetworkInterface(id: "en0", deviceName: "en0", hardwarePort: "Wi-Fi", macAddress: "aa:bb:cc:dd:ee:ff")
        iface.isActive = true
        iface.ipAddress = "10.0.0.1"
        XCTAssertFalse(iface.isValidRouteTarget)
    }
}

final class AppConfigTests: XCTestCase {

    func testDefaultConfig() {
        let config = AppConfig()
        XCTAssertEqual(config.version, 1)
        XCTAssertTrue(config.isActive)
        XCTAssertTrue(config.autoApplyOnLaunch)
        XCTAssertTrue(config.rules.isEmpty)
        XCTAssertFalse(config.cleanRoutesOnExit)
    }

    func testConfigCodable() throws {
        let config = AppConfig(
            isActive: false,
            autoApplyOnLaunch: false,
            rules: [
                RouteRule(destination: "10.0.0.5", interfaceName: "en1", gateway: "10.65.72.1", hardwarePort: "Wi-Fi")
            ],
            cleanRoutesOnExit: true
        )

        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(AppConfig.self, from: data)

        XCTAssertEqual(decoded.version, config.version)
        XCTAssertEqual(decoded.isActive, config.isActive)
        XCTAssertEqual(decoded.autoApplyOnLaunch, config.autoApplyOnLaunch)
        XCTAssertEqual(decoded.rules.count, config.rules.count)
        XCTAssertEqual(decoded.cleanRoutesOnExit, config.cleanRoutesOnExit)
    }

    func testConfigDecodesISO8601RuleDates() throws {
        let json = """
        {
          "autoApplyOnLaunch" : true,
          "cleanRoutesOnExit" : false,
          "isActive" : true,
          "rules" : [
            {
              "createdAt" : "2026-04-17T08:00:00Z",
              "destination" : "172.21.11.0/24",
              "gateway" : "10.65.196.1",
              "hardwarePort" : "Wi-Fi",
              "id" : "00000000-0000-0000-0000-000000000001",
              "interfaceName" : "en0",
              "isActive" : true
            }
          ],
          "version" : 1
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AppConfig.self, from: Data(json.utf8))

        XCTAssertEqual(decoded.rules.count, 1)
        XCTAssertEqual(decoded.rules.first?.destination, "172.21.11.0/24")
    }
}

@MainActor
final class RouteManagerTests: XCTestCase {

    func testActivationOnlyAppliesRulesMarkedActive() {
        let activeRule = RouteRule(
            destination: "172.16.36.34",
            interfaceName: "en0",
            gateway: "10.0.0.1",
            hardwarePort: "Wi-Fi",
            isActive: true
        )
        let skipOnLaunchRule = RouteRule(
            destination: "172.16.36.35",
            interfaceName: "en0",
            gateway: "10.0.0.1",
            hardwarePort: "Wi-Fi",
            isActive: false
        )

        let result = RouteManager.rulesToApplyOnActivation([activeRule, skipOnLaunchRule])

        XCTAssertEqual(result.map(\.destination), ["172.16.36.34"])
    }

    func testGlobalDeactivateRemovesAllStoredRulesIncludingSkipOnLaunch() {
        let activeRule = RouteRule(
            destination: "172.16.36.34",
            interfaceName: "en0",
            gateway: "10.0.0.1",
            hardwarePort: "Wi-Fi",
            isActive: true
        )
        let skipOnLaunchRule = RouteRule(
            destination: "172.16.36.35",
            interfaceName: "en0",
            gateway: "10.0.0.1",
            hardwarePort: "Wi-Fi",
            isActive: false
        )

        let result = RouteManager.rulesToRemoveOnGlobalDeactivate([activeRule, skipOnLaunchRule])

        XCTAssertEqual(result.map(\.destination), ["172.16.36.34", "172.16.36.35"])
    }

    func testIgnorableDeleteErrorForMissingRoute() {
        XCTAssertTrue(RouteManager.isIgnorableDeleteError("route: writing to routing socket: not in table"))
    }

    func testIgnorableDeleteErrorForNoSuchProcess() {
        XCTAssertTrue(RouteManager.isIgnorableDeleteError("route: No such process"))
    }

    func testDeleteErrorDoesNotIgnoreRealFailures() {
        XCTAssertFalse(RouteManager.isIgnorableDeleteError("route: permission denied"))
    }
}

@MainActor
final class MenuBarViewModelLogicTests: XCTestCase {

    func testDeletingSavedRuleSkipsSystemRemovalWhenGloballyInactive() {
        XCTAssertFalse(MenuBarViewModel.shouldRemoveSystemRouteWhenDeletingSavedRule(isGloballyActive: false))
    }

    func testDeletingSavedRuleRemovesSystemRouteWhenGloballyActive() {
        XCTAssertTrue(MenuBarViewModel.shouldRemoveSystemRouteWhenDeletingSavedRule(isGloballyActive: true))
    }
}
