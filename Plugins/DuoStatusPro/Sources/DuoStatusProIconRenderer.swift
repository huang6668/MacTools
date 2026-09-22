import AppKit
import CoreGraphics
import CoreText

// Adapted from Status Trio (https://github.com/lingyired/status-trio, Apache-2.0).

enum StatusTrioIconAppearance: Equatable, Sendable {
    case light
    case dark
}

/// Draws the battery ring, the network glyph, and the volume marks into one
/// menu-bar image. The image is a template unless a status color is in use.
enum StatusTrioIconRenderer {
    static let defaultSize = NSSize(width: 24, height: 24)

    private static let centerSymbolBasePointSize: CGFloat = 38
    /// Bluetooth device glyphs are drawn larger than the Wi-Fi symbol so their
    /// finer detail survives the menu-bar size.
    private static let bluetoothSymbolScale: CGFloat = 1.6
    private static let batteryTextScale: CGFloat = 1.8
    /// Unified optical alpha for all inactive tracks (battery groove, muted
    /// Wi-Fi signal, hidden volume dots).
    private static let inactiveTrackAlpha: CGFloat = 0.22
    /// The first symbol the running system ships wins. `headphones` exists on
    /// every supported macOS release, so the list never renders blank.
    private static let bluetoothSymbolCandidates = [
        "headphones",
        "airpods",
        "hifispeaker.fill",
        "speaker.wave.2"
    ]

    static func image(
        for snapshot: StatusTrioSnapshot,
        options: StatusTrioIconOptions,
        appearance: StatusTrioIconAppearance,
        pointSize: NSSize = defaultSize
    ) -> NSImage {
        let size = validatedSize(pointSize)
        let palette = Palette(appearance: appearance)
        let colorRole = StatusTrioIconMappings.batteryColorRole(snapshot.battery, options: options)
        let replacesNetworkIcon = StatusTrioIconMappings.shouldReplaceNetworkIcon(
            volume: snapshot.volume,
            wifi: snapshot.wifi,
            connection: snapshot.connection,
            options: options
        )
        let usesStatusColor = colorRole != .foreground || replacesNetworkIcon

        let image = NSImage(size: size, flipped: false) { _ in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            draw(
                snapshot,
                options: options,
                colorRole: colorRole,
                replacesNetworkIcon: replacesNetworkIcon,
                palette: palette,
                in: context,
                size: size
            )
            return true
        }
        image.isTemplate = !usesStatusColor
        return image
    }

    // MARK: Colors

    private struct Palette {
        let foreground: NSColor
        let critical: NSColor
        let charging: NSColor
        let lowPower: NSColor
        let bluetooth: NSColor

        init(appearance: StatusTrioIconAppearance) {
            switch appearance {
            case .light:
                foreground = .black
                critical = NSColor(srgbRed: 255.0 / 255.0, green: 59.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
                charging = NSColor(srgbRed: 31.0 / 255.0, green: 143.0 / 255.0, blue: 61.0 / 255.0, alpha: 1)
                lowPower = NSColor(srgbRed: 201.0 / 255.0, green: 151.0 / 255.0, blue: 0, alpha: 1)
                bluetooth = NSColor(srgbRed: 0, green: 102.0 / 255.0, blue: 204.0 / 255.0, alpha: 1)
            case .dark:
                foreground = .white
                critical = NSColor(srgbRed: 255.0 / 255.0, green: 69.0 / 255.0, blue: 58.0 / 255.0, alpha: 1)
                charging = NSColor(srgbRed: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0, alpha: 1)
                lowPower = NSColor(srgbRed: 242.0 / 255.0, green: 185.0 / 255.0, blue: 0, alpha: 1)
                bluetooth = NSColor(srgbRed: 77.0 / 255.0, green: 163.0 / 255.0, blue: 1, alpha: 1)
            }
        }

        var inactive: NSColor { foreground.withAlphaComponent(inactiveTrackAlpha) }

        func color(for role: StatusTrioBatteryColorRole) -> NSColor {
            switch role {
            case .foreground: foreground
            case .critical: critical
            case .charging: charging
            case .lowPower: lowPower
            }
        }
    }

    private static func validatedSize(_ size: NSSize) -> NSSize {
        guard size.width.isFinite, size.height.isFinite, size.width > 0, size.height > 0 else {
            return defaultSize
        }
        return size
    }

    // MARK: Composition

