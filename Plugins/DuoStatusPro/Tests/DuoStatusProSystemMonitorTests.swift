import AppKit
import Foundation
import XCTest
@testable import DuoStatusProPlugin

final class DuoStatusProSystemMonitorTests: XCTestCase {
    @MainActor
    func testStartReadsOffMainActorAndPublishesOnce() async {
        let reader = DuoStatusProFakeReader(
            battery: DuoStatusProBatteryStatus(rawPercentage: 64, isPresent: true),
            wifi: DuoStatusProWiFiStatus(state: .connected, rssi: -58),
            volume: DuoStatusProVolumeStatus(scalar: 0.5, isMuted: false, isBluetoothOutput: true)
        )
        let fixture = Fixture(reader: reader)
        var published: [DuoStatusProSnapshot] = []
        fixture.monitor.onChange = { published.append($0) }

        fixture.monitor.start()
        fixture.monitor.start()
        XCTAssertEqual(fixture.network.startCount, 1)
        XCTAssertEqual(fixture.audio.startCount, 1)

        await waitUntil { fixture.monitor.snapshot.battery.rawPercentage == 64 }
        XCTAssertEqual(published.count, 1)
        XCTAssertEqual(fixture.monitor.snapshot.wifi, DuoStatusProWiFiStatus(state: .connected, rssi: -58))
        XCTAssertEqual(fixture.monitor.snapshot.volume.scalar, 0.5)
        XCTAssertTrue(fixture.monitor.snapshot.volume.isBluetoothOutput)
        XCTAssertFalse(reader.ranOnMainThread)

        fixture.monitor.refresh()
        await waitUntil { reader.batteryReadCount >= 2 }
        await Task.yield()
        XCTAssertEqual(published.count, 1, "identical reading must not re-publish")
        fixture.monitor.stop()
    }

    @MainActor
    func testPathUpdatePublishesConnectionAndRereadsWiFi() async {
        let reader = DuoStatusProFakeReader(wifi: DuoStatusProWiFiStatus(state: .connected, rssi: -60))
        let fixture = Fixture(reader: reader)
        fixture.monitor.start()
        await waitUntil { fixture.monitor.snapshot.wifi.state == .connected }
        let wifiReadsBeforePath = reader.wifiReadCount

        let path = DuoStatusProNetworkPathSnapshot(isSatisfied: true, usesWiFi: true, isExpensive: true)
        reader.wifi = DuoStatusProWiFiStatus(state: .hotspot, rssi: -60)
        fixture.network.onChange?(path)

        await waitUntil { fixture.monitor.snapshot.connection == .wifi }
        await waitUntil { fixture.monitor.snapshot.wifi.state == .hotspot }
        XCTAssertGreaterThan(reader.wifiReadCount, wifiReadsBeforePath)
        XCTAssertEqual(reader.lastWiFiPath, path)

        fixture.network.onChange?(DuoStatusProNetworkPathSnapshot(isSatisfied: false))
        await waitUntil { fixture.monitor.snapshot.connection == .offline }
        fixture.monitor.stop()
    }

    @MainActor
    func testAudioEventOnlyRereadsVolume() async {
        let reader = DuoStatusProFakeReader(volume: DuoStatusProVolumeStatus(scalar: 0.2))
        let fixture = Fixture(reader: reader)
        fixture.monitor.start()
        await waitUntil { fixture.monitor.snapshot.volume.scalar == 0.2 }
        let batteryReads = reader.batteryReadCount
        let wifiReads = reader.wifiReadCount

        reader.volume = DuoStatusProVolumeStatus(scalar: 0.9, isMuted: true)
        fixture.audio.onChange?()

        await waitUntil { fixture.monitor.snapshot.volume.isMuted }
        XCTAssertEqual(fixture.monitor.snapshot.volume.scalar, 0.9)
        XCTAssertEqual(reader.batteryReadCount, batteryReads)
        XCTAssertEqual(reader.wifiReadCount, wifiReads)
        fixture.monitor.stop()
    }

    @MainActor
    func testStopRemovesSourcesAndIgnoresLateCallbacks() async throws {
        var context = CFRunLoopSourceContext()
        let source = try XCTUnwrap(CFRunLoopSourceCreate(nil, 0, &context))
        let reader = DuoStatusProFakeReader(battery: DuoStatusProBatteryStatus(rawPercentage: 30, isPresent: true))
        let fixture = Fixture(reader: reader, powerSource: source)
        var published: [DuoStatusProSnapshot] = []
        fixture.monitor.onChange = { published.append($0) }

        fixture.monitor.start()
        await waitUntil { fixture.monitor.snapshot.battery.rawPercentage == 30 }
        XCTAssertTrue(CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes))
        let publishedBeforeStop = published.count
        let oldNetworkCallback = fixture.network.onChange
        let oldAudioCallback = fixture.audio.onChange

