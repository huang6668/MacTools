import Combine
import MacToolsPluginKit
import SwiftUI

public final class StatusTrioPluginFactory: NSObject, MacToolsPluginBundleFactory {
    public static func makeProvider(context: PluginRuntimeContext) throws -> any PluginProvider {
        StatusTrioPluginProvider(context: context)
    }
}

@MainActor
private struct StatusTrioPluginProvider: PluginProvider {
    let context: PluginRuntimeContext

    func makePlugins() -> [any MacToolsPlugin] {
        [StatusTrioPlugin(context: context)]
    }
}

@MainActor
final class StatusTrioPlugin: MacToolsPlugin, PluginSettingsPresenting,
    PluginApplicationActivityStateHandling, PluginMenuBarIconProviding,
    PluginMenuBarIconHostContextConsuming {
    static let pluginID = "status-trio"
    static let iconID = "status"

    enum SettingsID {
        static let menuBarSection = "menu-bar"
        static let batterySection = "battery"
        static let networkSection = "network"
        static let volumeSection = "volume"
        static let appearanceSection = "appearance"

        static let placement = "placement"
        static let showsBatteryPercentage = "shows-battery-percentage"
        static let showsPercentageWhenConnected = "shows-percentage-when-connected"
        static let showsChargingIndicator = "shows-charging-indicator"
        static let usesBatteryStatusColors = "uses-battery-status-colors"
        static let batteryCriticalThreshold = "battery-critical-threshold"
        static let showsWiFiIconForEthernet = "shows-wifi-icon-for-ethernet"
        static let showsWiFiIconForHotspot = "shows-wifi-icon-for-hotspot"
        static let showsWiFiIconForTemporary = "shows-wifi-icon-for-temporary"
        static let showsWiFiIconForInternetSharing = "shows-wifi-icon-for-internet-sharing"
        static let volumeDisplayStyle = "volume-display-style"
        static let bluetoothGlyphReplacesNetworkIcon = "bluetooth-glyph-replaces-network-icon"
        static let bluetoothGlyphPrioritizesNetworkErrors = "bluetooth-glyph-prioritizes-network-errors"
        static let ringStrokeStyle = "ring-stroke-style"
    }

    var onStateChange: (() -> Void)?
    var requestPermissionGuidance: ((String) -> Void)?
    var shortcutBindingResolver: ((String) -> ShortcutBinding?)?
    var requestSettingsPresentation: (() -> Void)?

    var onMenuBarIconChange: ((String) -> Void)?
    var menuBarIconHostContext: PluginMenuBarIconHostContext? {
        didSet { applyConfiguration() }
    }
    private let localization: PluginLocalization
    private let monitor: any StatusTrioMonitoring
    private let menuBar: any StatusTrioMenuBarPresenting
    private let optionsStore: StatusTrioOptionsStore
    private(set) var options: StatusTrioIconOptions
    private var localizationSubscription: AnyCancellable?
    private var isActive = false
    private var activityState: PluginApplicationActivityState = .interactive
    private var placementError: PluginMenuBarIconPlacementError?
    private var iconRevision: UInt64 = 0
    private var cachedIcon: (PluginMenuBarIconRenderContext, PluginMenuBarIconSnapshot)?

    var placement: PluginMenuBarIconPlacement {
        menuBarIconHostContext?.placement(for: Self.iconID) ?? .standalone
    }

    init(
        context: PluginRuntimeContext,
        monitor: (any StatusTrioMonitoring)? = nil,
        menuBar: (any StatusTrioMenuBarPresenting)? = nil
    ) {
        localization = PluginLocalization(bundle: context.resourceBundle)
        optionsStore = StatusTrioOptionsStore(storage: context.storage)
        options = optionsStore.load()
        self.monitor = monitor ?? StatusTrioSystemMonitor()
        self.menuBar = menuBar ?? StatusTrioMenuBarController()
        self.monitor.onChange = { [weak self] snapshot in
            guard let self, self.isActive, self.menuBarIconHostContext != nil,
                  self.activityState.allowsBackgroundWork else { return }
            self.iconDidChange(snapshot: snapshot)
        }
        self.menuBar.openSettings = { [weak self] in
            guard let self, self.isActive, self.menuBarIconHostContext != nil,
                  self.placement == .standalone else { return }
            self.requestSettingsPresentation?()
        }
    }

    isolated deinit {
        monitor.onChange = nil
        monitor.stop()
        menuBar.openSettings = nil
        menuBar.remove()
    }

    var metadata: PluginMetadata {
        PluginMetadata(
            id: Self.pluginID,
            title: localization.string("metadata.title", defaultValue: "Status Trio"),
            iconName: "circle.dotted.and.circle",
            iconTint: .blue,
            order: 25,
            defaultDescription: localization.string(
                "metadata.description", defaultValue: "Wi-Fi、电量与音量合一的菜单栏图标"
            )
        )
    }

    var settingsPage: PluginSettingsPage? {
        .form(sections: [
            menuBarSection,
            batterySection,
            networkSection,
            volumeSection,
            appearanceSection
        ])
    }

    private var menuBarSection: PluginSettingsSection {
        PluginSettingsSection(
            id: SettingsID.menuBarSection,
            title: localization.string("settings.menuBar", defaultValue: "菜单栏"),
            systemImage: "menubar.rectangle",
            footer: localization.string(
                "settings.footer",
                defaultValue: "圆弧显示电量，圆点显示 Wi-Fi 信号，底部显示音量。"
            ),
            rows: [
                PluginSettingsRow(
                    id: SettingsID.placement,
                    title: localization.string("settings.placement", defaultValue: "显示方式"),
                    description: placement == .primary
                        ? localization.string("settings.primaryDescription", defaultValue: "替换 MacTools 主图标，点击行为保持不变。")
                        : localization.string("settings.standaloneDescription", defaultValue: "独立显示，悬停查看状态，点击打开设置。"),
                    error: placementErrorMessage,
                    isEnabled: menuBarIconHostContext != nil,
                    control: .picker(
                        selectionID: placement.rawValue,
                        options: [
                            .init(id: PluginMenuBarIconPlacement.standalone.rawValue,
                                  title: localization.string("settings.standalone", defaultValue: "独立图标")),
                            .init(id: PluginMenuBarIconPlacement.primary.rawValue,
                                  title: localization.string("settings.primary", defaultValue: "替换应用图标"))
                        ],
                        style: .segmented
                    )
                )
            ]
        )
    }

    private var batterySection: PluginSettingsSection {
        PluginSettingsSection(
            id: SettingsID.batterySection,
            title: localization.string("settings.battery", defaultValue: "电量"),
            systemImage: "battery.75percent",
            rows: [
                PluginSettingsRow(
                    id: SettingsID.showsBatteryPercentage,
                    title: localization.string("settings.showsBatteryPercentage", defaultValue: "显示电量百分比"),
                    description: localization.string(
                        "settings.showsBatteryPercentageDescription", defaultValue: "在圆环中心显示当前电量数字。"
                    ),
                    control: .toggle(isOn: options.showsBatteryPercentage)
                ),
                PluginSettingsRow(
                    id: SettingsID.showsPercentageWhenConnected,
                    title: localization.string("settings.showsPercentageWhenConnected", defaultValue: "接通电源时显示百分比"),
                    description: localization.string(
                        "settings.showsPercentageWhenConnectedDescription", defaultValue: "关闭后，接通电源时仅显示充电标记。"
                    ),
                    isEnabled: options.showsBatteryPercentage,
                    control: .toggle(isOn: options.showsPercentageWhenConnected)
                ),
                PluginSettingsRow(
                    id: SettingsID.showsChargingIndicator,
                    title: localization.string("settings.showsChargingIndicator", defaultValue: "显示充电标记"),
                    description: localization.string(
                        "settings.showsChargingIndicatorDescription", defaultValue: "充电或接通电源时显示闪电标记。"
                    ),
                    control: .toggle(isOn: options.showsChargingIndicator)
                ),
                PluginSettingsRow(
                    id: SettingsID.usesBatteryStatusColors,
                    title: localization.string("settings.usesBatteryStatusColors", defaultValue: "使用状态颜色"),
                    description: localization.string(
                        "settings.usesBatteryStatusColorsDescription", defaultValue: "低电量、充电与低电量模式使用不同颜色。"
                    ),
                    control: .toggle(isOn: options.usesBatteryStatusColors)
                ),
                PluginSettingsRow(
                    id: SettingsID.batteryCriticalThreshold,
                    title: localization.string("settings.batteryCriticalThreshold", defaultValue: "低电量阈值"),
                    description: localization.string(
                        "settings.batteryCriticalThresholdDescription", defaultValue: "电量低于此值时以警示颜色显示。"
                    ),
                    control: .slider(
                        value: Double(options.batteryCriticalThreshold),
                        range: Double(StatusTrioOptionsStore.criticalThresholdRange.lowerBound)
                            ... Double(StatusTrioOptionsStore.criticalThresholdRange.upperBound),
                        step: Double(StatusTrioOptionsStore.criticalThresholdStep),
                        valueFormat: .percentage
                    )
                )
            ]
        )
    }

    private var networkSection: PluginSettingsSection {
        PluginSettingsSection(
            id: SettingsID.networkSection,
            title: localization.string("settings.network", defaultValue: "网络"),
            systemImage: "wifi",
            footer: localization.string(
                "settings.networkFooter", defaultValue: "未开启时，对应网络状态改为显示专用图标。"
            ),
            rows: [
                PluginSettingsRow(
                    id: SettingsID.showsWiFiIconForEthernet,
                    title: localization.string("settings.showsWiFiIconForEthernet", defaultValue: "以太网时显示 Wi-Fi 图标"),
                    control: .toggle(isOn: options.showsWiFiIconForEthernet)
                ),
                PluginSettingsRow(
                    id: SettingsID.showsWiFiIconForHotspot,
                    title: localization.string("settings.showsWiFiIconForHotspot", defaultValue: "个人热点时显示 Wi-Fi 图标"),
                    control: .toggle(isOn: options.showsWiFiIconForHotspot)
                ),
                PluginSettingsRow(
                    id: SettingsID.showsWiFiIconForTemporary,
                    title: localization.string("settings.showsWiFiIconForTemporary", defaultValue: "临时网络时显示 Wi-Fi 图标"),
                    control: .toggle(isOn: options.showsWiFiIconForTemporary)
                ),
                PluginSettingsRow(
                    id: SettingsID.showsWiFiIconForInternetSharing,
                    title: localization.string(
                        "settings.showsWiFiIconForInternetSharing", defaultValue: "互联网共享时显示 Wi-Fi 图标"
                    ),
                    control: .toggle(isOn: options.showsWiFiIconForInternetSharing)
                )
            ]
        )
    }

    private var volumeSection: PluginSettingsSection {
        PluginSettingsSection(
            id: SettingsID.volumeSection,
            title: localization.string("settings.volume", defaultValue: "音量"),
            systemImage: "speaker.wave.2",
            rows: [
                PluginSettingsRow(
                    id: SettingsID.volumeDisplayStyle,
                    title: localization.string("settings.volumeDisplayStyle", defaultValue: "显示样式"),
                    control: .picker(
                        selectionID: options.volumeDisplayStyle.rawValue,
                        options: [
                            .init(id: StatusTrioVolumeDisplayStyle.dots.rawValue,
                                  title: localization.string("settings.volumeDots", defaultValue: "圆点")),
                            .init(id: StatusTrioVolumeDisplayStyle.arc.rawValue,
                                  title: localization.string("settings.volumeArc", defaultValue: "圆弧"))
                        ],
                        style: .segmented
                    )
                ),
                PluginSettingsRow(
                    id: SettingsID.bluetoothGlyphReplacesNetworkIcon,
                    title: localization.string("settings.bluetoothGlyphReplacesNetworkIcon", defaultValue: "蓝牙输出时替换网络图标"),
                    description: localization.string(
                        "settings.bluetoothGlyphReplacesNetworkIconDescription", defaultValue: "使用蓝牙音频设备时显示蓝牙标记。"
                    ),
                    control: .toggle(isOn: options.bluetoothGlyphReplacesNetworkIcon)
                ),
                PluginSettingsRow(
                    id: SettingsID.bluetoothGlyphPrioritizesNetworkErrors,
                    title: localization.string("settings.bluetoothGlyphPrioritizesNetworkErrors", defaultValue: "网络异常优先显示"),
                    description: localization.string(
                        "settings.bluetoothGlyphPrioritizesNetworkErrorsDescription", defaultValue: "网络异常时仍显示网络状态而非蓝牙标记。"
                    ),
                    isEnabled: options.bluetoothGlyphReplacesNetworkIcon,
                    control: .toggle(isOn: options.bluetoothGlyphPrioritizesNetworkErrors)
                )
            ]
        )
    }

    private var appearanceSection: PluginSettingsSection {
        PluginSettingsSection(
            id: SettingsID.appearanceSection,
            title: localization.string("settings.appearance", defaultValue: "外观"),
            systemImage: "paintbrush",
            rows: [
                PluginSettingsRow(
                    id: SettingsID.ringStrokeStyle,
                    title: localization.string("settings.ringStrokeStyle", defaultValue: "线条粗细"),
                    control: .picker(
                        selectionID: options.ringStrokeStyle.rawValue,
                        options: [
                            .init(id: StatusTrioRingStrokeStyle.light.rawValue,
                                  title: localization.string("settings.strokeLight", defaultValue: "细")),
                            .init(id: StatusTrioRingStrokeStyle.regular.rawValue,
                                  title: localization.string("settings.strokeRegular", defaultValue: "标准")),
                            .init(id: StatusTrioRingStrokeStyle.bold.rawValue,
                                  title: localization.string("settings.strokeBold", defaultValue: "粗"))
                        ],
                        style: .segmented
                    )
                )
            ]
        )
    }

    func activate(context: PluginRuntimeContext) {
        guard !isActive else { return }
        isActive = true
        localizationSubscription = PluginRuntimeLocalization.source.$revision
            .dropFirst()
            .sink { [weak self] _ in
                // Locale-source publication happens before its revision changes.
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.iconDidChange(snapshot: self.monitor.snapshot)
                }
            }
        applyConfiguration()
    }

    func deactivate(reason: PluginDeactivationReason) {
        isActive = false
        localizationSubscription = nil
        monitor.stop()
        menuBar.remove()
    }

    func refresh() {
        applyConfiguration()
        monitor.refresh()
        onStateChange?()
    }

    func applicationActivityStateDidChange(_ state: PluginApplicationActivityState) {
        activityState = state
        applyConfiguration()
    }

    func handleSettingsAction(_ action: PluginSettingsAction) {
        switch action {
        case let .setSelection(controlID, optionID):
            handleSelection(controlID: controlID, optionID: optionID)
        case let .setBoolean(controlID, value):
            handleBoolean(controlID: controlID, value: value)
        case let .setNumber(controlID, value, phase):
            guard phase == .committed, controlID == SettingsID.batteryCriticalThreshold else { return }
            var updated = options
            updated.batteryCriticalThreshold = StatusTrioOptionsStore.clampedThreshold(Int(value.rounded()))
            commit(updated)
        case .setText, .invoke:
            return
        }
    }

    private func handleSelection(controlID: String, optionID: String) {
        switch controlID {
        case SettingsID.placement:
            guard let placement = PluginMenuBarIconPlacement(rawValue: optionID) else { return }
            requestPlacement(placement)
        case SettingsID.volumeDisplayStyle:
            guard let style = StatusTrioVolumeDisplayStyle(rawValue: optionID) else { return }
            var updated = options
            updated.volumeDisplayStyle = style
            commit(updated)
        case SettingsID.ringStrokeStyle:
            guard let style = StatusTrioRingStrokeStyle(rawValue: optionID) else { return }
            var updated = options
            updated.ringStrokeStyle = style
            commit(updated)
        default:
            return
        }
    }

    private func handleBoolean(controlID: String, value: Bool) {
        var updated = options
        switch controlID {
        case SettingsID.showsBatteryPercentage:
            updated.showsBatteryPercentage = value
        case SettingsID.showsPercentageWhenConnected:
            updated.showsPercentageWhenConnected = value
        case SettingsID.showsChargingIndicator:
            updated.showsChargingIndicator = value
        case SettingsID.usesBatteryStatusColors:
            updated.usesBatteryStatusColors = value
        case SettingsID.showsWiFiIconForEthernet:
            updated.showsWiFiIconForEthernet = value
        case SettingsID.showsWiFiIconForHotspot:
            updated.showsWiFiIconForHotspot = value
        case SettingsID.showsWiFiIconForTemporary:
            updated.showsWiFiIconForTemporary = value
        case SettingsID.showsWiFiIconForInternetSharing:
            updated.showsWiFiIconForInternetSharing = value
        case SettingsID.bluetoothGlyphReplacesNetworkIcon:
            updated.bluetoothGlyphReplacesNetworkIcon = value
        case SettingsID.bluetoothGlyphPrioritizesNetworkErrors:
            updated.bluetoothGlyphPrioritizesNetworkErrors = value
        default:
            return
        }
        commit(updated)
    }

    private func requestPlacement(_ placement: PluginMenuBarIconPlacement) {
        let result = menuBarIconHostContext?.requestPlacement(placement, for: Self.iconID)
            ?? .failure(.unavailable)
        switch result {
        case .success:
            placementError = nil
            applyConfiguration()
        case let .failure(error):
            placementError = error
        }
        onStateChange?()
    }

    /// Applies and persists new options, then refreshes every icon surface.
    private func commit(_ updated: StatusTrioIconOptions) {
        guard updated != options else { return }
        options = updated
        optionsStore.save(updated)
        iconRevision &+= 1
        cachedIcon = nil
        updateMenuBar(snapshot: monitor.snapshot)
        onMenuBarIconChange?(Self.iconID)
        onStateChange?()
    }

    var menuBarIconDescriptors: [PluginMenuBarIconDescriptor] {
        [.init(id: Self.iconID, title: metadata.title)]
    }

    func menuBarIcon(
        for iconID: String,
        context: PluginMenuBarIconRenderContext
    ) -> PluginMenuBarIconSnapshot? {
        guard iconID == Self.iconID else { return nil }
        if let cachedIcon, cachedIcon.0 == context { return cachedIcon.1 }
        let image = StatusTrioIconRenderer.image(
            for: monitor.snapshot,
            options: options,
            appearance: context.appearance == .dark ? .dark : .light,
            pointSize: context.pointSize
        )
        let description = tooltip(for: monitor.snapshot)
        let snapshot = PluginMenuBarIconSnapshot(
            revision: iconRevision,
            image: image,
            isTemplate: image.isTemplate,
            tooltip: description,
            accessibilityDescription: description
        )
        cachedIcon = (context, snapshot)
        return snapshot
    }

    func menuBarIconPlacementDidChange() {
        placementError = nil
        applyConfiguration()
        onStateChange?()
    }

    private var placementErrorMessage: String? {
        switch placementError {
        case let .occupied(owner):
            let owner = menuBarIconHostContext?.primaryIconOwner ?? owner
            if owner.requiresRestart {
                return localization.format(
                    "settings.occupiedPendingRestartFormat",
                    defaultValue: "「%@」正在等待重启。请重启 MacTools 后调整其图标设置。",
                    owner.pluginTitle
                )
            }
            return localization.format(
                "settings.occupiedFormat",
                defaultValue: "应用图标已由「%@」使用。请先在其设置中取消替换。",
                owner.pluginTitle
            )
        case .unavailable:
            return localization.string("settings.unavailable", defaultValue: "暂时无法切换显示方式，请稍后重试。")
        case .invalidIcon:
            return localization.string("settings.invalidIcon", defaultValue: "图标暂不可用，已保留当前显示方式。")
        case nil:
            return nil
        }
    }

    private func tooltip(for snapshot: StatusTrioSnapshot) -> String {
        "\(metadata.title)\n\(StatusTrioStatusDescription(localization: localization).text(for: snapshot))"
    }

    private func applyConfiguration() {
        // Wait for host registration so a restored primary placement never creates a duplicate item.
        guard isActive, menuBarIconHostContext != nil else {
            monitor.stop()
            menuBar.remove()
            return
        }
        if activityState.allowsBackgroundWork {
            monitor.start()
        } else {
            monitor.stop()
        }
        updateMenuBar(snapshot: monitor.snapshot)
    }

    private func updateMenuBar(snapshot: StatusTrioSnapshot) {
        guard isActive, menuBarIconHostContext != nil else { return }
        guard placement == .standalone else {
            menuBar.remove()
            return
        }
        menuBar.update(snapshot: snapshot, options: options, tooltip: tooltip(for: snapshot))
    }

    private func iconDidChange(snapshot: StatusTrioSnapshot) {
        guard isActive else { return }
        iconRevision &+= 1
        cachedIcon = nil
        updateMenuBar(snapshot: snapshot)
        onMenuBarIconChange?(Self.iconID)
    }
}
