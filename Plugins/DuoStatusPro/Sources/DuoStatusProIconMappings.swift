import Foundation

// Adapted from Status Trio (https://github.com/lingyired/status-trio, Apache-2.0).

enum DuoStatusProBatteryColorRole: Equatable, Sendable {
    case foreground
    case critical
    case lowPower
    case charging
}

/// What fills the battery ring's top gap.
enum DuoStatusProBatteryGapContent: Equatable, Sendable {
    /// Charging: the lightning bolt.
    case bolt
    /// Connected to power without charging: the plug.
    case plug
    /// The percentage numerals.
    case percentage
    /// Nothing: the ring closes into a full arc.
    case empty
}

/// Pure snapshot-to-glyph decisions shared by the renderer and its tests.
enum DuoStatusProIconMappings {
    static func wifiBars(rssi: Int?) -> Int {
        guard let rssi else { return 0 }
        switch rssi {
        // Parentheses are required for this negative partial range in Swift 6.
        case (-60)...:
            return 3
        case -78 ... -61:
            return 2
        case -88 ... -79:
            return 1
        default:
            return 0
        }
    }

    /// Number of lit volume dots, 0...4. A missing output device counts as silent.
    static func volumeSteps(scalar: Double?, isMuted: Bool) -> Int {
        guard let scalar, scalar.isFinite else { return 0 }
        let clamped = min(1, max(0, scalar))
        if isMuted || clamped == 0 { return 0 }
        if clamped <= 0.25 { return 1 }
        if clamped <= 0.50 { return 2 }
        if clamped <= 0.75 { return 3 }
        return 4
    }

    static func batteryColorRole(
        _ battery: DuoStatusProBatteryStatus,
        options: DuoStatusProIconOptions
    ) -> DuoStatusProBatteryColorRole {
        guard options.usesBatteryStatusColors else { return .foreground }
        let threshold = min(100, max(0, options.batteryCriticalThreshold))
        if battery.percentage < threshold { return .critical }
        if battery.isLowPowerMode { return .lowPower }
        if battery.isCharging || battery.isConnectedToPower { return .charging }
        return .foreground
    }

    /// A charging battery keeps the bolt. A connected power source that is not
    /// charging, including a battery that is already full, shows the plug, or
    /// the percentage when the user asked for the number in that state.
    static func batteryGapContent(
        _ battery: DuoStatusProBatteryStatus,
        options: DuoStatusProIconOptions
    ) -> DuoStatusProBatteryGapContent {
        if battery.isPresent, options.showsChargingIndicator {
            if battery.isCharging { return .bolt }
            let showsPercentageForPower = options.showsPercentageWhenConnected
                && options.showsBatteryPercentage
            if battery.isConnectedToPower, !showsPercentageForPower {
                return .plug
            }
        }

        return options.showsBatteryPercentage ? .percentage : .empty
    }

    static func batteryProgress(_ battery: DuoStatusProBatteryStatus) -> Double {
        Double(battery.percentage) / 100.0
    }

    /// Whether the Bluetooth audio glyph takes over the center of the ring.
    static func shouldReplaceNetworkIcon(
        volume: DuoStatusProVolumeStatus,
        wifi: DuoStatusProWiFiStatus,
        connection: DuoStatusProNetworkConnection,
        options: DuoStatusProIconOptions
    ) -> Bool {
        guard options.bluetoothGlyphReplacesNetworkIcon, volume.isBluetoothOutput else {
            return false
        }
        guard options.bluetoothGlyphPrioritizesNetworkErrors else { return true }

        // A wired connection is not a Wi-Fi error and can still coexist with
        // Bluetooth audio, but being fully offline is always worth showing.
        if connection == .offline { return false }
        return !wifi.state.isBluetoothReplacementNetworkError
    }
}

private extension DuoStatusProWiFiState {
    var isBluetoothReplacementNetworkError: Bool {
        switch self {
        case .notAssociated, .noInternet, .off, .unavailable:
            true
        case .connected, .hotspot, .temporary, .shared:
            false
        }
    }
}
