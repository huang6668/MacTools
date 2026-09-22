import AppKit
import CoreAudio
import Foundation
import IOKit.ps
import Network
import OSLog

// Adapted from Status Trio (https://github.com/lingyired/status-trio, Apache-2.0).
// The upstream battery, Wi-Fi, volume, and network monitors are folded into one
// coalescing monitor that mirrors `DuoSystemStatusMonitor`.

private let statusTrioMonitorLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "cc.ggbond.mactools",
    category: "DuoStatusProSystemMonitor"
)

// MARK: - Network path monitoring

@MainActor
protocol DuoStatusProNetworkPathMonitoring: AnyObject {
    var onChange: (@Sendable (DuoStatusProNetworkPathSnapshot) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func cancel()
}

@MainActor
final class DuoStatusProSystemNetworkPathMonitor: DuoStatusProNetworkPathMonitoring {
    var onChange: (@Sendable (DuoStatusProNetworkPathSnapshot) -> Void)?
    private let monitor = NWPathMonitor()

    func start(queue: DispatchQueue) {
        let onChange = onChange
        monitor.pathUpdateHandler = { path in
            onChange?(DuoStatusProNetworkPathSnapshot(
                isSatisfied: path.status == .satisfied,
                usesWiFi: path.usesInterfaceType(.wifi),
                usesWiredEthernet: path.usesInterfaceType(.wiredEthernet),
                isExpensive: path.isExpensive
            ))
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.pathUpdateHandler = nil
        monitor.cancel()
        onChange = nil
    }
}

// MARK: - Audio event monitoring

/// Delivers "something about the default output changed" on the main actor.
/// Implementations own their CoreAudio listener registrations.
@MainActor
protocol DuoStatusProAudioEventMonitoring: AnyObject {
    func start(onChange: @escaping @MainActor @Sendable () -> Void)
    /// Re-targets device listeners when the default output device moved.
    func reconcile()
    func stop()
}

@MainActor
final class DuoStatusProCoreAudioEventMonitor: DuoStatusProAudioEventMonitoring {
    private struct Registration {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    private var defaultDeviceRegistration: Registration?
    private var deviceRegistrations: [Registration] = []
    private var registeredDeviceID: AudioDeviceID?
    private var onChange: (@MainActor @Sendable () -> Void)?
    private var isRunning = false

    init() {}

    isolated deinit {
        stop()
    }

    func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        guard !isRunning else { return }
        isRunning = true
        self.onChange = onChange
        registerDefaultDeviceListener()
        reconcile()
    }

    func reconcile() {
        guard isRunning else { return }
        let currentDeviceID = DuoStatusProCoreAudio.validDefaultOutputDevice()
        guard currentDeviceID != registeredDeviceID || deviceRegistrations.isEmpty else { return }
        removeDeviceListeners()
        registeredDeviceID = currentDeviceID
        if let currentDeviceID {
            registerDeviceListeners(for: currentDeviceID)
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let defaultDeviceRegistration {
            remove(defaultDeviceRegistration)
            self.defaultDeviceRegistration = nil
        }
        removeDeviceListeners()
        registeredDeviceID = nil
        onChange = nil
    }

    private func registerDefaultDeviceListener() {
        guard defaultDeviceRegistration == nil else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.defaultDeviceDidChange()
            }
        }
        let address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        defaultDeviceRegistration = add(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            address: address,
            block: block
        )
    }

