import AppKit

enum VibeSpotBranding {
    static let productName = "VibeSpot"
    static let legacyProductName = "Flare"

    static func quitMenuTitle() -> String {
        "Quit \(productName)"
    }

    static func liveSessionsToolTip(count: Int) -> String {
        "\(productName) • \(count) live session\(count == 1 ? "" : "s")"
    }

    static func makeMenuBarImage(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocusFlipped(false)

        let minSide = min(size.width, size.height)
        let stroke = max(1.25, minSide * 0.105)
        let centerY = size.height * 0.5

        let chevronLeft = NSPoint(x: size.width * 0.10, y: centerY + minSide * 0.20)
        let chevronMid = NSPoint(x: size.width * 0.37, y: centerY)
        let chevronBottom = NSPoint(x: size.width * 0.10, y: centerY - minSide * 0.20)

        let ringDiameter = minSide * 0.30
        let ringRect = NSRect(
            x: size.width * 0.51,
            y: centerY - ringDiameter / 2.0,
            width: ringDiameter,
            height: ringDiameter
        )

        let dotDiameter = max(1.9, minSide * 0.10)
        let dotRect = NSRect(
            x: size.width * 0.88 - dotDiameter / 2.0,
            y: centerY - dotDiameter / 2.0,
            width: dotDiameter,
            height: dotDiameter
        )

        NSColor.white.setStroke()
        NSColor.white.setFill()

        let chevron = NSBezierPath()
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.lineWidth = stroke
        chevron.move(to: chevronLeft)
        chevron.line(to: chevronMid)
        chevron.line(to: chevronBottom)
        chevron.stroke()

        let ring = NSBezierPath(ovalIn: ringRect)
        ring.lineWidth = stroke
        ring.stroke()

        let dot = NSBezierPath(ovalIn: dotRect)
        dot.fill()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    static func makeApplicationIcon(size: NSSize = NSSize(width: 512, height: 512)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocusFlipped(false)

        let rect = NSRect(origin: .zero, size: size)
        let minSide = min(size.width, size.height)
        let backgroundRect = rect.insetBy(dx: minSide * 0.04, dy: minSide * 0.04)
        let backgroundRadius = minSide * 0.23

        let bgPath = NSBezierPath(roundedRect: backgroundRect, xRadius: backgroundRadius, yRadius: backgroundRadius)
        NSColor(calibratedRed: 10 / 255, green: 11 / 255, blue: 16 / 255, alpha: 1).setFill()
        bgPath.fill()

        let glowColorA = NSColor(calibratedRed: 87 / 255, green: 170 / 255, blue: 150 / 255, alpha: 0.18)
        let glowColorB = NSColor(calibratedRed: 93 / 255, green: 131 / 255, blue: 181 / 255, alpha: 0.12)
        drawGlow(ovalIn: NSRect(x: size.width * 0.19, y: size.height * 0.58, width: minSide * 0.29, height: minSide * 0.29), color: glowColorA)
        drawGlow(ovalIn: NSRect(x: size.width * 0.58, y: size.height * 0.26, width: minSide * 0.22, height: minSide * 0.22), color: glowColorB)

        let stroke = minSide * 0.03125
        let lineColor = NSColor(calibratedRed: 226 / 255, green: 232 / 255, blue: 240 / 255, alpha: 1)
        lineColor.setStroke()
        lineColor.setFill()

        // A2 containment: use the original submitted geometry without moving internals,
        // but scale the whole mark to a slightly more balanced icon footprint.
        let symbolFrame = NSRect(
            x: size.width * 0.165,
            y: size.height * 0.165,
            width: size.width * 0.67,
            height: size.height * 0.67
        )

        func sx(_ value: CGFloat) -> CGFloat { symbolFrame.minX + symbolFrame.width * (value / 512.0) }
        func sy(_ value: CGFloat) -> CGFloat { symbolFrame.minY + symbolFrame.height * (1.0 - value / 512.0) }
        func ss(_ value: CGFloat) -> CGFloat { symbolFrame.width * (value / 512.0) }

        let chevron = NSBezierPath()
        chevron.lineCapStyle = .round
        chevron.lineJoinStyle = .round
        chevron.lineWidth = stroke
        chevron.move(to: NSPoint(x: sx(85), y: sy(151)))
        chevron.line(to: NSPoint(x: sx(199), y: sy(265)))
        chevron.line(to: NSPoint(x: sx(85), y: sy(379)))
        chevron.stroke()

        let ringRect = NSRect(
            x: sx(256),
            y: sy(310.2),
            width: ss(91.2),
            height: ss(91.2)
        )
        let ring = NSBezierPath(ovalIn: ringRect)
        ring.lineWidth = stroke
        ring.stroke()

        let dotRect = NSRect(
            x: sx(404),
            y: sy(276.8),
            width: ss(22.8),
            height: ss(22.8)
        )
        let dot = NSBezierPath(ovalIn: dotRect)
        dot.fill()

        image.unlockFocus()
        return image
    }

    private static func drawGlow(ovalIn rect: NSRect, color: NSColor) {
        guard let gradient = NSGradient(colorsAndLocations: (color, 0.0), (color.withAlphaComponent(0.0), 1.0)) else {
            return
        }
        let path = NSBezierPath(ovalIn: rect)
        gradient.draw(in: path, relativeCenterPosition: .zero)
    }
}
