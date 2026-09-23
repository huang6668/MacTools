# Duo Status Pro

Duo Status Pro (`duo-status-pro`) is a PluginKit v7 plugin for MacTools 1.3.1 or later. It displays one menu-bar icon that combines the Mac's battery level, Wi-Fi or network connection, and output volume: a battery ring around the outside, a network glyph in the center, and volume dots or an arc along the edge. When audio plays through a Bluetooth device, the center can show a Bluetooth glyph instead. It can also hide the system battery and Wi-Fi icons so the combined icon replaces them.

The icon and its rendering rules are adapted from the [Status Trio](https://github.com/lingyired/status-trio) project by lingyired, licensed under the [Apache License 2.0](../../Sources/Resources/ThirdPartyNotices/status-trio-LICENSE.txt). Only the combined menu-bar icon is ported; the upstream popover, Dock presence, and other surfaces are not part of this plugin.

## Use

Install the plugin from the Marketplace. **Duo Status Pro > Menu Bar > Display Mode** offers **Separate Icon** (default) and **Replace App Icon**. There is no additional visibility switch, Dashboard component, or Feature Panel entry. Hover for battery, Wi-Fi, connection, and volume details. With a separate icon, either mouse button opens plugin settings. With replacement, the original MacTools panel click behavior is preserved.

Replacement uses the [host's exclusive icon interface](menu-bar-icons.md), not direct access to its button. If another plugin such as Duo Status already owns the primary icon, the mode remains unchanged and an inline error names that plugin; pending updates instead explain that a restart is needed to access its settings. Switching back or uninstalling restores the original MacTools artwork, including custom or animated icons. The host keeps its click behavior, saved position, and automation badge. Separate mode has its own status item and saved position.

- The outer ring fills with the battery percentage. Macs without an internal battery keep a full ring so the icon stays stable.
- With status colors enabled, the ring is red below the critical threshold, yellow in Low Power Mode, and green while charging or on external power; a critical level takes precedence. With colors disabled, the ring follows the menu bar's monochrome appearance.
- A lightning bolt marks active charging; a plug marks external power with charging paused or complete, unless you prefer the percentage in that state. Both indicators can be hidden.
- The center shows Wi-Fi signal strength when Wi-Fi is the active connection. Ethernet, personal hotspot, temporary networks, and Internet Sharing use their own glyphs unless you choose to draw them as Wi-Fi. Wi-Fi off, not associated, or without internet is distinguished from a connected network.
- Volume is shown as up to four dots or as a continuous arc. Muted or silent output shows no active dots, while a missing output device remains explicit.
- When the default output device uses Bluetooth, the Bluetooth glyph can replace the network glyph. Network problems can still take priority over the Bluetooth glyph.

The icon uses inset vector artwork inside the host's 24-point canvas, follows the menu bar's effective appearance including wallpaper and display changes, and renders at the display's native scale. Tooltip and accessibility copy follow the host's selected language.

## Settings

All settings apply immediately to both display modes.

- **Battery**: show the percentage inside the ring, optionally only while connected to power; show the charging indicator; use status colors; set the critical threshold used for the red ring.
- **Network**: draw Ethernet, personal hotspot, temporary networks, or Internet Sharing with the Wi-Fi icon instead of their dedicated glyphs.
- **Volume**: choose dots or an arc.
- **Bluetooth**: let a Bluetooth output device replace the network glyph, and choose whether network errors still win.
- **Ring**: pick a light, regular, or bold stroke weight. Volume dots scale with the ring so the icon stays balanced.
- **Menu Bar**: hide the system battery icon and the system Wi-Fi icon independently, so this plugin's combined icon replaces them instead of sitting beside them. On macOS 26 and later, the plugin opens System Settings > Control Center instead, where the same menu-bar controls are available.

### Hiding the system battery and Wi-Fi icons

On macOS 25 and earlier, the two hide switches are independent: hide only the battery, only Wi-Fi, both, or neither. Each writes the matching Control Center visibility preference and restarts Control Center, which briefly refreshes the menu bar. macOS owns these icons, so a short flicker during the restart is expected.

The plugin records each icon's visibility before its first change and restores that recorded state when you turn the switch off, or when the plugin is disabled or uninstalled. Hot updates intentionally skip the restore, because the process restart completes the unload. If Control Center does not pick up a change, toggling the switch again reapplies it.

On macOS 26 and later, ControlCenter no longer reads the preference key used by the switches, so the plugin offers a single action under **Menu Bar** that opens **System Settings > Control Center**. Use the native Battery and Wi-Fi menu-bar controls there instead.

## Lifecycle and privacy

Battery, Wi-Fi, network-path, and audio reads run off the main thread. Power-source notifications, network-path changes, and default-output-device or volume changes request updates; a tolerant timer refreshes Wi-Fi signal strength. Read requests coalesce, unchanged snapshots do not redraw the icon, and callbacks from a stopped monitoring generation are discarded.

Losing the host capability, disabling or uninstalling the plugin, and replacing the plugin during an update stop monitoring and remove its separate status item. The host restores its primary icon before teardown. Switching display mode shares the existing monitor without restarting it. Locking or sleeping pauses monitoring; interactive activity resumes it with a fresh snapshot. Settings and image getters never query hardware synchronously.

The plugin uses native IOKit, CoreWLAN, Network, SystemConfiguration, and CoreAudio APIs. It does not read SSIDs, request location access, test internet endpoints, collect history, use the network, or send telemetry. It persists only its own icon settings; placement is stored by the host and is not duplicated in plugin preferences. Unknown and unavailable hardware states remain explicit.

On macOS 25 and earlier, hiding the system icons writes only the two Control Center menu-bar visibility preferences and restarts Control Center. It reads no other Control Center settings and changes nothing else in the user's menu bar. On macOS 26 and later, the action only opens the Apple System Settings page and performs no writes.

## Development

Plugin implementation, localization, and adjacent tests live under `Plugins/DuoStatusPro`. Its `project.yml` declares only the required system frameworks. Generic primary-icon arbitration lives in Core and the optional public contracts live in PluginKit; the host does not contain Duo Status Pro-specific rendering or settings. Source files adapted from upstream carry an attribution comment, and the retained license text is listed in `Sources/Resources/ThirdPartyNotices/manifest.json`.

```sh
make generate
make build-plugin PLUGIN=DuoStatusPro
xcodebuild -project MacTools.xcodeproj -scheme MacTools -configuration Debug \
  -derivedDataPath build/DerivedData test -quiet \
  -only-testing:MacToolsTests/DuoStatusProPluginTests \
  -only-testing:MacToolsTests/DuoStatusProIconRendererTests \
  -only-testing:MacToolsTests/DuoStatusProIconMappingsTests \
  -only-testing:MacToolsTests/DuoStatusProSystemMonitorTests \
  -only-testing:MacToolsTests/DuoStatusProWiFiClassifierTests \
  -only-testing:MacToolsTests/DuoStatusProSystemIconControllerTests
make script-tests
```

Tests use synthetic readings, isolated notification centers, in-memory preferences, and fake menu-bar presenters. They cover snapshot normalization, option-driven rendering, stale callback rejection, settings persistence, host activity, and resource cleanup without changing the developer's menu bar or querying real hardware.
