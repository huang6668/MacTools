import XCTest
@testable import DuoStatusProPlugin

final class DuoStatusProIconMappingsTests: XCTestCase {
    func testWiFiBarsFollowSignalThresholds() {
        XCTAssertEqual(DuoStatusProIconMappings.wifiBars(rssi: -40), 3)
        XCTAssertEqual(DuoStatusProIconMappings.wifiBars(rssi: -60), 3)
        XCTAssertEqual(DuoStatusProIconMappings.wifiBars(rssi: -61), 2)
        XCTAssertEqual(DuoStatusProIconMappings.wifiBars(rssi: -78), 2)
        XCTAssertEqual(DuoStatusProIconMappings.wifiBars(rssi: -79), 1)
        XCTAssertEqual(DuoStatusProIconMappings.wifiBars(rssi: -88), 1)
        XCTAssertEqual(DuoStatusProIconMappings.wifiBars(rssi: -89), 0)
        XCTAssertEqual(DuoStatusProIconMappings.wifiBars(rssi: nil), 0)
    }

    func testVolumeStepsQuantizeScalarAndRespectMute() {
        XCTAssertEqual(DuoStatusProIconMappings.volumeSteps(scalar: nil, isMuted: false), 0)
        XCTAssertEqual(DuoStatusProIconMappings.volumeSteps(scalar: 0, isMuted: false), 0)
        XCTAssertEqual(DuoStatusProIconMappings.volumeSteps(scalar: 0.9, isMuted: true), 0)
        XCTAssertEqual(DuoStatusProIconMappings.volumeSteps(scalar: 0.25, isMuted: false), 1)
        XCTAssertEqual(DuoStatusProIconMappings.volumeSteps(scalar: 0.5, isMuted: false), 2)
        XCTAssertEqual(DuoStatusProIconMappings.volumeSteps(scalar: 0.75, isMuted: false), 3)
        XCTAssertEqual(DuoStatusProIconMappings.volumeSteps(scalar: 0.76, isMuted: false), 4)
        XCTAssertEqual(DuoStatusProIconMappings.volumeSteps(scalar: 1.5, isMuted: false), 4)
        XCTAssertEqual(DuoStatusProIconMappings.volumeSteps(scalar: .nan, isMuted: false), 0)
    }

    func testBatteryColorRoleOrdersCriticalBeforeLowPowerBeforeCharging() {
        let options = DuoStatusProIconOptions.default

        var battery = DuoStatusProBatteryStatus(rawPercentage: 10, isPresent: true, isCharging: true, isLowPowerMode: true)
        XCTAssertEqual(DuoStatusProIconMappings.batteryColorRole(battery, options: options), .critical)

        battery.rawPercentage = 20
        XCTAssertEqual(DuoStatusProIconMappings.batteryColorRole(battery, options: options), .lowPower)

        battery.isLowPowerMode = false
        XCTAssertEqual(DuoStatusProIconMappings.batteryColorRole(battery, options: options), .charging)

        battery.isCharging = false
        battery.isConnectedToPower = true
        XCTAssertEqual(DuoStatusProIconMappings.batteryColorRole(battery, options: options), .charging)

        battery.isConnectedToPower = false
        XCTAssertEqual(DuoStatusProIconMappings.batteryColorRole(battery, options: options), .foreground)
    }

    func testBatteryColorRoleHonorsThresholdAndColorToggle() {
        var options = DuoStatusProIconOptions.default
        options.batteryCriticalThreshold = 50
        let battery = DuoStatusProBatteryStatus(rawPercentage: 49, isPresent: true, isCharging: true)
        XCTAssertEqual(DuoStatusProIconMappings.batteryColorRole(battery, options: options), .critical)

        options.usesBatteryStatusColors = false
        XCTAssertEqual(DuoStatusProIconMappings.batteryColorRole(battery, options: options), .foreground)
    }

    func testMissingBatteryRendersAsFullNeutralRing() {
        let desktop = DuoStatusProBatteryStatus(rawPercentage: nil, isPresent: false)
        XCTAssertEqual(DuoStatusProIconMappings.batteryProgress(desktop), 1)
        XCTAssertEqual(DuoStatusProIconMappings.batteryColorRole(desktop, options: .default), .foreground)
        XCTAssertEqual(DuoStatusProIconMappings.batteryGapContent(desktop, options: .default), .empty)
    }

    func testBatteryGapContentPrefersBoltThenPlugThenPercentage() {
        var options = DuoStatusProIconOptions.default
        var battery = DuoStatusProBatteryStatus(rawPercentage: 80, isPresent: true, isCharging: true, isConnectedToPower: true)
        XCTAssertEqual(DuoStatusProIconMappings.batteryGapContent(battery, options: options), .bolt)

        battery.isCharging = false
        XCTAssertEqual(DuoStatusProIconMappings.batteryGapContent(battery, options: options), .plug)

        options.showsBatteryPercentage = true
        XCTAssertEqual(DuoStatusProIconMappings.batteryGapContent(battery, options: options), .plug)

        options.showsPercentageWhenConnected = true
        XCTAssertEqual(DuoStatusProIconMappings.batteryGapContent(battery, options: options), .percentage)

        battery.isConnectedToPower = false
        options.showsPercentageWhenConnected = false
        XCTAssertEqual(DuoStatusProIconMappings.batteryGapContent(battery, options: options), .percentage)

        options.showsBatteryPercentage = false
        XCTAssertEqual(DuoStatusProIconMappings.batteryGapContent(battery, options: options), .empty)

        options.showsChargingIndicator = false
        battery.isCharging = true
        XCTAssertEqual(DuoStatusProIconMappings.batteryGapContent(battery, options: options), .empty)
    }

    func testBluetoothGlyphReplacesNetworkIconUnlessNetworkErrorTakesPriority() {
        var options = DuoStatusProIconOptions.default
        let bluetooth = DuoStatusProVolumeStatus(scalar: 0.5, isBluetoothOutput: true)
        let wired = DuoStatusProVolumeStatus(scalar: 0.5, isBluetoothOutput: false)
        let connected = DuoStatusProWiFiStatus(state: .connected, rssi: -50)

        XCTAssertTrue(DuoStatusProIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: connected, connection: .wifi, options: options))
        XCTAssertFalse(DuoStatusProIconMappings.shouldReplaceNetworkIcon(volume: wired, wifi: connected, connection: .wifi, options: options))

        for state: DuoStatusProWiFiState in [.off, .notAssociated, .noInternet, .unavailable] {
            let wifi = DuoStatusProWiFiStatus(state: state)
            XCTAssertFalse(
                DuoStatusProIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: wifi, connection: .wifi, options: options),
                "\(state) should keep the network icon visible"
            )
        }
        for state: DuoStatusProWiFiState in [.hotspot, .temporary, .shared] {
            let wifi = DuoStatusProWiFiStatus(state: state)
            XCTAssertTrue(
                DuoStatusProIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: wifi, connection: .wifi, options: options),
                "\(state) is not an error and should yield to the Bluetooth glyph"
            )
        }
        XCTAssertFalse(DuoStatusProIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: connected, connection: .offline, options: options))

        options.bluetoothGlyphPrioritizesNetworkErrors = false
        XCTAssertTrue(DuoStatusProIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: DuoStatusProWiFiStatus(state: .off), connection: .offline, options: options))

        options.bluetoothGlyphReplacesNetworkIcon = false
        XCTAssertFalse(DuoStatusProIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: connected, connection: .wifi, options: options))
    }
}
