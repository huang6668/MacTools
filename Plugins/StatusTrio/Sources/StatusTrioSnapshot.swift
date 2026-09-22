import Foundation

// Adapted from Status Trio (https://github.com/lingyired/status-trio, Apache-2.0).
// Only the menu-bar icon inputs are carried over; popover, Dock, and Bluetooth
// panel state are intentionally absent.

struct StatusTrioBatteryStatus: Equatable, Sendable {
    /// Nil when IOKit reports no usable capacity.
    var rawPercentage: Int?
    /// False on desktop Macs without an internal battery.
    var isPresent: Bool
    var isCharging: Bool
    var isConnectedToPower: Bool
    var isLowPowerMode: Bool

    init(
        rawPercentage: Int? = nil,
        isPresent: Bool = false,
        isCharging: Bool = false,
        isConnectedToPower: Bool = false,
        isLowPowerMode: Bool = false
    ) {
        self.rawPercentage = rawPercentage
        self.isPresent = isPresent
        self.isCharging = isCharging
        self.isConnectedToPower = isConnectedToPower
        self.isLowPowerMode = isLowPowerMode
    }

    /// A missing battery renders as a full ring so desktop Macs keep a stable icon.
    var percentage: Int {
        guard isPresent else { return 100 }
        return min(100, max(0, rawPercentage ?? 100))
    }

    static let unknown = StatusTrioBatteryStatus()
}

enum StatusTrioWiFiState: Equatable, Sendable {
    case connected
    case notAssociated
    case off
    case noInternet
    case hotspot
    case temporary
    case shared
    case unavailable
}

struct StatusTrioWiFiStatus: Equatable, Sendable {
    var state: StatusTrioWiFiState
    /// Negative dBm while associated; nil when CoreWLAN reports no reading.
    var rssi: Int?

    init(state: StatusTrioWiFiState = .unavailable, rssi: Int? = nil) {
        self.state = state
        self.rssi = rssi
    }

    static let unknown = StatusTrioWiFiStatus()
}

enum StatusTrioNetworkConnection: Equatable, Sendable {
    case wifi
    case ethernet
    case other
    case offline
    case unknown
}

struct StatusTrioVolumeStatus: Equatable, Sendable {
    /// 0...1 for the default output device; nil when no output device exists.
    var scalar: Double?
    var isMuted: Bool
    /// True when the default output device uses a Bluetooth transport.
    var isBluetoothOutput: Bool

    init(scalar: Double? = nil, isMuted: Bool = false, isBluetoothOutput: Bool = false) {
        self.scalar = scalar
        self.isMuted = isMuted
        self.isBluetoothOutput = isBluetoothOutput
    }

    static let unknown = StatusTrioVolumeStatus()
}

struct StatusTrioSnapshot: Equatable, Sendable {
    var battery: StatusTrioBatteryStatus = .unknown
    var wifi: StatusTrioWiFiStatus = .unknown
    var connection: StatusTrioNetworkConnection = .unknown
    var volume: StatusTrioVolumeStatus = .unknown

    static let unknown = StatusTrioSnapshot()
}
