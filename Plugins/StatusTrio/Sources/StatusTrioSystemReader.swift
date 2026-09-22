import CoreAudio
import CoreWLAN
import Foundation
import IOKit.ps
import OSLog
import SystemConfiguration

// Adapted from Status Trio (https://github.com/lingyired/status-trio, Apache-2.0).
// Only the reads that feed `StatusTrioSnapshot` are carried over; AirPods
// battery, output-device enumeration, and SSID lookups are intentionally absent.

// MARK: - Pure classification

/// Maps CoreWLAN interface flags plus the current network path to a Wi-Fi state.
/// Precedence matches the upstream classifier: off, notAssociated, shared,
/// temporary, hotspot, noInternet, connected.
enum StatusTrioWiFiClassifier {
    /// - Parameters:
    ///   - pathSatisfied: `nil` when no path update has arrived yet. An unknown
    ///     path never downgrades an associated interface to `noInternet`.
    static func classify(
        powerOn: Bool,
        serviceActive: Bool,
        isIBSS: Bool,
        sharingActive: Bool,
        pathSatisfied: Bool?,
        usesWiFi: Bool,
        isExpensive: Bool
    ) -> StatusTrioWiFiState {
        if !powerOn { return .off }
        if !serviceActive { return .notAssociated }
        if sharingActive { return .shared }
        if isIBSS { return .temporary }

        if let pathSatisfied {
            if pathSatisfied && usesWiFi && isExpensive {
                return .hotspot
            }
            if !pathSatisfied {
                return .noInternet
            }
        }

        return .connected
    }
}

/// Reduces an `NWPath` to the fields the snapshot and the Wi-Fi classifier need.
struct StatusTrioNetworkPathSnapshot: Equatable, Sendable {
    var isSatisfied: Bool
    var usesWiFi: Bool
    var usesWiredEthernet: Bool
    var isExpensive: Bool

    init(
        isSatisfied: Bool = false,
        usesWiFi: Bool = false,
        usesWiredEthernet: Bool = false,
        isExpensive: Bool = false
    ) {
        self.isSatisfied = isSatisfied
        self.usesWiFi = usesWiFi
        self.usesWiredEthernet = usesWiredEthernet
        self.isExpensive = isExpensive
    }

    var connection: StatusTrioNetworkConnection {
        StatusTrioNetworkConnectionResolver.resolve(
            satisfied: isSatisfied,
            usesWired: usesWiredEthernet,
            usesWiFi: usesWiFi
        )
    }
}

enum StatusTrioNetworkConnectionResolver {
    /// Wired wins over Wi-Fi when both are active so the icon reflects the
    /// interface the system prefers; anything else satisfied is `other`.
    static func resolve(
        satisfied: Bool,
        usesWired: Bool,
        usesWiFi: Bool
    ) -> StatusTrioNetworkConnection {
        guard satisfied else { return .offline }
        if usesWired { return .ethernet }
        if usesWiFi { return .wifi }
        return .other
    }
}

// MARK: - Reader protocol

/// Synchronous system reads. Implementations must be safe to call from a
/// background queue; the monitor never calls them on the main actor.
protocol StatusTrioSystemReading: Sendable {
    func readBattery() -> StatusTrioBatteryStatus
    func readWiFi(path: StatusTrioNetworkPathSnapshot?) -> StatusTrioWiFiStatus
    func readVolume() -> StatusTrioVolumeStatus
}

struct StatusTrioSystemReader: StatusTrioSystemReading {
    init() {}

    // MARK: Battery

    func readBattery() -> StatusTrioBatteryStatus {
        let isLowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else {
            return StatusTrioBatteryStatus(isLowPowerMode: isLowPowerMode)
        }
        let descriptions = sources.compactMap {
            IOPSGetPowerSourceDescription(info, $0)?.takeUnretainedValue() as? [String: Any]
        }
        return Self.battery(from: descriptions, isLowPowerMode: isLowPowerMode)
    }

