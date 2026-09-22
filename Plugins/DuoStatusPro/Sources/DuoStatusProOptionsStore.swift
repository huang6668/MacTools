import Foundation
import MacToolsPluginKit

/// Persists `DuoStatusProIconOptions` through the plugin's scoped storage.
/// Keys are stable and must not be renamed without a migration.
@MainActor
struct DuoStatusProOptionsStore {
    enum Key {
        static let showsBatteryPercentage = "shows-battery-percentage"
        static let showsPercentageWhenConnected = "shows-percentage-when-connected"
        static let showsChargingIndicator = "shows-charging-indicator"
        static let usesBatteryStatusColors = "uses-battery-status-colors"
        static let batteryCriticalThreshold = "battery-critical-threshold"
        static let ringStrokeStyle = "ring-stroke-style"
        static let showsWiFiIconForEthernet = "shows-wifi-icon-for-ethernet"
        static let showsWiFiIconForHotspot = "shows-wifi-icon-for-hotspot"
        static let showsWiFiIconForTemporary = "shows-wifi-icon-for-temporary"
        static let showsWiFiIconForInternetSharing = "shows-wifi-icon-for-internet-sharing"
        static let volumeDisplayStyle = "volume-display-style"
        static let bluetoothGlyphReplacesNetworkIcon = "bluetooth-glyph-replaces-network-icon"
        static let bluetoothGlyphPrioritizesNetworkErrors = "bluetooth-glyph-prioritizes-network-errors"
        static let hidesSystemBattery = "hides-system-battery"
        static let hidesSystemWiFi = "hides-system-wifi"
    }

    static let criticalThresholdRange = 5...50
    static let criticalThresholdStep = 5

    private let storage: PluginStorage

    init(storage: PluginStorage) {
        self.storage = storage
    }

    func load() -> DuoStatusProIconOptions {
        var options = DuoStatusProIconOptions.default
        options.showsBatteryPercentage = bool(Key.showsBatteryPercentage, default: options.showsBatteryPercentage)
        options.showsPercentageWhenConnected = bool(
            Key.showsPercentageWhenConnected, default: options.showsPercentageWhenConnected
        )
        options.showsChargingIndicator = bool(Key.showsChargingIndicator, default: options.showsChargingIndicator)
        options.usesBatteryStatusColors = bool(Key.usesBatteryStatusColors, default: options.usesBatteryStatusColors)
        if let threshold = storage.object(forKey: Key.batteryCriticalThreshold) as? Int {
            options.batteryCriticalThreshold = Self.clampedThreshold(threshold)
        }
        if let raw = storage.string(forKey: Key.ringStrokeStyle),
           let style = DuoStatusProRingStrokeStyle(rawValue: raw) {
            options.ringStrokeStyle = style
        }
        options.showsWiFiIconForEthernet = bool(Key.showsWiFiIconForEthernet, default: options.showsWiFiIconForEthernet)
        options.showsWiFiIconForHotspot = bool(Key.showsWiFiIconForHotspot, default: options.showsWiFiIconForHotspot)
        options.showsWiFiIconForTemporary = bool(
            Key.showsWiFiIconForTemporary, default: options.showsWiFiIconForTemporary
        )
        options.showsWiFiIconForInternetSharing = bool(
            Key.showsWiFiIconForInternetSharing, default: options.showsWiFiIconForInternetSharing
        )
        if let raw = storage.string(forKey: Key.volumeDisplayStyle),
           let style = DuoStatusProVolumeDisplayStyle(rawValue: raw) {
            options.volumeDisplayStyle = style
        }
        options.bluetoothGlyphReplacesNetworkIcon = bool(
            Key.bluetoothGlyphReplacesNetworkIcon, default: options.bluetoothGlyphReplacesNetworkIcon
        )
        options.bluetoothGlyphPrioritizesNetworkErrors = bool(
            Key.bluetoothGlyphPrioritizesNetworkErrors, default: options.bluetoothGlyphPrioritizesNetworkErrors
        )
        options.hidesSystemBattery = bool(Key.hidesSystemBattery, default: options.hidesSystemBattery)
        options.hidesSystemWiFi = bool(Key.hidesSystemWiFi, default: options.hidesSystemWiFi)
        return options
    }

    func save(_ options: DuoStatusProIconOptions) {
        storage.set(options.showsBatteryPercentage, forKey: Key.showsBatteryPercentage)
        storage.set(options.showsPercentageWhenConnected, forKey: Key.showsPercentageWhenConnected)
        storage.set(options.showsChargingIndicator, forKey: Key.showsChargingIndicator)
        storage.set(options.usesBatteryStatusColors, forKey: Key.usesBatteryStatusColors)
        storage.set(Self.clampedThreshold(options.batteryCriticalThreshold), forKey: Key.batteryCriticalThreshold)
        storage.set(options.ringStrokeStyle.rawValue, forKey: Key.ringStrokeStyle)
        storage.set(options.showsWiFiIconForEthernet, forKey: Key.showsWiFiIconForEthernet)
        storage.set(options.showsWiFiIconForHotspot, forKey: Key.showsWiFiIconForHotspot)
        storage.set(options.showsWiFiIconForTemporary, forKey: Key.showsWiFiIconForTemporary)
        storage.set(options.showsWiFiIconForInternetSharing, forKey: Key.showsWiFiIconForInternetSharing)
        storage.set(options.volumeDisplayStyle.rawValue, forKey: Key.volumeDisplayStyle)
        storage.set(options.bluetoothGlyphReplacesNetworkIcon, forKey: Key.bluetoothGlyphReplacesNetworkIcon)
        storage.set(options.bluetoothGlyphPrioritizesNetworkErrors, forKey: Key.bluetoothGlyphPrioritizesNetworkErrors)
        storage.set(options.hidesSystemBattery, forKey: Key.hidesSystemBattery)
        storage.set(options.hidesSystemWiFi, forKey: Key.hidesSystemWiFi)
    }

    static func clampedThreshold(_ value: Int) -> Int {
        let step = criticalThresholdStep
        let snapped = Int((Double(value) / Double(step)).rounded()) * step
        return min(criticalThresholdRange.upperBound, max(criticalThresholdRange.lowerBound, snapped))
    }

    private func bool(_ key: String, default defaultValue: Bool) -> Bool {
        storage.object(forKey: key) as? Bool ?? defaultValue
    }
}
