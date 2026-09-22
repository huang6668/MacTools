import Foundation

// Adapted from Status Trio (https://github.com/lingyired/status-trio, Apache-2.0).

enum StatusTrioRingStrokeStyle: String, CaseIterable, Sendable {
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

enum StatusTrioVolumeDisplayStyle: String, CaseIterable, Sendable {
    case dots
    case arc
}

/// Everything the renderer needs besides the live snapshot. Persisted by the plugin.
struct StatusTrioIconOptions: Equatable, Sendable {
    static let defaultCriticalThreshold = 20

    var showsBatteryPercentage = false
    var showsPercentageWhenConnected = false
    var showsChargingIndicator = true
    var usesBatteryStatusColors = true
    var batteryCriticalThreshold = defaultCriticalThreshold
    var ringStrokeStyle: StatusTrioRingStrokeStyle = .regular
    var showsWiFiIconForEthernet = false
    var showsWiFiIconForHotspot = false
    var showsWiFiIconForTemporary = false
    var showsWiFiIconForInternetSharing = false
    var volumeDisplayStyle: StatusTrioVolumeDisplayStyle = .dots
    var bluetoothGlyphReplacesNetworkIcon = true
    var bluetoothGlyphPrioritizesNetworkErrors = true

    static let `default` = StatusTrioIconOptions()

    var ringStrokeScale: CGFloat { ringStrokeStyle.scale }
    /// Dots grow half as fast as the stroke so they stay visually balanced.
    var volumeDotRadiusScale: CGFloat { 1 + (ringStrokeScale - 1) * 0.5 }
}
