import AppKit
import XCTest
@testable import DuoStatusProPlugin

@MainActor
final class DuoStatusProIconRendererTests: XCTestCase {
    func testImageUsesRequestedSizeAndDrawsInsideBounds() throws {
        let image = DuoStatusProIconRenderer.image(for: connectedSnapshot, options: .default, appearance: .light)
        XCTAssertEqual(image.size, DuoStatusProIconRenderer.defaultSize)
        let pixels = try alphaPixels(image)
        XCTAssertTrue(pixels.contains { $0 > 0 })

        let custom = DuoStatusProIconRenderer.image(
            for: connectedSnapshot, options: .default, appearance: .dark, pointSize: NSSize(width: 44, height: 30)
        )
        XCTAssertEqual(custom.size, NSSize(width: 44, height: 30))
        XCTAssertTrue(try alphaPixels(custom).contains { $0 > 0 })
    }

    func testNeutralStateIsTemplateAndStatusColorsAreNot() throws {
        let neutral = DuoStatusProIconRenderer.image(for: connectedSnapshot, options: .default, appearance: .light)
        XCTAssertTrue(neutral.isTemplate)
        XCTAssertFalse(try rgbaPixels(neutral).contains { $0.isRed || $0.isGreen || $0.isBlue })

        var charging = connectedSnapshot
        charging.battery.isCharging = true
        charging.battery.isConnectedToPower = true
        let chargingImage = DuoStatusProIconRenderer.image(for: charging, options: .default, appearance: .light)
        XCTAssertFalse(chargingImage.isTemplate)
        XCTAssertTrue(try rgbaPixels(chargingImage).contains(where: \.isGreen))

        var critical = connectedSnapshot
        critical.battery.rawPercentage = 10
        let criticalImage = DuoStatusProIconRenderer.image(for: critical, options: .default, appearance: .light)
        XCTAssertFalse(criticalImage.isTemplate)
        XCTAssertTrue(try rgbaPixels(criticalImage).contains(where: \.isRed))

        var bluetooth = connectedSnapshot
        bluetooth.volume.isBluetoothOutput = true
        let bluetoothImage = DuoStatusProIconRenderer.image(for: bluetooth, options: .default, appearance: .light)
        XCTAssertFalse(bluetoothImage.isTemplate)
        XCTAssertTrue(try rgbaPixels(bluetoothImage).contains(where: \.isBlue))
    }

    func testDisabledStatusColorsKeepTemplateForChargingAndCritical() throws {
        var options = DuoStatusProIconOptions.default
        options.usesBatteryStatusColors = false
        var charging = connectedSnapshot
        charging.battery.isCharging = true
        charging.battery.rawPercentage = 5
        let image = DuoStatusProIconRenderer.image(for: charging, options: options, appearance: .light)
        XCTAssertTrue(image.isTemplate)
        XCTAssertFalse(try rgbaPixels(image).contains { $0.isRed || $0.isGreen })
    }

    func testBluetoothGlyphYieldsToNetworkErrorWhenPrioritized() throws {
        var snapshot = connectedSnapshot
        snapshot.volume.isBluetoothOutput = true
        snapshot.wifi = DuoStatusProWiFiStatus(state: .off)
        let image = DuoStatusProIconRenderer.image(for: snapshot, options: .default, appearance: .light)
        XCTAssertTrue(image.isTemplate)
        XCTAssertFalse(try rgbaPixels(image).contains(where: \.isBlue))
    }

    func testLowBatteryChangesRingCoverageOnly() throws {
        let full = try alphaPixels(DuoStatusProIconRenderer.image(for: connectedSnapshot, options: .default, appearance: .light))
        var low = connectedSnapshot
        low.battery.rawPercentage = 10
        let lowPixels = try alphaPixels(DuoStatusProIconRenderer.image(for: low, options: .default, appearance: .light))

        XCTAssertNotEqual(full, lowPixels)
        // The right half of the ring drops from solid to the faint track.
        let fullRing = region(full, x: 36..<48, y: 8..<40)
        let lowRing = region(lowPixels, x: 36..<48, y: 8..<40)
        XCTAssertNotEqual(fullRing, lowRing)
        XCTAssertGreaterThan(try XCTUnwrap(fullRing.max()), try XCTUnwrap(lowRing.max()))
        // The center glyph is unaffected by battery level.
        XCTAssertEqual(region(full, x: 14..<34, y: 14..<34), region(lowPixels, x: 14..<34, y: 14..<34))
    }

