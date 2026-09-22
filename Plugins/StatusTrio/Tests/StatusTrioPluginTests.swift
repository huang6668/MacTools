import MacToolsPluginKit
import XCTest
@testable import MacTools
@testable import StatusTrioPlugin

@MainActor
final class StatusTrioPluginTests: XCTestCase {
    func testActivationCreatesStandaloneItemAndStartsMonitorOnlyAfterHostContext() throws {
        let storage = StorageFake()
        let monitor = MonitorFake()
        let menuBar = MenuBarFake()
        let context = PluginRuntimeContext(pluginID: StatusTrioPlugin.pluginID, storage: storage)
        let plugin = StatusTrioPlugin(context: context, monitor: monitor, menuBar: menuBar)
        XCTAssertFalse(plugin.panelItems.contains { $0.kind == .row })
        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
        XCTAssertEqual(plugin.settingsPage?.body.layout, .form)

        var settingsRequests = 0
        plugin.requestSettingsPresentation = { settingsRequests += 1 }
        plugin.activate(context: context)
        plugin.activate(context: context)
        XCTAssertEqual(monitor.startCount, 0)
        XCTAssertEqual(menuBar.creationCount, 0)
        menuBar.openSettings?()
        XCTAssertEqual(settingsRequests, 0)

        let defaults = UserDefaults(suiteName: "StatusTrioPluginTests-\(UUID().uuidString)")!
        let coordinator = PluginMenuBarIconCoordinator(userDefaults: defaults)
        coordinator.synchronize(with: [plugin], pendingPluginIDs: [])
        XCTAssertEqual(monitor.startCount, 1)
        XCTAssertTrue(menuBar.isVisible)
        XCTAssertEqual(menuBar.creationCount, 1)
        menuBar.openSettings?()
        XCTAssertEqual(settingsRequests, 1)

        monitor.emit(.init(battery: .init(rawPercentage: 42, isPresent: true, isCharging: true)))
        XCTAssertEqual(menuBar.snapshot?.battery.rawPercentage, 42)
        XCTAssertEqual(menuBar.options, plugin.options)
        let tooltip = try XCTUnwrap(menuBar.tooltip)
        XCTAssertTrue(tooltip.hasPrefix(plugin.metadata.title))
        XCTAssertTrue(tooltip.contains("42%"))
    }

    func testPrimaryPlacementRemovesStandaloneItemAndBumpsRevisionOnMonitorChange() throws {
        let fixture = Fixture()
        fixture.plugin.activate(context: fixture.context)
        XCTAssertTrue(fixture.menuBar.isVisible)
        fixture.plugin.handleSettingsAction(.setSelection(controlID: "placement", optionID: "primary"))
        XCTAssertEqual(fixture.plugin.placement, .primary)
        XCTAssertFalse(fixture.menuBar.isVisible)
        XCTAssertTrue(fixture.monitor.isRunning)
        XCTAssertEqual(fixture.monitor.startCount, 1)

        var iconChanges: [String] = []
        fixture.plugin.onMenuBarIconChange = { iconChanges.append($0) }
        var stateChanges = 0
        fixture.plugin.onStateChange = { stateChanges += 1 }
        let light = PluginMenuBarIconRenderContext(
            pointSize: .init(width: 24, height: 24), displayScale: 2, appearance: .light
        )
        let before = try XCTUnwrap(fixture.plugin.menuBarIcon(for: "status", context: light))
        XCTAssertTrue(before.image === fixture.plugin.menuBarIcon(for: "status", context: light)?.image)
        XCTAssertTrue(before.tooltip.hasPrefix(fixture.plugin.metadata.title))

        fixture.monitor.emit(.init(volume: .init(scalar: 0.5, isMuted: true)))
        let after = try XCTUnwrap(fixture.plugin.menuBarIcon(for: "status", context: light))
        XCTAssertGreaterThan(after.revision, before.revision)
        XCTAssertFalse(after.image === before.image)
        XCTAssertEqual(iconChanges, ["status"])
        XCTAssertEqual(stateChanges, 0)
        XCTAssertFalse(fixture.menuBar.isVisible)
        XCTAssertNil(fixture.plugin.menuBarIcon(for: "other", context: light))

        fixture.plugin.handleSettingsAction(.setSelection(controlID: "placement", optionID: "standalone"))
        XCTAssertTrue(fixture.menuBar.isVisible)
        XCTAssertEqual(fixture.monitor.startCount, 1)
    }