    private func registerDeviceListeners(for deviceID: AudioDeviceID) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.volumeDidChange()
            }
        }
        for element in DuoStatusProCoreAudio.outputElements {
            for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
                guard DuoStatusProCoreAudio.hasProperty(
                    objectID: deviceID,
                    selector: selector,
                    scope: kAudioObjectPropertyScopeOutput,
                    element: element
                ) else { continue }
                let address = AudioObjectPropertyAddress(
                    mSelector: selector,
                    mScope: kAudioObjectPropertyScopeOutput,
                    mElement: element
                )
                if let registration = add(objectID: deviceID, address: address, block: block) {
                    deviceRegistrations.append(registration)
                }
            }
        }
    }

    private func defaultDeviceDidChange() {
        guard isRunning else { return }
        reconcile()
        onChange?()
    }

    private func volumeDidChange() {
        guard isRunning else { return }
        onChange?()
    }

    private func add(
        objectID: AudioObjectID,
        address: AudioObjectPropertyAddress,
        block: @escaping AudioObjectPropertyListenerBlock
    ) -> Registration? {
        var mutableAddress = address
        let status = AudioObjectAddPropertyListenerBlock(objectID, &mutableAddress, .main, block)
        guard status == noErr else {
            statusTrioMonitorLogger.error(
                "Failed to add CoreAudio listener selector=\(address.mSelector, privacy: .public) element=\(address.mElement, privacy: .public) status=\(status, privacy: .public)"
            )
            return nil
        }
        return Registration(objectID: objectID, address: address, block: block)
    }

    private func removeDeviceListeners() {
        for registration in deviceRegistrations {
            remove(registration)
        }
        deviceRegistrations.removeAll()
    }

    private func remove(_ registration: Registration) {
        var address = registration.address
        let status = AudioObjectRemovePropertyListenerBlock(
            registration.objectID,
            &address,
            .main,
            registration.block
        )
        if status != noErr {
            statusTrioMonitorLogger.error(
                "Failed to remove CoreAudio listener selector=\(address.mSelector, privacy: .public) element=\(address.mElement, privacy: .public) status=\(status, privacy: .public)"
            )
        }
    }
}

// MARK: - Monitor

@MainActor
protocol DuoStatusProMonitoring: AnyObject {
    var snapshot: DuoStatusProSnapshot { get }
    var onChange: ((DuoStatusProSnapshot) -> Void)? { get set }
    func start()
    func stop()
    func refresh()
}

@MainActor
final class DuoStatusProSystemMonitor: DuoStatusProMonitoring {
    typealias NotificationSourceFactory = (UnsafeMutableRawPointer) -> CFRunLoopSource?

    /// Which system reads a refresh performs. Events only re-read what they
    /// can have changed; the periodic timer and wake re-read everything.
    struct RefreshScope: OptionSet, Sendable {
        let rawValue: UInt8
        static let battery = RefreshScope(rawValue: 1 << 0)
        static let wifi = RefreshScope(rawValue: 1 << 1)
        static let volume = RefreshScope(rawValue: 1 << 2)
        static let all: RefreshScope = [.battery, .wifi, .volume]
    }

    private struct Reading: Sendable {
        var battery: DuoStatusProBatteryStatus?
        var wifi: DuoStatusProWiFiStatus?
        var volume: DuoStatusProVolumeStatus?
    }

    private(set) var snapshot: DuoStatusProSnapshot = .unknown
    var onChange: ((DuoStatusProSnapshot) -> Void)?

    private let reader: any DuoStatusProSystemReading
    private let networkMonitorFactory: @MainActor () -> any DuoStatusProNetworkPathMonitoring
    private let audioEventMonitorFactory: @MainActor () -> any DuoStatusProAudioEventMonitoring
    private let notificationSourceFactory: NotificationSourceFactory
    private let workspaceNotificationCenter: NotificationCenter
    private let processInfoNotificationCenter: NotificationCenter
    private let refreshInterval: TimeInterval
    private let queue = DispatchQueue(label: "com.mactools.duo-status-pro", qos: .utility)

    private var networkMonitor: (any DuoStatusProNetworkPathMonitoring)?
    private var audioEventMonitor: (any DuoStatusProAudioEventMonitoring)?
    private var powerSource: CFRunLoopSource?
    private var wakeObserver: NSObjectProtocol?
    private var powerStateObserver: NSObjectProtocol?
    private var timer: Timer?
    private var latestPath: DuoStatusProNetworkPathSnapshot?
    private var isRunning = false
    private var generation: UInt64 = 0
    private var isReading = false
    private var pendingScope: RefreshScope = []

