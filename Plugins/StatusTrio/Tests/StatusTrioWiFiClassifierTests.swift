import CoreAudio
import IOKit.ps
import XCTest
@testable import StatusTrioPlugin

final class StatusTrioWiFiClassifierTests: XCTestCase {
    private func classify(
        powerOn: Bool = true,
        serviceActive: Bool = true,
        isIBSS: Bool = false,
        sharingActive: Bool = false,
        pathSatisfied: Bool? = true,
        usesWiFi: Bool = true,
        isExpensive: Bool = false
    ) -> StatusTrioWiFiState {
        StatusTrioWiFiClassifier.classify(
            powerOn: powerOn,
            serviceActive: serviceActive,
            isIBSS: isIBSS,
            sharingActive: sharingActive,
            pathSatisfied: pathSatisfied,
            usesWiFi: usesWiFi,
            isExpensive: isExpensive
        )
    }

    func testOffBeatsEveryOtherSignal() {
        XCTAssertEqual(
            classify(
                powerOn: false,
                serviceActive: true,
                isIBSS: true,
                sharingActive: true,
                pathSatisfied: false,
                isExpensive: true
            ),
            .off
        )
    }

    func testNotAssociatedBeatsSharingAndPath() {
        XCTAssertEqual(
            classify(serviceActive: false, isIBSS: true, sharingActive: true, pathSatisfied: false),
            .notAssociated
        )
    }

    func testSharedBeatsTemporaryAndPath() {
        XCTAssertEqual(classify(isIBSS: true, sharingActive: true, pathSatisfied: false), .shared)
    }

    func testTemporaryBeatsPath() {
        XCTAssertEqual(classify(isIBSS: true, pathSatisfied: false, isExpensive: true), .temporary)
    }

    func testHotspotWhenSatisfiedExpensiveWiFi() {
        XCTAssertEqual(classify(pathSatisfied: true, usesWiFi: true, isExpensive: true), .hotspot)
    }

    func testExpensivePathOverAnotherInterfaceIsNotHotspot() {
        XCTAssertEqual(classify(pathSatisfied: true, usesWiFi: false, isExpensive: true), .connected)
    }

    func testNoInternetWhenPathUnsatisfied() {
        XCTAssertEqual(classify(pathSatisfied: false, isExpensive: true), .noInternet)
    }

    func testUnknownPathDefaultsToConnected() {
        XCTAssertEqual(classify(pathSatisfied: nil, usesWiFi: false, isExpensive: true), .connected)
    }

    func testConnectedByDefault() {
        XCTAssertEqual(classify(), .connected)
    }

    // MARK: - Connection resolver

    func testResolverOfflineWhenUnsatisfied() {
        XCTAssertEqual(
            StatusTrioNetworkConnectionResolver.resolve(satisfied: false, usesWired: true, usesWiFi: true),
            .offline
        )
    }

    func testResolverPrefersWiredOverWiFi() {
        XCTAssertEqual(
            StatusTrioNetworkConnectionResolver.resolve(satisfied: true, usesWired: true, usesWiFi: true),
            .ethernet
        )
        XCTAssertEqual(
            StatusTrioNetworkConnectionResolver.resolve(satisfied: true, usesWired: false, usesWiFi: true),
            .wifi
        )
    }

    func testResolverFallsBackToOther() {
        XCTAssertEqual(
            StatusTrioNetworkConnectionResolver.resolve(satisfied: true, usesWired: false, usesWiFi: false),
            .other
        )
    }

    func testPathSnapshotConnectionUsesResolver() {
        let path = StatusTrioNetworkPathSnapshot(isSatisfied: true, usesWiFi: true, isExpensive: true)
        XCTAssertEqual(path.connection, .wifi)
        XCTAssertEqual(StatusTrioNetworkPathSnapshot().connection, .offline)
    }

    // MARK: - Reader pure helpers

    func testBatteryParsePercentageAndPowerState() {
        let status = StatusTrioSystemReader.battery(
            from: [[
                kIOPSTypeKey: kIOPSInternalBatteryType,
                kIOPSIsPresentKey: true,
                kIOPSCurrentCapacityKey: 4_100,
                kIOPSMaxCapacityKey: 5_000,
                kIOPSIsChargingKey: true,
                kIOPSPowerSourceStateKey: kIOPSACPowerValue
            ]],
            isLowPowerMode: true
        )
        XCTAssertEqual(status.rawPercentage, 82)
        XCTAssertTrue(status.isPresent)
        XCTAssertTrue(status.isCharging)
        XCTAssertTrue(status.isConnectedToPower)
        XCTAssertTrue(status.isLowPowerMode)
    }

    func testBatteryParseWithoutInternalBatteryKeepsLowPowerFlag() {
        let status = StatusTrioSystemReader.battery(
            from: [[kIOPSTypeKey: kIOPSUPSType]],
            isLowPowerMode: true
        )
        XCTAssertFalse(status.isPresent)
        XCTAssertNil(status.rawPercentage)
        XCTAssertTrue(status.isLowPowerMode)
        XCTAssertEqual(status.percentage, 100)
    }

    func testBatteryParseTreatsAbsentBatteryAsNotPresent() {
        let status = StatusTrioSystemReader.battery(
            from: [[
                kIOPSTypeKey: kIOPSInternalBatteryType,
                kIOPSIsPresentKey: false,
                kIOPSCurrentCapacityKey: 50,
                kIOPSMaxCapacityKey: 100
            ]],
            isLowPowerMode: false
        )
        XCTAssertFalse(status.isPresent)
        XCTAssertNil(status.rawPercentage)
    }

    func testRSSIOnlyAcceptsNegativeReadings() {
        XCTAssertEqual(StatusTrioSystemReader.normalizedRSSI(-61), -61)
        XCTAssertNil(StatusTrioSystemReader.normalizedRSSI(0))
        XCTAssertNil(StatusTrioSystemReader.normalizedRSSI(12))
    }

    func testAverageScalarSkipsNonFiniteAndClamps() {
        XCTAssertNil(StatusTrioSystemReader.averageScalar([]))
        XCTAssertEqual(StatusTrioSystemReader.averageScalar([0.25, 0.75]), 0.5)
        XCTAssertEqual(StatusTrioSystemReader.averageScalar([.nan, 1.5]), 1)
    }

    func testBluetoothTransportDetection() {
        XCTAssertTrue(StatusTrioSystemReader.isBluetoothTransport(kAudioDeviceTransportTypeBluetooth))
        XCTAssertTrue(StatusTrioSystemReader.isBluetoothTransport(kAudioDeviceTransportTypeBluetoothLE))
        XCTAssertFalse(StatusTrioSystemReader.isBluetoothTransport(kAudioDeviceTransportTypeBuiltIn))
        XCTAssertFalse(StatusTrioSystemReader.isBluetoothTransport(nil))
    }
}