    func testDarkAppearanceDrawsWhiteForegroundWhenColored() throws {
        var charging = connectedSnapshot
        charging.battery.isCharging = true
        let light = try rgbaPixels(DuoStatusProIconRenderer.image(for: charging, options: .default, appearance: .light))
        let dark = try rgbaPixels(DuoStatusProIconRenderer.image(for: charging, options: .default, appearance: .dark))
        XCTAssertTrue(light.contains { $0.alpha > 200 && max($0.red, $0.green, $0.blue) < 10 })
        XCTAssertTrue(dark.contains { min($0.red, $0.green, $0.blue, $0.alpha) > 200 })
        XCTAssertTrue(dark.contains(where: \.isGreen))
    }

    func testTopGapContentDiffersBetweenBoltPlugPercentageAndEmpty() throws {
        let empty = try alphaPixels(DuoStatusProIconRenderer.image(for: connectedSnapshot, options: .default, appearance: .light))

        var charging = connectedSnapshot
        charging.battery.isCharging = true
        charging.battery.isConnectedToPower = true
        let bolt = try alphaPixels(DuoStatusProIconRenderer.image(for: charging, options: .default, appearance: .light))

        var plugged = connectedSnapshot
        plugged.battery.isConnectedToPower = true
        let plug = try alphaPixels(DuoStatusProIconRenderer.image(for: plugged, options: .default, appearance: .light))

        var percentageOptions = DuoStatusProIconOptions.default
        percentageOptions.showsBatteryPercentage = true
        let percentage = try alphaPixels(DuoStatusProIconRenderer.image(for: connectedSnapshot, options: percentageOptions, appearance: .light))

        let top = { (pixels: [UInt8]) in self.region(pixels, x: 0..<48, y: 34..<48) }
        XCTAssertNotEqual(top(empty), top(bolt))
        XCTAssertNotEqual(top(bolt), top(plug))
        XCTAssertNotEqual(top(plug), top(percentage))
        XCTAssertNotEqual(top(percentage), top(empty))
        // Only a single alpha level of platform-specific antialiasing may vary below the top gap.
        XCTAssertLessThanOrEqual(
            maximumAlphaDifference(
                region(empty, x: 0..<48, y: 0..<14),
                region(bolt, x: 0..<48, y: 0..<14)
            ),
            1
        )
    }

    func testVolumeDotsAndArcDifferAndTrackLevel() throws {
        let dots = try alphaPixels(DuoStatusProIconRenderer.image(for: connectedSnapshot, options: .default, appearance: .light))
        var arcOptions = DuoStatusProIconOptions.default
        arcOptions.volumeDisplayStyle = .arc
        let arc = try alphaPixels(DuoStatusProIconRenderer.image(for: connectedSnapshot, options: arcOptions, appearance: .light))
        XCTAssertNotEqual(region(dots, x: 0..<48, y: 0..<10), region(arc, x: 0..<48, y: 0..<10))
        XCTAssertEqual(region(dots, x: 0..<48, y: 14..<48), region(arc, x: 0..<48, y: 14..<48))

        var muted = connectedSnapshot
        muted.volume.isMuted = true
        let mutedDots = try alphaPixels(DuoStatusProIconRenderer.image(for: muted, options: .default, appearance: .light))
        XCTAssertNotEqual(region(dots, x: 0..<48, y: 0..<10), region(mutedDots, x: 0..<48, y: 0..<10))
        XCTAssertGreaterThan(try XCTUnwrap(region(dots, x: 0..<48, y: 0..<10).max()), try XCTUnwrap(region(mutedDots, x: 0..<48, y: 0..<10).max()))
    }

