import CoreGraphics
import Foundation

// Adapted from Status Trio (https://github.com/lingyired/status-trio, Apache-2.0).

/// Vector paths for the menu-bar glyph, expressed on a 120 x 120 canvas whose
/// origin is the top-left corner (y grows downward). The renderer scales and
/// flips the canvas into the requested point size.
enum DuoStatusProIconGeometry {
    static let canvas = CGRect(x: 0, y: 0, width: 120, height: 120)

    // Derived from the SVG battery endpoints and radius.
    private static let batteryRadius: CGFloat = 51.5
    private static let batteryCenter = CGPoint(x: 59.5, y: 61.48715261785473)
    private static let batteryStart: CGFloat = 148.69008689281117 * .pi / 180
    private static let batterySweep: CGFloat = 242.6198262143777 * .pi / 180
    static let batteryValueTopGapWidth: CGFloat = 64
    static let batteryChargingBoltTopGapWidth: CGFloat = 50

    static let batteryValueBaseFontSize: CGFloat = 20
    static let batteryChargingBoltCalibration: CGFloat = 220.0 / 180.0

    /// SF Symbol drawn in the top gap when the battery is connected to power
    /// without charging.
    static let batteryPlugSymbolName = "powerplug.portrait.fill"

    /// Optical size of the plug relative to the bolt. The plug's strokes are
    /// thinner than the bolt's solid body, so it is drawn slightly taller to
    /// carry the same visual weight in the gap.
    static let batteryPlugHeightScale: CGFloat = 1.2

    static let batteryChargingBoltPivot = CGPoint(x: 59.5, y: 2.1)

    /// The bolt scales away from its tip, so any other glyph in the top gap
    /// shares the scaled bolt's center to stay optically aligned with it.
    static func batteryTopIndicatorCenter(boltScale: CGFloat) -> CGPoint {
        let bolt = batteryChargingBolt().boundingBoxOfPath
        let pivot = batteryChargingBoltPivot
        return CGPoint(
            x: pivot.x + (bolt.midX - pivot.x) * boltScale,
            y: pivot.y + (bolt.midY - pivot.y) * boltScale
        )
    }

    static func batteryValueBaseline(fontSize: CGFloat) -> CGPoint {
        let referenceFontSize: CGFloat = 20
        let referenceBaseline: CGFloat = 17
        let currentFontSize: CGFloat = 32
        let currentBaseline: CGFloat = 24
        let slope = (currentBaseline - referenceBaseline) / (currentFontSize - referenceFontSize)
        return CGPoint(
            x: 59.5,
            y: referenceBaseline + (fontSize - referenceFontSize) * slope
        )
    }

    /// Optical center shared by every SF Symbol drawn in the middle of the ring.
    static let centerSymbolCenter = CGPoint(x: canvas.midX, y: 64.0)

    private static let wifiOuterCenter = CGPoint(x: 59.5, y: 78.3)
    private static let wifiOuterRadius: CGFloat = 31
    private static let wifiOuterStart: CGFloat = 227.35 * .pi / 180
    private static let wifiOuterEnd: CGFloat = 312.65 * .pi / 180

    static func batteryTrack(
        hasTopGap: Bool = false,
        topGapWidth: CGFloat = batteryChargingBoltTopGapWidth
    ) -> CGPath {
        batteryArc(progress: 1, hasTopGap: hasTopGap, topGapWidth: topGapWidth)
    }

    static func batteryFill(
        progress: Double,
        hasTopGap: Bool = false,
        topGapWidth: CGFloat = batteryChargingBoltTopGapWidth
    ) -> CGPath {
        let clamped = min(1, max(0, progress))
        guard clamped > 0 else { return CGMutablePath() }
        return batteryArc(
            progress: clamped,
            hasTopGap: hasTopGap,
            topGapWidth: topGapWidth
        )
    }