    /// Pure parse of IOKit power-source descriptions. A missing or absent
    /// internal battery yields `isPresent == false` while still carrying the
    /// Low Power Mode flag.
    static func battery(
        from descriptions: [[String: Any]],
        isLowPowerMode: Bool
    ) -> StatusTrioBatteryStatus {
        guard let battery = descriptions.first(where: {
            $0[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
        }), battery[kIOPSIsPresentKey] as? Bool != false else {
            return StatusTrioBatteryStatus(isLowPowerMode: isLowPowerMode)
        }

        let percentage: Int?
        if let current = integerValue(battery[kIOPSCurrentCapacityKey]),
           let maximum = integerValue(battery[kIOPSMaxCapacityKey]) {
            if maximum > 0 {
                percentage = Int((Double(current) / Double(maximum) * 100).rounded())
            } else {
                percentage = current
            }
        } else {
            percentage = nil
        }

        return StatusTrioBatteryStatus(
            rawPercentage: percentage,
            isPresent: true,
            isCharging: battery[kIOPSIsChargingKey] as? Bool ?? false,
            isConnectedToPower: battery[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
            isLowPowerMode: isLowPowerMode
        )
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

    // MARK: Wi-Fi

    func readWiFi(path: StatusTrioNetworkPathSnapshot?) -> StatusTrioWiFiStatus {
        guard let interface = CWWiFiClient.shared().interface() else {
            return .unknown
        }
        let powerOn = interface.powerOn()
        let serviceActive = interface.serviceActive()
        // Internet Sharing only matters while the interface is up and associated,
        // so the SystemConfiguration read is skipped otherwise.
        let sharingActive = powerOn && serviceActive
            && Self.isInternetSharingActive() == true

        let state = StatusTrioWiFiClassifier.classify(
            powerOn: powerOn,
            serviceActive: serviceActive,
            isIBSS: interface.interfaceMode() == .IBSS,
            sharingActive: sharingActive,
            pathSatisfied: path?.isSatisfied,
            usesWiFi: path?.usesWiFi ?? false,
            isExpensive: path?.isExpensive ?? false
        )
        return StatusTrioWiFiStatus(state: state, rssi: Self.normalizedRSSI(interface.rssiValue()))
    }

    /// CoreWLAN reports zero when no reading is available; only negative dBm is real.
    static func normalizedRSSI(_ rssi: Int) -> Int? {
        rssi < 0 ? rssi : nil
    }

    /// `com.apple.nat` is an undocumented dynamic-store key used only as a
    /// best-effort signal. Missing or unreadable data returns `nil`, which means
    /// "not definitively sharing" and never assumes sharing is active.
    static func isInternetSharingActive() -> Bool? {
        guard let store = SCDynamicStoreCreate(nil, "MacTools.StatusTrio" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "com.apple.nat" as CFString) as? [String: Any],
              let nat = value["NAT"] as? [String: Any] else {
            return nil
        }
        return booleanValue(nat["Enabled"])
    }

    private static func booleanValue(_ value: Any?) -> Bool? {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return nil
    }

    // MARK: Volume

    func readVolume() -> StatusTrioVolumeStatus {
        guard let deviceID = StatusTrioCoreAudio.validDefaultOutputDevice() else {
            return .unknown
        }
        let scalars = StatusTrioCoreAudio.outputElements.compactMap { element in
            StatusTrioCoreAudio.readFloat32(
                objectID: deviceID,
                selector: kAudioDevicePropertyVolumeScalar,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
        }
        let mutes = StatusTrioCoreAudio.outputElements.compactMap { element in
            StatusTrioCoreAudio.readUInt32(
                objectID: deviceID,
                selector: kAudioDevicePropertyMute,
                scope: kAudioObjectPropertyScopeOutput,
                element: element
            )
        }
        let transport = StatusTrioCoreAudio.readUInt32(
            objectID: deviceID,
            selector: kAudioDevicePropertyTransportType,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        )
        return StatusTrioVolumeStatus(
            scalar: Self.averageScalar(scalars),
            isMuted: mutes.first == 1,
            isBluetoothOutput: Self.isBluetoothTransport(transport)
        )
    }

    /// Averages every channel that exposes a volume; devices without any
    /// software volume (for example some HDMI outputs) yield `nil`.
    static func averageScalar(_ scalars: [Float32]) -> Double? {
        let finite = scalars.filter(\.isFinite).map { min(1, max(0, Double($0))) }
        guard !finite.isEmpty else { return nil }
        return finite.reduce(0, +) / Double(finite.count)
    }

    static func isBluetoothTransport(_ transport: UInt32?) -> Bool {
        transport == kAudioDeviceTransportTypeBluetooth
            || transport == kAudioDeviceTransportTypeBluetoothLE
    }
}

// MARK: - CoreAudio helpers

/// Thin wrappers over `AudioObjectGetPropertyData` that turn every failure into
/// `nil`. Shared by the volume reader and the CoreAudio event monitor.
enum StatusTrioCoreAudio {
    /// Main element first, then the left and right channels for devices without
    /// a master control.
    static let outputElements: [AudioObjectPropertyElement] = [
        kAudioObjectPropertyElementMain,
        1,
        2
    ]

    static func defaultOutputDevice() -> AudioDeviceID? {
        guard let deviceID = readUInt32(
            objectID: AudioObjectID(kAudioObjectSystemObject),
            selector: kAudioHardwarePropertyDefaultOutputDevice,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        ), deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    /// The default device can briefly point at a stale ID while Bluetooth
    /// devices disconnect; only a live audio device is worth reading.
    static func validDefaultOutputDevice() -> AudioDeviceID? {
        guard let deviceID = defaultOutputDevice() else { return nil }
        let classID = readUInt32(
            objectID: deviceID,
            selector: kAudioObjectPropertyClass,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        )
        guard classID == kAudioDeviceClassID else { return nil }
        let isAlive = readUInt32(
            objectID: deviceID,
            selector: kAudioDevicePropertyDeviceIsAlive,
            scope: kAudioObjectPropertyScopeGlobal,
            element: kAudioObjectPropertyElementMain
        )
        guard isAlive == 1 else { return nil }
        return deviceID
    }

    static func hasProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Bool {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        return AudioObjectHasProperty(objectID, &address)
    }

    static func readUInt32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> UInt32? {
        readScalar(objectID: objectID, selector: selector, scope: scope, element: element, defaultValue: UInt32(0))
    }

    static func readFloat32(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement
    ) -> Float32? {
        readScalar(objectID: objectID, selector: selector, scope: scope, element: element, defaultValue: Float32(0))
    }

    private static func readScalar<Value>(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope,
        element: AudioObjectPropertyElement,
        defaultValue: Value
    ) -> Value? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
        guard AudioObjectHasProperty(objectID, &address) else { return nil }
        var value = defaultValue
        var size = UInt32(MemoryLayout<Value>.size)
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, UnsafeMutableRawPointer(pointer))
        }
        guard status == noErr, size == MemoryLayout<Value>.size else { return nil }
        return value
    }
}