    private static func draw(
        _ snapshot: StatusTrioSnapshot,
        options: StatusTrioIconOptions,
        colorRole: StatusTrioBatteryColorRole,
        replacesNetworkIcon: Bool,
        palette: Palette,
        in context: CGContext,
        size: NSSize
    ) {
        context.saveGState()
        defer { context.restoreGState() }

        // Uniform scale, centered, with the canvas flipped so its origin is top-left.
        let canvas = StatusTrioIconGeometry.canvas
        let scale = min(size.width, size.height) / canvas.width
        let offsetX = (size.width - canvas.width * scale) / 2
        let offsetY = (size.height - canvas.height * scale) / 2
        context.translateBy(x: offsetX, y: offsetY + canvas.height * scale)
        context.scaleBy(x: scale, y: -scale)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        drawBattery(snapshot.battery, options: options, colorRole: colorRole, palette: palette, in: context)

        if replacesNetworkIcon {
            drawBluetoothAudio(palette: palette, in: context)
        } else if snapshot.connection == .ethernet, !options.showsWiFiIconForEthernet {
            drawEthernet(palette: palette, in: context)
        } else if snapshot.connection == .ethernet {
            drawStandardWiFi(snapshot.wifi, palette: palette, in: context)
        } else {
            drawWiFi(snapshot.wifi, options: options, palette: palette, in: context)
        }

        drawVolume(snapshot.volume, options: options, palette: palette, in: context)
    }

    // MARK: Battery

    private static func drawBattery(
        _ battery: StatusTrioBatteryStatus,
        options: StatusTrioIconOptions,
        colorRole: StatusTrioBatteryColorRole,
        palette: Palette,
        in context: CGContext
    ) {
        let gapContent = StatusTrioIconMappings.batteryGapContent(battery, options: options)
        let hasTopGap = gapContent != .empty
        let topGapWidth: CGFloat = switch gapContent {
        case .bolt, .plug: StatusTrioIconGeometry.batteryChargingBoltTopGapWidth
        case .percentage, .empty: StatusTrioIconGeometry.batteryValueTopGapWidth
        }

        context.setLineWidth(8 * options.ringStrokeScale)
        context.setStrokeColor(palette.inactive.cgColor)
        context.addPath(StatusTrioIconGeometry.batteryTrack(hasTopGap: hasTopGap, topGapWidth: topGapWidth))
        context.strokePath()

        context.setStrokeColor(palette.color(for: colorRole).cgColor)
        context.addPath(StatusTrioIconGeometry.batteryFill(
            progress: StatusTrioIconMappings.batteryProgress(battery),
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        ))
        context.strokePath()

        let indicatorScale = batteryChargingBoltScale()
        switch gapContent {
        case .bolt:
            context.setFillColor(palette.foreground.cgColor)
            context.addPath(StatusTrioIconGeometry.batteryChargingBolt(scale: indicatorScale))
            context.fillPath()
        case .plug:
            drawBatteryPlug(boltScale: indicatorScale, foreground: palette.foreground, in: context)
        case .percentage:
            drawBatteryPercentage(battery.percentage, color: palette.foreground, in: context)
        case .empty:
            break
        }
    }

    /// Draws the plug at the bolt's optical size and center, so the ring's top
    /// gap reads the same whichever indicator is showing.
    private static func drawBatteryPlug(boltScale: CGFloat, foreground: NSColor, in context: CGContext) {
        let boltHeight = StatusTrioIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
        let targetHeight = boltHeight * boltScale * StatusTrioIconGeometry.batteryPlugHeightScale
        guard targetHeight.isFinite, targetHeight > 0 else { return }

        drawSymbol(
            name: StatusTrioIconGeometry.batteryPlugSymbolName,
            pointSize: batteryPlugPointSize(targetHeight: targetHeight),
            center: StatusTrioIconGeometry.batteryTopIndicatorCenter(boltScale: boltScale),
            color: foreground,
            in: context
        )
    }

    private static func drawBatteryPercentage(_ percentage: Int, color: NSColor, in context: CGContext) {
        let fontSize = batteryValueFontSize
        let attributes: [NSAttributedString.Key: Any] = [
            .font: batteryValueFont(size: fontSize),
            .kern: -fontSize * 0.04,
            .foregroundColor: color
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: String(percentage), attributes: attributes)
        )
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let baseline = StatusTrioIconGeometry.batteryValueBaseline(fontSize: fontSize)

        context.saveGState()
        defer { context.restoreGState() }
        context.setFillColor(color.cgColor)
        // The canvas is flipped, so glyphs are flipped back to stay upright.
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.textPosition = CGPoint(x: baseline.x - width / 2, y: baseline.y)
        CTLineDraw(line, context)
    }

    private static var batteryValueFontSize: CGFloat {
        StatusTrioIconGeometry.batteryValueBaseFontSize * batteryTextScale
    }