    func testVolumeStylePersistsAndReloadsInNewInstance() throws {
        let fixture = Fixture()
        fixture.plugin.activate(context: fixture.context)
        XCTAssertEqual(fixture.plugin.options.volumeDisplayStyle, .dots)
        var iconChanges = 0
        fixture.plugin.onMenuBarIconChange = { _ in iconChanges += 1 }
        var stateChanges = 0
        fixture.plugin.onStateChange = { stateChanges += 1 }
        let updatesBefore = fixture.menuBar.updateCount

        fixture.plugin.handleSettingsAction(.setSelection(controlID: "volume-display-style", optionID: "arc"))
        XCTAssertEqual(fixture.plugin.options.volumeDisplayStyle, .arc)
        XCTAssertEqual(fixture.storage.string(forKey: "volume-display-style"), "arc")
        XCTAssertEqual(iconChanges, 1)
        XCTAssertEqual(stateChanges, 1)
        XCTAssertEqual(fixture.menuBar.updateCount, updatesBefore + 1)
        XCTAssertEqual(fixture.menuBar.options?.volumeDisplayStyle, .arc)

        // Re-applying the same value is a no-op and must not churn persistence or icons.
        fixture.plugin.handleSettingsAction(.setSelection(controlID: "volume-display-style", optionID: "arc"))
        XCTAssertEqual(iconChanges, 1)
        XCTAssertEqual(stateChanges, 1)

        fixture.plugin.handleSettingsAction(.setBoolean(controlID: "shows-battery-percentage", value: true))
        fixture.plugin.handleSettingsAction(
            .setNumber(controlID: "battery-critical-threshold", value: 33, phase: .changed)
        )
        XCTAssertEqual(fixture.plugin.options.batteryCriticalThreshold, 20)
        fixture.plugin.handleSettingsAction(
            .setNumber(controlID: "battery-critical-threshold", value: 33, phase: .committed)
        )
        XCTAssertEqual(fixture.plugin.options.batteryCriticalThreshold, 35)
        fixture.plugin.handleSettingsAction(.setSelection(controlID: "ring-stroke-style", optionID: "bold"))

        let restored = StatusTrioPlugin(context: fixture.context, monitor: MonitorFake(), menuBar: MenuBarFake())
        XCTAssertEqual(restored.options.volumeDisplayStyle, .arc)
        XCTAssertTrue(restored.options.showsBatteryPercentage)
        XCTAssertEqual(restored.options.batteryCriticalThreshold, 35)
        XCTAssertEqual(restored.options.ringStrokeStyle, .bold)
        XCTAssertEqual(restored.options, fixture.plugin.options)

        guard case let .form(sections) = restored.settingsPage?.body else { return XCTFail("Missing form") }
        let rows = sections.flatMap { section -> [PluginSettingsRow] in
            if case let .rows(rows) = section.content { return rows }
            return []
        }
        let volumeRow = try XCTUnwrap(rows.first { $0.id == "volume-display-style" })
        guard case let .picker(selection, options, _) = volumeRow.control else {
            return XCTFail("Expected a picker for the volume display style")
        }
        XCTAssertEqual(selection, "arc")
        XCTAssertEqual(options.map(\.id), ["dots", "arc"])
        let dependentRow = try XCTUnwrap(rows.first { $0.id == "shows-percentage-when-connected" })
        XCTAssertTrue(dependentRow.isEnabled)
    }

