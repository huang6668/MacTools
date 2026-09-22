import XCTest
@testable import StatusTrioPlugin

final class StatusTrioIconMappingsTests: XCTestCase {
    func testWiFiBarsFollowSignalThresholds() {
        XCTAssertEqual(StatusTrioIconMappings.wifiBars(rssi: -40), 3)
        XCTAssertEqual(StatusTrioIconMappings.wifiBars(rssi: -60), 3)
        XCTAssertEqual(StatusTrioIconMappings.wifiBars(rssi: -61), 2)
        XCTAssertEqual(StatusTrioIconMappings.wifiBars(rssi: -78), 2)
        XCTAssertEqual(StatusTrioIconMappings.wifiBars(rssi: -79), 1)
        XCTAssertEqual(StatusTrioIconMappings.wifiBars(rssi: -88), 1)
        XCTAssertEqual(StatusTrioIconMappings.wifiBars(rssi: -89), 0)
        XCTAssertEqual(StatusTrioIconMappings.wifiBars(rssi: nil), 0)
    }

    func testVolumeStepsQuantizeScalarAndRespectMute() {
        XCTAssertEqual(StatusTrioIconMappings.volumeSteps(scalar: nil, isMuted: false), 0)
        XCTAssertEqual(StatusTrioIconMappings.volumeSteps(scalar: 0, isMuted: false), 0)
        XCTAssertEqual(StatusTrioIconMappings.volumeSteps(scalar: 0.9, isMuted: true), 0)
        XCTAssertEqual(StatusTrioIconMappings.volumeSteps(scalar: 0.25, isMuted: false), 1)
        XCTAssertEqual(StatusTrioIconMappings.volumeSteps(scalar: 0.5, isMuted: false), 2)
        XCTAssertEqual(StatusTrioIconMappings.volumeSteps(scalar: 0.75, isMuted: false), 3)
        XCTAssertEqual(StatusTrioIconMappings.volumeSteps(scalar: 0.76, isMuted: false), 4)
        XCTAssertEqual(StatusTrioIconMappings.volumeSteps(scalar: 1.5, isMuted: false), 4)
        XCTAssertEqual(StatusTrioIconMappings.volumeSteps(scalar: .nan, isMuted: false), 0)
    }

    func testBatteryColorRoleOrdersCriticalBeforeLowPowerBeforeCharging() {
        let options = StatusTrioIconOptions.default

        var battery = StatusTrioBatteryStatus(rawPercentage: 10, isPresent: true, isCharging: true, isLowPowerMode: true)
        XCTAssertEqual(StatusTrioIconMappings.batteryColorRole(battery, options: options), .critical)

        battery.rawPercentage = 20
        XCTAssertEqual(StatusTrioIconMappings.batteryColorRole(battery, options: options), .lowPower)

        battery.isLowPowerMode = false
        XCTAssertEqual(StatusTrioIconMappings.batteryColorRole(battery, options: options), .charging)

        battery.isCharging = false
        battery.isConnectedToPower = true
        XCTAssertEqual(StatusTrioIconMappings.batteryColorRole(battery, options: options), .charging)

        battery.isConnectedToPower = false
        XCTAssertEqual(StatusTrioIconMappings.batteryColorRole(battery, options: options), .foreground)
    }

    func testBatteryColorRoleHonorsThresholdAndColorToggle() {
        var options = StatusTrioIconOptions.default
        options.batteryCriticalThreshold = 50
        let battery = StatusTrioBatteryStatus(rawPercentage: 49, isPresent: true, isCharging: true)
        XCTAssertEqual(StatusTrioIconMappings.batteryColorRole(battery, options: options), .critical)

        options.usesBatteryStatusColors = false
        XCTAssertEqual(StatusTrioIconMappings.batteryColorRole(battery, options: options), .foreground)
    }

    func testMissingBatteryRendersAsFullNeutralRing() {
        let desktop = StatusTrioBatteryStatus(rawPercentage: nil, isPresent: false)
        XCTAssertEqual(StatusTrioIconMappings.batteryProgress(desktop), 1)
        XCTAssertEqual(StatusTrioIconMappings.batteryColorRole(desktop, options: .default), .foreground)
        XCTAssertEqual(StatusTrioIconMappings.batteryGapContent(desktop, options: .default), .empty)
    }

    func testBatteryGapContentPrefersBoltThenPlugThenPercentage() {
        var options = StatusTrioIconOptions.default
        var battery = StatusTrioBatteryStatus(rawPercentage: 80, isPresent: true, isCharging: true, isConnectedToPower: true)
        XCTAssertEqual(StatusTrioIconMappings.batteryGapContent(battery, options: options), .bolt)

        battery.isCharging = false
        XCTAssertEqual(StatusTrioIconMappings.batteryGapContent(battery, options: options), .plug)

        options.showsBatteryPercentage = true
        XCTAssertEqual(StatusTrioIconMappings.batteryGapContent(battery, options: options), .plug)

        options.showsPercentageWhenConnected = true
        XCTAssertEqual(StatusTrioIconMappings.batteryGapContent(battery, options: options), .percentage)

        battery.isConnectedToPower = false
        options.showsPercentageWhenConnected = false
        XCTAssertEqual(StatusTrioIconMappings.batteryGapContent(battery, options: options), .percentage)

        options.showsBatteryPercentage = false
        XCTAssertEqual(StatusTrioIconMappings.batteryGapContent(battery, options: options), .empty)

        options.showsChargingIndicator = false
        battery.isCharging = true
        XCTAssertEqual(StatusTrioIconMappings.batteryGapContent(battery, options: options), .empty)
    }

    func testBluetoothGlyphReplacesNetworkIconUnlessNetworkErrorTakesPriority() {
        var options = StatusTrioIconOptions.default
        let bluetooth = StatusTrioVolumeStatus(scalar: 0.5, isBluetoothOutput: true)
        let wired = StatusTrioVolumeStatus(scalar: 0.5, isBluetoothOutput: false)
        let connected = StatusTrioWiFiStatus(state: .connected, rssi: -50)

        XCTAssertTrue(StatusTrioIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: connected, connection: .wifi, options: options))
        XCTAssertFalse(StatusTrioIconMappings.shouldReplaceNetworkIcon(volume: wired, wifi: connected, connection: .wifi, options: options))

        for state: StatusTrioWiFiState in [.off, .notAssociated, .noInternet, .unavailable] {
            let wifi = StatusTrioWiFiStatus(state: state)
            XCTAssertFalse(
                StatusTrioIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: wifi, connection: .wifi, options: options),
                "\(state) should keep the network icon visible"
            )
        }
        for state: StatusTrioWiFiState in [.hotspot, .temporary, .shared] {
            let wifi = StatusTrioWiFiStatus(state: state)
            XCTAssertTrue(
                StatusTrioIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: wifi, connection: .wifi, options: options),
                "\(state) is not an error and should yield to the Bluetooth glyph"
            )
        }
        XCTAssertFalse(StatusTrioIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: connected, connection: .offline, options: options))

        options.bluetoothGlyphPrioritizesNetworkErrors = false
        XCTAssertTrue(StatusTrioIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: StatusTrioWiFiStatus(state: .off), connection: .offline, options: options))

        options.bluetoothGlyphReplacesNetworkIcon = false
        XCTAssertFalse(StatusTrioIconMappings.shouldReplaceNetworkIcon(volume: bluetooth, wifi: connected, connection: .wifi, options: options))
    }
}