        fixture.monitor.stop()
        fixture.monitor.stop()
        XCTAssertEqual(fixture.network.cancelCount, 1)
        XCTAssertEqual(fixture.audio.stopCount, 1)
        XCTAssertFalse(CFRunLoopContainsSource(CFRunLoopGetMain(), source, .commonModes))
        XCTAssertFalse(CFRunLoopSourceIsValid(source))

        let readsAfterStop = reader.readCount
        fixture.monitor.refresh()
        oldNetworkCallback?(DuoStatusProNetworkPathSnapshot(isSatisfied: true, usesWiredEthernet: true))
        oldAudioCallback?()
        fixture.workspaceCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
        fixture.processInfoCenter.post(name: .NSProcessInfoPowerStateDidChange, object: nil)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(reader.readCount, readsAfterStop)
        XCTAssertEqual(published.count, publishedBeforeStop)
        XCTAssertEqual(fixture.monitor.snapshot.connection, .unknown)
    }

    @MainActor
    func testStopDiscardsInFlightReadingAndRestartReadsFresh() async {
        let reader = DuoStatusProBlockingReader()
        let fixture = Fixture(reader: reader)
        var publishedLevels: [Int] = []
        fixture.monitor.onChange = { snapshot in
            if let level = snapshot.battery.rawPercentage {
                publishedLevels.append(level)
            }
        }

        fixture.monitor.start()
        await waitUntil { reader.hasStarted }
        fixture.monitor.stop()
        fixture.monitor.start()
        reader.release()

        await waitUntil { fixture.monitor.snapshot.battery.rawPercentage == 90 }
        XCTAssertEqual(publishedLevels, [90])
        fixture.monitor.stop()
    }

    @MainActor
    func testDeinitStopsMonitors() async {
        let network = DuoStatusProNetworkPathMonitorFake()
        let audio = DuoStatusProAudioEventMonitorFake()
        let reader = DuoStatusProFakeReader(battery: DuoStatusProBatteryStatus(rawPercentage: 55, isPresent: true))
        var monitor: DuoStatusProSystemMonitor? = DuoStatusProSystemMonitor(
            reader: reader,
            networkMonitorFactory: { network },
            audioEventMonitorFactory: { audio },
            notificationSourceFactory: { _ in nil },
            workspaceNotificationCenter: NotificationCenter(),
            processInfoNotificationCenter: NotificationCenter()
        )
        weak var weakMonitor = monitor
        monitor?.start()
        await waitUntil { monitor?.snapshot.battery.rawPercentage == 55 }

        monitor = nil

        XCTAssertNil(weakMonitor)
        XCTAssertEqual(network.cancelCount, 1)
        XCTAssertEqual(audio.stopCount, 1)
    }

    // MARK: - Helpers

    @MainActor
    private struct Fixture {
        let monitor: DuoStatusProSystemMonitor
        let network: DuoStatusProNetworkPathMonitorFake
        let audio: DuoStatusProAudioEventMonitorFake
        let workspaceCenter: NotificationCenter
        let processInfoCenter: NotificationCenter

        init(reader: any DuoStatusProSystemReading, powerSource: CFRunLoopSource? = nil) {
            let network = DuoStatusProNetworkPathMonitorFake()
            let audio = DuoStatusProAudioEventMonitorFake()
            let workspaceCenter = NotificationCenter()
            let processInfoCenter = NotificationCenter()
            self.network = network
            self.audio = audio
            self.workspaceCenter = workspaceCenter
            self.processInfoCenter = processInfoCenter
            monitor = DuoStatusProSystemMonitor(
                reader: reader,
                networkMonitorFactory: { network },
                audioEventMonitorFactory: { audio },
                notificationSourceFactory: { _ in powerSource },
                workspaceNotificationCenter: workspaceCenter,
                processInfoNotificationCenter: processInfoCenter,
                refreshInterval: 60
            )
        }
    }

    @MainActor
    private func waitUntil(
        _ condition: @MainActor () -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while !condition(), clock.now < deadline {
            await Task.yield()
        }
        XCTAssertTrue(condition(), file: file, line: line)
    }
}

// MARK: - Fakes

