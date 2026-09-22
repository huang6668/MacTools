import MacToolsPluginKit

/// Tooltip and accessibility text for the combined icon, one line per subsystem.
struct DuoStatusProStatusDescription {
    let localization: PluginLocalization

    func text(for snapshot: DuoStatusProSnapshot) -> String {
        [
            batteryText(snapshot.battery),
            wifiText(snapshot.wifi),
            connectionText(snapshot.connection),
            volumeText(snapshot.volume)
        ].joined(separator: "\n")
    }

    private func batteryText(_ battery: DuoStatusProBatteryStatus) -> String {
        guard battery.isPresent else {
            return localization.string("status.noBattery", defaultValue: "无内置电池")
        }
        guard battery.rawPercentage != nil else {
            return localization.string("status.batteryUnavailable", defaultValue: "电量暂不可用")
        }
        let percentage = battery.percentage
        var qualifiers: [String] = []
        if battery.isCharging {
            qualifiers.append(localization.string("status.charging", defaultValue: "充电中"))
        } else if battery.isConnectedToPower {
            qualifiers.append(localization.string("status.connectedToPower", defaultValue: "已接通电源"))
        }
        if battery.isLowPowerMode {
            qualifiers.append(localization.string("status.lowPowerMode", defaultValue: "低电量模式"))
        }
        guard !qualifiers.isEmpty else {
            return localization.format("status.batteryFormat", defaultValue: "电量 %d%%", percentage)
        }
        let separator = localization.string("status.qualifierSeparator", defaultValue: "、")
        return localization.format(
            "status.batteryQualifiedFormat",
            defaultValue: "电量 %d%%（%@）",
            percentage,
            qualifiers.joined(separator: separator)
        )
    }

    private func wifiText(_ wifi: DuoStatusProWiFiStatus) -> String {
        switch wifi.state {
        case .connected:
            let strength = signalStrengthText(rssi: wifi.rssi)
            return localization.format("status.wifiConnectedFormat", defaultValue: "Wi-Fi 已连接·信号%@", strength)
        case .notAssociated:
            return localization.string("status.wifiNotAssociated", defaultValue: "Wi-Fi 未连接")
        case .off:
            return localization.string("status.wifiOff", defaultValue: "Wi-Fi 已关闭")
        case .noInternet:
            return localization.string("status.wifiNoInternet", defaultValue: "Wi-Fi 无互联网")
        case .hotspot:
            return localization.string("status.wifiHotspot", defaultValue: "Wi-Fi 个人热点")
        case .temporary:
            return localization.string("status.wifiTemporary", defaultValue: "Wi-Fi 临时网络")
        case .shared:
            return localization.string("status.wifiShared", defaultValue: "Wi-Fi 互联网共享")
        case .unavailable:
            return localization.string("status.wifiUnavailable", defaultValue: "Wi-Fi 不可用")
        }
    }

    private func signalStrengthText(rssi: Int?) -> String {
        guard let rssi else {
            return localization.string("status.signalUnknown", defaultValue: "未知")
        }
        // Thresholds follow the common macOS interpretation of RSSI in dBm.
        if rssi >= -60 {
            return localization.string("status.signalStrong", defaultValue: "强")
        }
        if rssi >= -75 {
            return localization.string("status.signalMedium", defaultValue: "中")
        }
        return localization.string("status.signalWeak", defaultValue: "弱")
    }

    private func connectionText(_ connection: DuoStatusProNetworkConnection) -> String {
        switch connection {
        case .wifi:
            localization.string("status.connectionWiFi", defaultValue: "网络 Wi-Fi")
        case .ethernet:
            localization.string("status.connectionEthernet", defaultValue: "网络 以太网")
        case .other:
            localization.string("status.connectionOther", defaultValue: "网络 其他")
        case .offline:
            localization.string("status.connectionOffline", defaultValue: "网络 离线")
        case .unknown:
            localization.string("status.connectionUnknown", defaultValue: "网络 未知")
        }
    }

    private func volumeText(_ volume: DuoStatusProVolumeStatus) -> String {
        guard let scalar = volume.scalar, scalar.isFinite else {
            return localization.string("status.volumeUnavailable", defaultValue: "音量暂不可用")
        }
        let percentage = Int((min(1, max(0, scalar)) * 100).rounded())
        var qualifiers: [String] = []
        if volume.isMuted {
            qualifiers.append(localization.string("status.muted", defaultValue: "已静音"))
        }
        if volume.isBluetoothOutput {
            qualifiers.append(localization.string("status.bluetoothOutput", defaultValue: "蓝牙输出"))
        }
        guard !qualifiers.isEmpty else {
            return localization.format("status.volumeFormat", defaultValue: "音量 %d%%", percentage)
        }
        let separator = localization.string("status.qualifierSeparator", defaultValue: "、")
        return localization.format(
            "status.volumeQualifiedFormat",
            defaultValue: "音量 %d%%（%@）",
            percentage,
            qualifiers.joined(separator: separator)
        )
    }
}