    private static func batteryValueFont(size: CGFloat) -> NSFont {
        let fallback = NSFont.systemFont(ofSize: size, weight: .bold)
        guard let descriptor = fallback.fontDescriptor.withDesign(.rounded) else {
            return fallback
        }
        return NSFont(descriptor: descriptor, size: size) ?? fallback
    }

    /// The bolt is calibrated to match the height of the percentage numerals.
    private static func batteryChargingBoltScale() -> CGFloat {
        let boltHeight = StatusTrioIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
        let targetHeight = batteryTopIndicatorHeight()
        guard boltHeight.isFinite, boltHeight > 0, targetHeight > 0 else {
            return StatusTrioIconGeometry.batteryChargingBoltCalibration
        }
        return targetHeight / boltHeight
    }

    private static func batteryTopIndicatorHeight() -> CGFloat {
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(
                string: "100",
                attributes: [.font: batteryValueFont(size: batteryValueFontSize)]
            )
        )
        let glyphHeight = CTLineGetBoundsWithOptions(line, [.useGlyphPathBounds]).height
        guard glyphHeight.isFinite, glyphHeight > 0 else {
            return StatusTrioIconGeometry.batteryChargingBolt().boundingBoxOfPath.height
                * StatusTrioIconGeometry.batteryChargingBoltCalibration
        }
        return glyphHeight * StatusTrioIconGeometry.batteryChargingBoltCalibration
    }

    /// Glyph height per point of symbol size. SF Symbols report sizes rounded
    /// to whole points, so the reference size is large enough for the rounding
    /// to be negligible.
    private static func batteryPlugHeightPerPoint() -> CGFloat {
        let referencePointSize: CGFloat = 200
        guard let height = configuredSymbol(
            name: StatusTrioIconGeometry.batteryPlugSymbolName,
            pointSize: referencePointSize,
            color: .black
        )?.size.height, height.isFinite, height > 0 else {
            return 1.34
        }
        return height / referencePointSize
    }

    private static func batteryPlugPointSize(targetHeight: CGFloat) -> CGFloat {
        let fallbackPointSize: CGFloat = 38
        let pointSize = targetHeight / batteryPlugHeightPerPoint()
        return pointSize.isFinite && pointSize > 0 ? pointSize : fallbackPointSize
    }

    // MARK: Network

    private static func drawWiFi(
        _ wifi: StatusTrioWiFiStatus,
        options: StatusTrioIconOptions,
        palette: Palette,
        in context: CGContext
    ) {
        switch wifi.state {
        case .connected:
            drawStandardWiFi(wifi, palette: palette, in: context)
        case .notAssociated:
            drawSymbol(name: "wifi", variableValue: 0, pointSize: centerSymbolBasePointSize, color: palette.foreground, in: context)
        case .off, .unavailable:
            drawSymbol(name: "wifi.slash", pointSize: centerSymbolBasePointSize, color: palette.foreground, in: context)
        case .noInternet:
            drawSymbol(name: "wifi.exclamationmark", pointSize: centerSymbolBasePointSize, color: palette.foreground, in: context)
        case .hotspot where options.showsWiFiIconForHotspot:
            drawStandardWiFi(wifi, palette: palette, in: context)
        case .hotspot:
            drawSymbol(name: "personalhotspot", pointSize: centerSymbolBasePointSize, color: palette.foreground, in: context)
        case .temporary where options.showsWiFiIconForTemporary:
            drawStandardWiFi(wifi, palette: palette, in: context)
        case .temporary:
            drawTemporaryConnectionMark(foreground: palette.foreground, in: context)
        case .shared where options.showsWiFiIconForInternetSharing:
            drawStandardWiFi(wifi, palette: palette, in: context)
        case .shared:
            drawSharedConnectionMark(foreground: palette.foreground, in: context)
        }
    }

    private static func drawStandardWiFi(_ wifi: StatusTrioWiFiStatus, palette: Palette, in context: CGContext) {
        let bars = StatusTrioIconMappings.wifiBars(rssi: wifi.rssi)
        guard bars > 0 else {
            drawSymbol(name: "wifi", variableValue: 0, pointSize: centerSymbolBasePointSize, color: palette.inactive, in: context)
            return
        }
        drawSymbol(
            name: "wifi",
            variableValue: Double(bars) / 3,
            pointSize: centerSymbolBasePointSize,
            color: palette.foreground,
            in: context
        )
    }

    private static func drawEthernet(palette: Palette, in context: CGContext) {
        context.setStrokeColor(palette.foreground.cgColor)
        context.setLineWidth(StatusTrioIconGeometry.ethernetStrokeWidth)
        for path in StatusTrioIconGeometry.ethernetChevrons() {
            context.addPath(path)
            context.strokePath()
        }

        context.setFillColor(palette.foreground.cgColor)
        let radius = StatusTrioIconGeometry.ethernetDotRadius
        for point in StatusTrioIconGeometry.ethernetDots() {
            context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
        }
    }

    private static func drawTemporaryConnectionMark(foreground: NSColor, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }

        context.setFillColor(foreground.cgColor)
        context.setStrokeColor(foreground.cgColor)
        context.setLineWidth(7)
        context.addPath(StatusTrioIconGeometry.temporaryWedge())
        context.drawPath(using: .fillStroke)

        context.saveGState()
        context.setBlendMode(.clear)
        context.setLineWidth(2.5)
        context.addPath(StatusTrioIconGeometry.temporaryScreenOutline())
        context.strokePath()
        context.addPath(StatusTrioIconGeometry.temporaryScreenStand())
        context.fillPath()
        context.restoreGState()
    }

    private static func drawSharedConnectionMark(foreground: NSColor, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }

        context.setFillColor(foreground.cgColor)
        context.setStrokeColor(foreground.cgColor)
        context.setLineWidth(7)
        context.addPath(StatusTrioIconGeometry.sharedWedge())
        context.drawPath(using: .fillStroke)

        context.saveGState()
        context.setBlendMode(.clear)
        context.addPath(StatusTrioIconGeometry.sharedArrowCutout())
        context.fillPath()
        context.restoreGState()
    }

    private static func drawBluetoothAudio(palette: Palette, in context: CGContext) {
        guard let name = bluetoothSymbolCandidates.first(where: {
            NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil
        }) else {
            return
        }
        drawSymbol(
            name: name,
            pointSize: centerSymbolBasePointSize * bluetoothSymbolScale,
            color: palette.bluetooth,
            in: context
        )
    }

    // MARK: Volume

    private static func drawVolume(
        _ volume: StatusTrioVolumeStatus,
        options: StatusTrioIconOptions,
        palette: Palette,
        in context: CGContext
    ) {
        let hiddenColor = palette.inactive.cgColor
        let activeColor = palette.foreground.cgColor

        switch options.volumeDisplayStyle {
        case .dots:
            let level = StatusTrioIconMappings.volumeSteps(scalar: volume.scalar, isMuted: volume.isMuted)
            let radius = StatusTrioIconGeometry.volumeDotRadius * options.volumeDotRadiusScale
            for (index, point) in StatusTrioIconGeometry.volumeDots().enumerated() {
                context.setFillColor(index < level ? activeColor : hiddenColor)
                context.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
            }
        case .arc:
            context.setLineWidth(7 * options.ringStrokeScale)
            context.setStrokeColor(hiddenColor)
            context.addPath(StatusTrioIconGeometry.volumeArcTrack())
            context.strokePath()

            guard !volume.isMuted, let scalar = volume.scalar, scalar.isFinite, scalar > 0 else { return }
            context.setStrokeColor(activeColor)
            context.addPath(StatusTrioIconGeometry.volumeArcFill(progress: scalar))
            context.strokePath()
        }
    }

    // MARK: SF Symbols

    /// Draws a symbol centered on a canvas point. A symbol the running system
    /// does not ship draws nothing.
    private static func drawSymbol(
        name: String,
        variableValue: Double? = nil,
        pointSize: CGFloat,
        center: CGPoint = StatusTrioIconGeometry.centerSymbolCenter,
        color: NSColor,
        in context: CGContext
    ) {
        guard let symbol = configuredSymbol(name: name, variableValue: variableValue, pointSize: pointSize, color: color) else {
            return
        }

        context.saveGState()
        defer { context.restoreGState() }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

        // Flip back to an upright orientation for AppKit image drawing.
        context.scaleBy(x: 1, y: -1)
        let targetRect = CGRect(
            x: center.x - symbol.size.width / 2,
            y: -(center.y + symbol.size.height / 2),
            width: symbol.size.width,
            height: symbol.size.height
        )
        symbol.draw(in: targetRect)
    }

    private static func configuredSymbol(
        name: String,
        variableValue: Double? = nil,
        pointSize: CGFloat,
        color: NSColor
    ) -> NSImage? {
        let base: NSImage?
        if let variableValue {
            base = NSImage(systemSymbolName: name, variableValue: variableValue, accessibilityDescription: nil)
                ?? NSImage(systemSymbolName: name, accessibilityDescription: nil)
        } else {
            base = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        guard let base else { return nil }

        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(.init(hierarchicalColor: color))
        return base.withSymbolConfiguration(configuration)
    }
}