@MainActor
private final class DuoStatusProNetworkPathMonitorFake: DuoStatusProNetworkPathMonitoring {
    var onChange: (@Sendable (DuoStatusProNetworkPathSnapshot) -> Void)?
    private(set) var startCount = 0
    private(set) var cancelCount = 0

    func start(queue _: DispatchQueue) {
        startCount += 1
    }

    func cancel() {
        cancelCount += 1
        onChange = nil
    }
}

@MainActor
private final class DuoStatusProAudioEventMonitorFake: DuoStatusProAudioEventMonitoring {
    private(set) var onChange: (@MainActor @Sendable () -> Void)?
    private(set) var startCount = 0
    private(set) var reconcileCount = 0
    private(set) var stopCount = 0

    func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        startCount += 1
        self.onChange = onChange
    }

    func reconcile() {
        reconcileCount += 1
    }

    func stop() {
        stopCount += 1
        onChange = nil
    }
}

private final class DuoStatusProFakeReader: DuoStatusProSystemReading, @unchecked Sendable {
    private let lock = NSLock()
    private var storedBattery: DuoStatusProBatteryStatus
    private var storedWiFi: DuoStatusProWiFiStatus
    private var storedVolume: DuoStatusProVolumeStatus
    private var batteryReads = 0
    private var wifiReads = 0
    private var volumeReads = 0
    private var wasOnMainThread = false
    private var storedLastWiFiPath: DuoStatusProNetworkPathSnapshot?

    init(
        battery: DuoStatusProBatteryStatus = .unknown,
        wifi: DuoStatusProWiFiStatus = .unknown,
        volume: DuoStatusProVolumeStatus = .unknown
    ) {
        storedBattery = battery
        storedWiFi = wifi
        storedVolume = volume
    }

    var battery: DuoStatusProBatteryStatus {
        get { lock.withLock { storedBattery } }
        set { lock.withLock { storedBattery = newValue } }
    }

    var wifi: DuoStatusProWiFiStatus {
        get { lock.withLock { storedWiFi } }
        set { lock.withLock { storedWiFi = newValue } }
    }

    var volume: DuoStatusProVolumeStatus {
        get { lock.withLock { storedVolume } }
        set { lock.withLock { storedVolume = newValue } }
    }

    var batteryReadCount: Int { lock.withLock { batteryReads } }
    var wifiReadCount: Int { lock.withLock { wifiReads } }
    var volumeReadCount: Int { lock.withLock { volumeReads } }
    var readCount: Int { lock.withLock { batteryReads + wifiReads + volumeReads } }
    var ranOnMainThread: Bool { lock.withLock { wasOnMainThread } }
    var lastWiFiPath: DuoStatusProNetworkPathSnapshot? { lock.withLock { storedLastWiFiPath } }

    func readBattery() -> DuoStatusProBatteryStatus {
        lock.withLock {
            batteryReads += 1
            wasOnMainThread = wasOnMainThread || Thread.isMainThread
            return storedBattery
        }
    }

    func readWiFi(path: DuoStatusProNetworkPathSnapshot?) -> DuoStatusProWiFiStatus {
        lock.withLock {
            wifiReads += 1
            storedLastWiFiPath = path
            wasOnMainThread = wasOnMainThread || Thread.isMainThread
            return storedWiFi
        }
    }

    func readVolume() -> DuoStatusProVolumeStatus {
        lock.withLock {
            volumeReads += 1
            wasOnMainThread = wasOnMainThread || Thread.isMainThread
            return storedVolume
        }
    }
}

/// Blocks the first battery read until released so a stop/start cycle can be
/// exercised while a read is in flight.
private final class DuoStatusProBlockingReader: DuoStatusProSystemReading, @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var readCount = 0

    var hasStarted: Bool { lock.withLock { readCount > 0 } }

    func readBattery() -> DuoStatusProBatteryStatus {
        let count = lock.withLock {
            readCount += 1
            return readCount
        }
        if count == 1 {
            _ = semaphore.wait(timeout: .now() + 5)
        }
        return DuoStatusProBatteryStatus(rawPercentage: count == 1 ? 10 : 90, isPresent: true)
    }

    func readWiFi(path _: DuoStatusProNetworkPathSnapshot?) -> DuoStatusProWiFiStatus {
        DuoStatusProWiFiStatus(state: .connected, rssi: -50)
    }

    func readVolume() -> DuoStatusProVolumeStatus {
        DuoStatusProVolumeStatus(scalar: 0.5)
    }

    func release() {
        semaphore.signal()
    }
}