    func testDependentRowsFollowParentToggles() throws {
        let fixture = Fixture()
        func row(_ id: String) throws -> PluginSettingsRow {
            guard case let .form(sections) = fixture.plugin.settingsPage?.body else {
                XCTFail("Missing form")
                throw MissingRowError(id: id)
            }
            let rows = sections.flatMap { section -> [PluginSettingsRow] in
                if case let .rows(rows) = section.content { return rows }
                return []
            }
            guard let row = rows.first(where: { $0.id == id }) else { throw MissingRowError(id: id) }
            return row
        }
        XCTAssertFalse(try row("shows-percentage-when-connected").isEnabled)
        XCTAssertTrue(try row("bluetooth-glyph-prioritizes-network-errors").isEnabled)
        fixture.plugin.handleSettingsAction(.setBoolean(controlID: "shows-battery-percentage", value: true))
        fixture.plugin.handleSettingsAction(.setBoolean(controlID: "bluetooth-glyph-replaces-network-icon", value: false))
        XCTAssertTrue(try row("shows-percentage-when-connected").isEnabled)
        XCTAssertFalse(try row("bluetooth-glyph-prioritizes-network-errors").isEnabled)
        XCTAssertEqual(fixture.storage.object(forKey: "bluetooth-glyph-replaces-network-icon") as? Bool, false)
        XCTAssertEqual(fixture.monitor.startCount, 0)
    }

    func testDeactivateStopsMonitorAndRemovesItem() {
        for reason in [PluginDeactivationReason.disabled, .uninstalling, .updating, .hostShutdown] {
            let fixture = Fixture()
            fixture.plugin.activate(context: fixture.context)
            XCTAssertTrue(fixture.monitor.isRunning)
            XCTAssertTrue(fixture.menuBar.isVisible)
            var settingsRequests = 0
            fixture.plugin.requestSettingsPresentation = { settingsRequests += 1 }
            fixture.coordinator.unregister(pluginID: StatusTrioPlugin.pluginID, reason: reason)
            fixture.plugin.deactivate(reason: reason)
            XCTAssertFalse(fixture.monitor.isRunning)
            XCTAssertFalse(fixture.menuBar.isVisible)
            fixture.monitor.emit(.init(wifi: .init(state: .off)))
            fixture.menuBar.openSettings?()
            fixture.plugin.refresh()
            XCTAssertFalse(fixture.monitor.isRunning)
            XCTAssertFalse(fixture.menuBar.isVisible)
            XCTAssertEqual(settingsRequests, 0)
        }
    }

    func testActivityPausesMonitoringWithoutCreatingDuplicateItems() {
        let fixture = Fixture()
        fixture.plugin.applicationActivityStateDidChange(.systemSleeping)
        fixture.plugin.activate(context: fixture.context)
        XCTAssertFalse(fixture.monitor.isRunning)
        XCTAssertTrue(fixture.menuBar.isVisible)

        fixture.plugin.applicationActivityStateDidChange(.interactive)
        XCTAssertTrue(fixture.monitor.isRunning)
        for state in [PluginApplicationActivityState.sessionInactive, .displayAsleep, .systemSleeping, .waking] {
            fixture.plugin.applicationActivityStateDidChange(state)
            XCTAssertFalse(fixture.monitor.isRunning)
            let updates = fixture.menuBar.updateCount
            fixture.monitor.emit(.init(wifi: .init(state: .off)))
            XCTAssertEqual(fixture.menuBar.updateCount, updates)
        }
        fixture.plugin.applicationActivityStateDidChange(.interactive)
        XCTAssertTrue(fixture.monitor.isRunning)
        XCTAssertEqual(fixture.menuBar.creationCount, 1)
    }