    init(
        reader: any DuoStatusProSystemReading = DuoStatusProSystemReader(),
        networkMonitorFactory: @escaping @MainActor () -> any DuoStatusProNetworkPathMonitoring = {
            DuoStatusProSystemNetworkPathMonitor()
        },
        audioEventMonitorFactory: @escaping @MainActor () -> any DuoStatusProAudioEventMonitoring = {
            DuoStatusProCoreAudioEventMonitor()
        },
        notificationSourceFactory: @escaping NotificationSourceFactory = { context in
            IOPSNotificationCreateRunLoopSource({ context in
                guard let context else { return }
                let monitor = Unmanaged<DuoStatusProSystemMonitor>
                    .fromOpaque(context)
                    .takeUnretainedValue()
                Task { @MainActor in monitor.refresh(.battery) }
            }, context)?.takeRetainedValue()
        },
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        processInfoNotificationCenter: NotificationCenter = .default,
        refreshInterval: TimeInterval = 15
    ) {
        self.reader = reader
        self.networkMonitorFactory = networkMonitorFactory
        self.audioEventMonitorFactory = audioEventMonitorFactory
        self.notificationSourceFactory = notificationSourceFactory
        self.workspaceNotificationCenter = workspaceNotificationCenter
        self.processInfoNotificationCenter = processInfoNotificationCenter
        self.refreshInterval = max(refreshInterval, 1)
    }

    isolated deinit {
        stop()
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        generation &+= 1
        let currentGeneration = generation
        latestPath = nil
        publish(.unknown)

        let networkMonitor = networkMonitorFactory()
        self.networkMonitor = networkMonitor
        networkMonitor.onChange = { [weak self] path in
            Task { @MainActor in
                guard let self, self.isRunning, self.generation == currentGeneration else { return }
                self.latestPath = path
                var updated = self.snapshot
                updated.connection = path.connection
                self.publish(updated)
                // Wi-Fi classification depends on the path (hotspot / no internet).
                self.refresh(.wifi)
            }
        }
        networkMonitor.start(queue: queue)

        let audioEventMonitor = audioEventMonitorFactory()
        self.audioEventMonitor = audioEventMonitor
        audioEventMonitor.start { [weak self] in
            guard let self, self.isRunning, self.generation == currentGeneration else { return }
            self.refresh(.volume)
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = notificationSourceFactory(context) {
            powerSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        } else {
            statusTrioMonitorLogger.error("IOPS notification source unavailable; timer refresh remains active")
        }

        powerStateObserver = processInfoNotificationCenter.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.refresh(.battery)
            }
        }
        wakeObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.audioEventMonitor?.reconcile()
                self.refresh()
            }
        }

        let timer = Timer(timeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.generation == currentGeneration else { return }
                self.refresh()
            }
        }
        timer.tolerance = min(refreshInterval / 5, 3)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        refresh()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        generation &+= 1
        timer?.invalidate()
        timer = nil
        if let wakeObserver {
            workspaceNotificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        if let powerStateObserver {
            processInfoNotificationCenter.removeObserver(powerStateObserver)
        }
        powerStateObserver = nil
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .commonModes)
            CFRunLoopSourceInvalidate(powerSource)
        }
        powerSource = nil
        audioEventMonitor?.stop()
        audioEventMonitor = nil
        networkMonitor?.cancel()
        networkMonitor = nil
        latestPath = nil
        isReading = false
        pendingScope = []
    }

    func refresh() {
        refresh(.all)
    }

    /// Reads the requested subsystems off the main actor and merges the result.
    /// While a read is in flight the scope accumulates into a single follow-up.
    func refresh(_ scope: RefreshScope) {
        guard isRunning, !scope.isEmpty else { return }
        guard !isReading else {
            pendingScope.formUnion(scope)
            return
        }
        isReading = true
        let currentGeneration = generation
        let reader = reader
        let path = latestPath
        queue.async { [weak self] in
            var reading = Reading()
            if scope.contains(.battery) { reading.battery = reader.readBattery() }
            if scope.contains(.wifi) { reading.wifi = reader.readWiFi(path: path) }
            if scope.contains(.volume) { reading.volume = reader.readVolume() }
            Task { @MainActor in
                guard let self, self.isRunning, self.generation == currentGeneration else { return }
                self.isReading = false
                var updated = self.snapshot
                if let battery = reading.battery { updated.battery = battery }
                if let wifi = reading.wifi { updated.wifi = wifi }
                if let volume = reading.volume { updated.volume = volume }
                self.publish(updated)
                if !self.pendingScope.isEmpty {
                    let pending = self.pendingScope
                    self.pendingScope = []
                    self.refresh(pending)
                }
            }
        }
    }

    private func publish(_ updated: DuoStatusProSnapshot) {
        guard updated != snapshot else { return }
        snapshot = updated
        onChange?(updated)
    }
}
