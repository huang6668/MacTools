import CoreFoundation
import Foundation
import OSLog

// Controls the visibility of macOS system menu bar icons (Battery, Wi-Fi) by
// writing to com.apple.controlcenter preferences. Changes take effect after
// ControlCenter restarts, which causes a brief visual refresh of the menu bar.
// The controller records each icon's pre-hide state and restores it on demand.

@MainActor
final class DuoStatusProSystemIconController {
    enum SystemIcon: String, CaseIterable {
        case battery = "Battery"
        case wifi = "WiFi"

        var preferenceKey: String { "NSStatusItem Visible \(rawValue)" }
    }

    private static let appID = "com.apple.controlcenter" as CFString
    private var originalVisibility: [SystemIcon: Bool] = [:]
    private var pendingRestartTask: Task<Void, Never>?

    /// Applies the desired hide state for each icon. Restarts ControlCenter once
    /// if any visibility changed. The restart is debounced by one run-loop cycle
    /// so rapid successive calls coalesce into a single restart.
    func apply(hideBattery: Bool, hideWiFi: Bool) {
        var changed = false

        for icon in SystemIcon.allCases {
            let shouldHide = icon == .battery ? hideBattery : hideWiFi
            let currentlyVisible = readVisibility(icon)

            // Record the pre-change original before the first modification.
            if originalVisibility[icon] == nil {
                originalVisibility[icon] = currentlyVisible
            }

            let targetVisible = !shouldHide
            if currentlyVisible != targetVisible {
                setVisibility(icon, visible: targetVisible)
                changed = true
            }
        }

        if changed {
            scheduleRestart()
        }
    }

    /// Restores every icon the controller has ever hidden back to its recorded
    /// original state. Called on cleanup deactivation so the user's menu bar
    /// returns to its pre-plugin appearance.
    func restore() {
        guard !originalVisibility.isEmpty else { return }
        var changed = false

        for (icon, original) in originalVisibility {
            let current = readVisibility(icon)
            if current != original {
                setVisibility(icon, visible: original)
                changed = true
            }
        }

        originalVisibility.removeAll()
        pendingRestartTask?.cancel()
        pendingRestartTask = nil

        if changed {
            restartControlCenter()
        }
    }

    // MARK: - Private

    private func readVisibility(_ icon: SystemIcon) -> Bool {
        let value = CFPreferencesCopyAppValue(icon.preferenceKey as CFString, Self.appID)
        if let bool = value as? Bool { return bool }
        if let num = value as? NSNumber { return num.boolValue }
        return true // absent key means visible (the default)
    }

    private func setVisibility(_ icon: SystemIcon, visible: Bool) {
        CFPreferencesSetAppValue(
            icon.preferenceKey as CFString,
            (visible ? 1 : 0) as CFTypeRef,
            Self.appID
        )
        CFPreferencesAppSynchronize(Self.appID)
    }

    private func scheduleRestart() {
        pendingRestartTask?.cancel()
        pendingRestartTask = Task { @MainActor [weak self] in
            // Yield once so rapid back-to-back calls coalesce.
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.restartControlCenter()
        }
    }

    private func restartControlCenter() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["ControlCenter"]
        do {
            try task.run()
        } catch {
            AppLog.plugin.error("[DuoStatusPro] Failed to restart ControlCenter: \(error)")
        }
    }
}