    func testDeinitStopsResourcesAndClearsCallbacks() {
        let storage = StorageFake()
        let monitor = MonitorFake()
        let menuBar = MenuBarFake()
        let context = PluginRuntimeContext(pluginID: StatusTrioPlugin.pluginID, storage: storage)
        var plugin: StatusTrioPlugin? = StatusTrioPlugin(context: context, monitor: monitor, menuBar: menuBar)
        weak let weakPlugin = plugin
        plugin?.activate(context: context)
        plugin = nil
        XCTAssertNil(weakPlugin)
        XCTAssertFalse(monitor.isRunning)
        XCTAssertFalse(menuBar.isVisible)
        XCTAssertNil(monitor.onChange)
        XCTAssertNil(menuBar.openSettings)
    }

    func testOccupiedPlacementKeepsStandaloneAndShowsInlineError() throws {
        let fixture = Fixture()
        fixture.plugin.activate(context: fixture.context)
        let owner = PluginMenuBarIconOwner(pluginID: "other", iconID: "status", pluginTitle: "Other Status")
        fixture.plugin.menuBarIconHostContext = PluginMenuBarIconHostContext(
            placement: { _ in .standalone }, primaryIconOwner: { owner },
            requestPlacement: { _, _ in .failure(.occupied(owner: owner)) }
        )
        fixture.plugin.handleSettingsAction(.setSelection(controlID: "placement", optionID: "primary"))
        XCTAssertEqual(fixture.plugin.placement, .standalone)
        XCTAssertTrue(fixture.menuBar.isVisible)
        guard case let .form(sections) = fixture.plugin.settingsPage?.body,
              case let .rows(rows) = sections.first?.content else { return XCTFail("Missing form") }
        XCTAssertEqual(rows.first?.id, "placement")
        XCTAssertTrue(try XCTUnwrap(rows.first?.error).contains("Other Status"))

        fixture.plugin.menuBarIconPlacementDidChange()
        guard case let .form(updated) = fixture.plugin.settingsPage?.body,
              case let .rows(updatedRows) = updated.first?.content else { return XCTFail("Missing form") }
        XCTAssertNil(updatedRows.first?.error)
    }

    func testPendingRestartConflictUsesRestartGuidance() throws {
        let fixture = Fixture()
        fixture.plugin.activate(context: fixture.context)
        let owner = PluginMenuBarIconOwner(
            pluginID: "other", iconID: "status", pluginTitle: "Other Status", requiresRestart: true
        )
        fixture.plugin.menuBarIconHostContext = PluginMenuBarIconHostContext(
            placement: { _ in .standalone }, primaryIconOwner: { owner },
            requestPlacement: { _, _ in .failure(.occupied(owner: owner)) }
        )
        fixture.plugin.handleSettingsAction(.setSelection(controlID: "placement", optionID: "primary"))
        guard case let .form(sections) = fixture.plugin.settingsPage?.body,
              case let .rows(rows) = sections.first?.content else { return XCTFail("Missing form") }
        let localization = PluginLocalization(bundle: fixture.context.resourceBundle)
        XCTAssertEqual(try XCTUnwrap(rows.first?.error), localization.format(
            "settings.occupiedPendingRestartFormat",
            defaultValue: "「%@」正在等待重启。请重启 MacTools 后调整其图标设置。",
            owner.pluginTitle
        ))
        XCTAssertEqual(fixture.plugin.placement, .standalone)
    }

    func testRestoredPrimaryPlacementWaitsForHostWithoutCreatingStandaloneItem() {
        let fixture = Fixture()
        fixture.plugin.activate(context: fixture.context)
        fixture.plugin.handleSettingsAction(.setSelection(controlID: "placement", optionID: "primary"))
        fixture.coordinator.deactivateAll(reason: .hostShutdown)
        fixture.plugin.deactivate(reason: .hostShutdown)
        let menuBar = MenuBarFake()
        let monitor = MonitorFake()
        let restored = StatusTrioPlugin(context: fixture.context, monitor: monitor, menuBar: menuBar)
        restored.activate(context: fixture.context)
        XCTAssertEqual(menuBar.creationCount, 0)
        XCTAssertEqual(monitor.startCount, 0)
        let coordinator = PluginMenuBarIconCoordinator(userDefaults: fixture.defaults)
        coordinator.synchronize(with: [restored], pendingPluginIDs: [])
        XCTAssertEqual(restored.placement, .primary)
        XCTAssertEqual(menuBar.creationCount, 0)
        XCTAssertEqual(monitor.startCount, 1)
    }

