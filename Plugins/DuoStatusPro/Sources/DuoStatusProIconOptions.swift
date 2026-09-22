import Foundation

// Adapted from Status Trio (https://github.com/lingyired/status-trio, Apache-2.0).

enum DuoStatusProRingStrokeStyle: String, CaseIterable, Sendable {
    case light
    case regular
    case bold

    var scale: CGFloat {
        switch self {
        case .light: 1.0
        case .regular: 1.25
        case .bold: 1.5
        }
    }
}

enum DuoStatusProVolumeDisplayStyle: String, CaseIterable, Sendable {
    case dots
    case arc
}

/// Everything the renderer needs besides the live snapshot. Persisted by the plugin.
struct DuoStatusProIconOptions: Equatable, Sendable {
    static let defaultCriticalThreshold = 20

    var showsBatteryPercentage = false
    var showsPercentageWhenConnected = false
    var showsChargingIndicator = true
    var usesBatteryStatusColors = true
    var batteryCriticalThreshold = defaultCriticalThreshold
    var ringStrokeStyle: DuoStatusProRingStrokeStyle = .regular
    var showsWiFiIconForEthernet = false
    var showsWiFiIconForHotspot = false
    var showsWiFiIconForTemporary = false
    var showsWiFiIconForInternetSharing = false
    var volumeDisplayStyle: DuoStatusProVolumeDisplayStyle = .dots
    var bluetoothGlyphReplacesNetworkIcon = true
    var bluetoothGlyphPrioritizesNetworkErrors = true
    /// Hides the system Battery menu bar icon while the plugin is active.
    var hidesSystemBattery = false
    /// Hides the system Wi-Fi menu bar icon while the plugin is active.
    var hidesSystemWiFi = false

    static let `default` = DuoStatusProIconOptions()

    var ringStrokeScale: CGFloat { ringStrokeStyle.scale }
    /// Dots grow half as fast as the stroke so they stay visually balanced.
    var volumeDotRadiusScale: CGFloat { 1 + (ringStrokeScale - 1) * 0.5 }
}