    func testNetworkStatesProduceDistinctCenterGlyphs() throws {
        let center = { (image: NSImage) in try self.region(self.alphaPixels(image), x: 14..<34, y: 14..<34) }
        let connected = try center(DuoStatusProIconRenderer.image(for: connectedSnapshot, options: .default, appearance: .light))
        XCTAssertTrue(connected.contains { $0 > 0 })

        var seen: [[UInt8]] = [connected]
        for state: DuoStatusProWiFiState in [.off, .noInternet, .hotspot, .temporary, .shared, .notAssociated] {
            var snapshot = connectedSnapshot
            snapshot.wifi = DuoStatusProWiFiStatus(state: state)
            let glyph = try center(DuoStatusProIconRenderer.image(for: snapshot, options: .default, appearance: .light))
            XCTAssertTrue(glyph.contains { $0 > 0 }, "\(state) should draw a center glyph")
            XCTAssertFalse(seen.contains(glyph), "\(state) should not repeat another state's glyph")
            seen.append(glyph)
        }

        var ethernet = connectedSnapshot
        ethernet.connection = .ethernet
        let ethernetGlyph = try center(DuoStatusProIconRenderer.image(for: ethernet, options: .default, appearance: .light))
        XCTAssertNotEqual(ethernetGlyph, connected)

        var wifiForEthernet = DuoStatusProIconOptions.default
        wifiForEthernet.showsWiFiIconForEthernet = true
        XCTAssertEqual(try center(DuoStatusProIconRenderer.image(for: ethernet, options: wifiForEthernet, appearance: .light)), connected)
    }

    func testWeakSignalChangesWiFiGlyphWithoutTouchingRing() throws {
        let strong = try alphaPixels(DuoStatusProIconRenderer.image(for: connectedSnapshot, options: .default, appearance: .light))
        var weak = connectedSnapshot
        weak.wifi.rssi = -85
        let weakPixels = try alphaPixels(DuoStatusProIconRenderer.image(for: weak, options: .default, appearance: .light))
        XCTAssertNotEqual(region(strong, x: 14..<34, y: 14..<34), region(weakPixels, x: 14..<34, y: 14..<34))
        XCTAssertEqual(region(strong, x: 0..<8, y: 8..<40), region(weakPixels, x: 0..<8, y: 8..<40))
    }

    // MARK: Helpers

    private var connectedSnapshot: DuoStatusProSnapshot {
        var snapshot = DuoStatusProSnapshot()
        snapshot.battery = DuoStatusProBatteryStatus(rawPercentage: 80, isPresent: true)
        snapshot.wifi = DuoStatusProWiFiStatus(state: .connected, rssi: -50)
        snapshot.connection = .wifi
        snapshot.volume = DuoStatusProVolumeStatus(scalar: 0.5)
        return snapshot
    }

    private struct Pixel {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8

        var isGreen: Bool { alpha > 15 && Int(green) > Int(red) + 20 && Int(green) > Int(blue) + 20 }
        var isRed: Bool { alpha > 15 && Int(red) > Int(green) + 20 && Int(red) > Int(blue) + 20 }
        var isBlue: Bool { alpha > 15 && Int(blue) > Int(red) + 20 && Int(blue) > Int(green) + 20 }
    }

    private func alphaPixels(_ image: NSImage) throws -> [UInt8] {
        try rgbaPixels(image).map(\.alpha)
    }

    /// Rasterizes a square image at 2x into a 48 x 48 premultiplied RGBA grid.
    private func rgbaPixels(_ image: NSImage, scale: CGFloat = 2) throws -> [Pixel] {
        let width = Int(image.size.width * scale)
        let height = Int(image.size.height * scale)
        let context = try XCTUnwrap(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        context.scaleBy(x: scale, y: scale)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        let data = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<(width * height)).map {
            Pixel(red: data[$0 * 4], green: data[$0 * 4 + 1], blue: data[$0 * 4 + 2], alpha: data[$0 * 4 + 3])
        }
    }

    /// Samples a 48 x 48 grid in artwork coordinates: y grows upward from the bottom edge.
    private func region(_ pixels: [UInt8], x: Range<Int>, y: Range<Int>) -> [UInt8] {
        y.flatMap { row in x.map { column in pixels[(47 - row) * 48 + column] } }
    }

    private func maximumAlphaDifference(_ lhs: [UInt8], _ rhs: [UInt8]) -> Int {
        zip(lhs, rhs).map { abs(Int($0) - Int($1)) }.max() ?? 0
    }
}