    func testFactoryAndManifestAgreeOnSettingsOnlyCapabilities() throws {
        let fixture = Fixture()
        let provider = try StatusTrioPluginFactory.makeProvider(context: fixture.context)
        let plugins = provider.makePlugins()
        XCTAssertEqual(plugins.count, 1)
        let plugin = try XCTUnwrap(plugins.first)
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("plugin.json")
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let capabilities = try XCTUnwrap(manifest["capabilities"] as? [String: Any])
        XCTAssertEqual(manifest["id"] as? String, plugin.metadata.id)
        XCTAssertEqual(capabilities["panelItems"] as? [String], plugin.panelItems.map { $0.kind.rawValue })
        XCTAssertEqual(capabilities["settings"] as? String, "form")
        XCTAssertEqual(manifest["permissions"] as? [String], [])
        XCTAssertFalse(plugin is any PluginActionProviding)
        XCTAssertNoThrow(try PluginSettingsValidator.validate(try XCTUnwrap(plugin.settingsPage)))
    }

    @MainActor
    private final class Fixture {
        let storage = StorageFake()
        let monitor = MonitorFake()
        let menuBar = MenuBarFake()
        let context: PluginRuntimeContext
        let plugin: StatusTrioPlugin
        let suiteName = "StatusTrioPluginTests-\(UUID().uuidString)"
        let defaults: UserDefaults
        let coordinator: PluginMenuBarIconCoordinator

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            coordinator = PluginMenuBarIconCoordinator(userDefaults: defaults)
            context = PluginRuntimeContext(pluginID: StatusTrioPlugin.pluginID, storage: storage)
            plugin = StatusTrioPlugin(context: context, monitor: monitor, menuBar: menuBar)
            coordinator.synchronize(with: [plugin], pendingPluginIDs: [])
        }

        isolated deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}

private struct MissingRowError: Error {
    let id: String
}

@MainActor
private final class MonitorFake: StatusTrioMonitoring {
    var snapshot = StatusTrioSnapshot.unknown
    var onChange: ((StatusTrioSnapshot) -> Void)?
    private(set) var isRunning = false
    private(set) var startCount = 0

    func start() {
        guard !isRunning else { return }
        isRunning = true
        startCount += 1
    }

    func stop() { isRunning = false }
    func refresh() {}

    func emit(_ snapshot: StatusTrioSnapshot) {
        self.snapshot = snapshot
        onChange?(snapshot)
    }
}

@MainActor
private final class MenuBarFake: StatusTrioMenuBarPresenting {
    var openSettings: (() -> Void)?
    private(set) var snapshot: StatusTrioSnapshot?
    private(set) var options: StatusTrioIconOptions?
    private(set) var tooltip: String?
    private(set) var isVisible = false
    private(set) var updateCount = 0
    private(set) var creationCount = 0

    func update(snapshot: StatusTrioSnapshot, options: StatusTrioIconOptions, tooltip: String) {
        if !isVisible { creationCount += 1 }
        isVisible = true
        self.snapshot = snapshot
        self.options = options
        self.tooltip = tooltip
        updateCount += 1
    }

    func remove() {
        isVisible = false
        snapshot = nil
        options = nil
        tooltip = nil
    }
}

@MainActor
private final class StorageFake: PluginStorage {
    private var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func data(forKey key: String) -> Data? { values[key] as? Data }
    func string(forKey key: String) -> String? { values[key] as? String }
    func stringArray(forKey key: String) -> [String]? { values[key] as? [String] }
    func integer(forKey key: String) -> Int { values[key] as? Int ?? 0 }
    func bool(forKey key: String) -> Bool { values[key] as? Bool ?? false }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    func migrateValueIfNeeded(fromLegacyKey legacyKey: String, to key: String) {}
}