    static func batteryChargingBolt(scale: CGFloat = 1) -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 62.1, y: 2.2))
        path.addQuadCurve(
            to: CGPoint(x: 62.6, y: 3.3),
            control: CGPoint(x: 62.8, y: 2.5)
        )
        path.addLine(to: CGPoint(x: 61.2, y: 7.8))
        path.addLine(to: CGPoint(x: 65.9, y: 7.8))
        path.addQuadCurve(
            to: CGPoint(x: 67.3, y: 8.6),
            control: CGPoint(x: 66.9, y: 7.8)
        )
        path.addQuadCurve(
            to: CGPoint(x: 67, y: 10),
            control: CGPoint(x: 67.6, y: 9.3)
        )
        path.addLine(to: CGPoint(x: 57, y: 21.3))
        path.addQuadCurve(
            to: CGPoint(x: 55.6, y: 21.6),
            control: CGPoint(x: 56.4, y: 22)
        )
        path.addQuadCurve(
            to: CGPoint(x: 55.3, y: 20.5),
            control: CGPoint(x: 55, y: 21.3)
        )
        path.addLine(to: CGPoint(x: 57.4, y: 14.1))
        path.addLine(to: CGPoint(x: 52.9, y: 14.1))
        path.addQuadCurve(
            to: CGPoint(x: 51.6, y: 13.3),
            control: CGPoint(x: 52, y: 14.1)
        )
        path.addQuadCurve(
            to: CGPoint(x: 51.9, y: 12),
            control: CGPoint(x: 51.3, y: 12.6)
        )
        path.addLine(to: CGPoint(x: 61.1, y: 2.7))
        path.addQuadCurve(
            to: CGPoint(x: 62.1, y: 2.2),
            control: CGPoint(x: 61.6, y: 2.1)
        )
        path.closeSubpath()

        guard scale.isFinite, scale > 0, scale != 1 else { return path }
        let pivot = batteryChargingBoltPivot
        var transform = CGAffineTransform(
            a: scale,
            b: 0,
            c: 0,
            d: scale,
            tx: pivot.x * (1 - scale),
            ty: pivot.y * (1 - scale)
        )
        return path.copy(using: &transform) ?? path
    }

    static func wifiOuterArc() -> CGPath {
        arc(
            center: wifiOuterCenter,
            radius: wifiOuterRadius,
            start: wifiOuterStart,
            end: wifiOuterEnd
        )
    }

    // MARK: Ethernet

    static let ethernetStrokeWidth: CGFloat = 4.886659979939819
    static let ethernetDotRadius: CGFloat = 2.4433299899699095

    private static let ethernetSourceBounds = CGRect(
        x: 56.132,
        y: 75.812,
        width: 87.736,
        height: 46.376
    )
    private static let ethernetTargetBounds = CGRect(
        x: 31.5,
        y: 51.19959879638917,
        width: 56,
        height: 29.60080240722166
    )

    static func ethernetChevrons() -> [CGPath] {
        let left = ethernetPolyline([
            CGPoint(x: 79.32, y: 79.64),
            CGPoint(x: 59.96, y: 99),
            CGPoint(x: 79.32, y: 118.36)
        ])
        let right = ethernetPolyline([
            CGPoint(x: 120.68, y: 79.64),
            CGPoint(x: 140.04, y: 99),
            CGPoint(x: 120.68, y: 118.36)
        ])
        return [left, right]
    }

    static func ethernetDots() -> [CGPoint] {
        [
            ethernetPoint(x: 84.688, y: 99),
            ethernetPoint(x: 100, y: 99),
            ethernetPoint(x: 115.312, y: 99)
        ]
    }

    private static func ethernetPolyline(_ points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: ethernetPoint(x: first.x, y: first.y))
        for point in points.dropFirst() {
            path.addLine(to: ethernetPoint(x: point.x, y: point.y))
        }
        return path
    }

    private static func ethernetPoint(x: CGFloat, y: CGFloat) -> CGPoint {
        let scaleX = ethernetTargetBounds.width / ethernetSourceBounds.width
        let scaleY = ethernetTargetBounds.height / ethernetSourceBounds.height
        return CGPoint(
            x: ethernetTargetBounds.minX + (x - ethernetSourceBounds.minX) * scaleX,
            y: ethernetTargetBounds.minY + (y - ethernetSourceBounds.minY) * scaleY
        )
    }

    // MARK: Temporary and shared connection marks

    static func temporaryWedge() -> CGPath {
        let path = CGMutablePath()
        path.addPath(wifiOuterArc())
        path.addLine(to: CGPoint(x: 59.5, y: 77.45))
        path.closeSubpath()
        return path
    }

    static func temporaryScreenOutline() -> CGPath {
        let path = CGMutablePath()
        path.addRoundedRect(
            in: CGRect(x: 50.5, y: 53.5, width: 18, height: 12),
            cornerWidth: 2.5,
            cornerHeight: 2.5
        )
        return path
    }

    static func temporaryScreenStand() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 57.5, y: 65.5))
        path.addLine(to: CGPoint(x: 61.5, y: 65.5))
        path.addLine(to: CGPoint(x: 61.5, y: 67.5))
        path.addLine(to: CGPoint(x: 63, y: 67.5))
        path.addLine(to: CGPoint(x: 63, y: 70.5))
        path.addLine(to: CGPoint(x: 56, y: 70.5))
        path.addLine(to: CGPoint(x: 56, y: 67.5))
        path.addLine(to: CGPoint(x: 57.5, y: 67.5))
        path.closeSubpath()
        return path
    }

    static func sharedWedge() -> CGPath {
        temporaryWedge()
    }

    static func sharedArrowCutout() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 59.5, y: 51.5))
        path.addLine(to: CGPoint(x: 67.5, y: 59.5))
        path.addLine(to: CGPoint(x: 63, y: 59.5))
        path.addLine(to: CGPoint(x: 63, y: 72.5))
        path.addLine(to: CGPoint(x: 56, y: 72.5))
        path.addLine(to: CGPoint(x: 56, y: 59.5))
        path.addLine(to: CGPoint(x: 51.5, y: 59.5))
        path.closeSubpath()
        return path
    }

    // MARK: Volume

    static func volumeDots() -> [CGPoint] {
        [
            CGPoint(x: 33, y: 104.2),
            CGPoint(x: 50.5, y: 111.2),
            CGPoint(x: 68.5, y: 111.7),
            CGPoint(x: 86, y: 105.8)
        ]
    }

    static let volumeDotRadius: CGFloat = 5.5

    static let volumeArcStartAngle: CGFloat = 121.82 * .pi / 180
    static let volumeArcEndAngle: CGFloat = 59.12 * .pi / 180

    static func volumeArcTrack() -> CGPath {
        let path = CGMutablePath()
        path.addArc(
            center: batteryCenter,
            radius: batteryRadius,
            startAngle: volumeArcStartAngle,
            endAngle: volumeArcEndAngle,
            clockwise: true
        )
        return path
    }

    static func volumeArcFill(progress: Double) -> CGPath {
        let clamped = min(1, max(0, progress))
        guard clamped > 0 else { return CGMutablePath() }
        let sweep = volumeArcStartAngle - volumeArcEndAngle
        let end = volumeArcStartAngle - sweep * CGFloat(clamped)
        let path = CGMutablePath()
        path.addArc(
            center: batteryCenter,
            radius: batteryRadius,
            startAngle: volumeArcStartAngle,
            endAngle: end,
            clockwise: true
        )
        return path
    }

    // MARK: Helpers

    private static func batteryArc(
        progress: Double,
        hasTopGap: Bool,
        topGapWidth: CGFloat
    ) -> CGPath {
        guard hasTopGap else {
            let end = batteryStart + batterySweep * CGFloat(progress)
            return arc(center: batteryCenter, radius: batteryRadius, start: batteryStart, end: end)
        }

        let gapFraction = min(
            1,
            max(0, Double(topGapWidth / (batteryRadius * batterySweep)))
        )
        let gapStartProgress = 0.5 - gapFraction / 2
        let gapEndProgress = 0.5 + gapFraction / 2
        let path = CGMutablePath()
        let firstSegmentEnd = min(progress, gapStartProgress)
        if firstSegmentEnd > 0 {
            path.addPath(arc(
                center: batteryCenter,
                radius: batteryRadius,
                start: batteryStart,
                end: batteryStart + batterySweep * CGFloat(firstSegmentEnd)
            ))
        }

        guard progress > gapEndProgress else { return path }
        path.addPath(arc(
            center: batteryCenter,
            radius: batteryRadius,
            start: batteryStart + batterySweep * CGFloat(gapEndProgress),
            end: batteryStart + batterySweep * CGFloat(progress)
        ))
        return path
    }

    private static func arc(
        center: CGPoint,
        radius: CGFloat,
        start: CGFloat,
        end: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        return path
    }
}
