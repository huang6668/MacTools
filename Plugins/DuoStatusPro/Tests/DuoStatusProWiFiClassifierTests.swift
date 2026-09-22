import CoreAudio
import IOKit.ps
import XCTest
@testable import DuoStatusProPlugin

final class DuoStatusProWiFiClassifierTests: XCTestCase {
    private func classify(
        powerOn: Bool = true,
        serviceActive: Bool = true,
        isIBSS: Bool = false,
        sharingActive: Bool = false,
        pathSatisfied: Bool? = true,
        usesWiFi: Bool = true,
        isExpensive: Bool = false
    ) -> DuoStatusProWiFiState {
        DuoStatusProWiFiClassifier.classify(
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
            DuoStatusProNetworkConnectionResolver.resolve(satisfied: false, usesWired: true, usesWiFi: true),
            .offline
        )
    }

    func testResolverPrefersWiredOverWiFi() {
        XCTAssertEqual(
            DuoStatusProNetworkConnectionResolver.resolve(satisfied: true, usesWired: true, usesWiFi: true),
            .ethernet
        )
        XCTAssertEqual(
            DuoStatusProNetworkConnectionResolver.resolve(satisfied: true, usesWired: false, usesWiFi: true),
            .wifi
        )
    }

    func testResolverFallsBackToOther() {
        XCTAssertEqual(
            DuoStatusProNetworkConnectionResolver.resolve(satisfied: true, usesWired: false, usesWiFi: false),
            .other
        )
    }

    func testPathSnapshotConnectionUsesResolver() {
        let path = DuoStatusProNetworkPathSnapshot(isSatisfied: true, usesWiFi: true, isExpensive: true)
        XCTAssertEqual(path.connection, .wifi)
        XCTAssertEqual(DuoStatusProNetworkPathSnapshot().connection, .offline)
    }

    // MARK: - Reader pure helpers

    func testBatteryParsePercentageAndPowerState() {
        let status = DuoStatusProSystemReader.battery(
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
        let status = DuoStatusProSystemReader.battery(
            from: [[kIOPSTypeKey: kIOPSUPSType]],
            isLowPowerMode: true
        )
        XCTAssertFalse(status.isPresent)
        XCTAssertNil(status.rawPercentage)
        XCTAssertTrue(status.isLowPowerMode)
        XCTAssertEqual(status.percentage, 100)
    }

    func testBatteryParseTreatsAbsentBatteryAsNotPresent() {
        let status = DuoStatusProSystemReader.battery(
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
        XCTAssertEqual(DuoStatusProSystemReader.normalizedRSSI(-61), -61)
        XCTAssertNil(DuoStatusProSystemReader.normalizedRSSI(0))
        XCTAssertNil(DuoStatusProSystemReader.normalizedRSSI(12))
    }

    func testAverageScalarSkipsNonFiniteAndClamps() {
        XCTAssertNil(DuoStatusProSystemReader.averageScalar([]))
        XCTAssertEqual(DuoStatusProSystemReader.averageScalar([0.25, 0.75]), 0.5)
        XCTAssertEqual(DuoStatusProSystemReader.averageScalar([.nan, 1.5]), 1)
    }

    func testBluetoothTransportDetection() {
        XCTAssertTrue(DuoStatusProSystemReader.isBluetoothTransport(kAudioDeviceTransportTypeBluetooth))
        XCTAssertTrue(DuoStatusProSystemReader.isBluetoothTransport(kAudioDeviceTransportTypeBluetoothLE))
        XCTAssertFalse(DuoStatusProSystemReader.isBluetoothTransport(kAudioDeviceTransportTypeBuiltIn))
        XCTAssertFalse(DuoStatusProSystemReader.isBluetoothTransport(nil))
    }
}
