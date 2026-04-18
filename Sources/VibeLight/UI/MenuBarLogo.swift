import AppKit

enum MenuBarLogo {
    static func makeImage(size: NSSize = NSSize(width: 18, height: 18)) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocusFlipped(false)

        let scaleX = size.width / 18.0
        let scaleY = size.height / 18.0
        let lineWidth = max(1.65, min(scaleX, scaleY) * 1.75)
        let headRect = NSRect(x: 1.9 * scaleX, y: 3.4 * scaleY, width: 14.4 * scaleX, height: 10.7 * scaleY)
        let searchRect = NSRect(x: 3.4 * scaleX, y: 10.9 * scaleY, width: 11.5 * scaleX, height: 2.7 * scaleY)
        let graphStart = NSPoint(x: 4.3 * scaleX, y: 8.7 * scaleY)
        let graphPoints = [
            NSPoint(x: 6.6 * scaleX, y: 7.4 * scaleY),
            NSPoint(x: 8.3 * scaleX, y: 8.9 * scaleY),
            NSPoint(x: 10.8 * scaleX, y: 6.4 * scaleY),
            NSPoint(x: 13.9 * scaleX, y: 8.1 * scaleY),
        ]

        NSColor.white.set()

        let head = NSBezierPath(roundedRect: headRect, xRadius: 2.7 * scaleX, yRadius: 2.7 * scaleY)
        head.lineWidth = lineWidth
        head.stroke()

        let antenna = NSBezierPath()
        antenna.move(to: NSPoint(x: 9.1 * scaleX, y: 14.0 * scaleY))
        antenna.line(to: NSPoint(x: 9.1 * scaleX, y: 16.25 * scaleY))
        antenna.lineWidth = lineWidth
        antenna.stroke()

        let antennaDot = NSBezierPath(ovalIn: NSRect(x: 8.2 * scaleX, y: 15.45 * scaleY, width: 1.8 * scaleX, height: 1.8 * scaleY))
        antennaDot.fill()

        let eyeSize = NSSize(width: 1.45 * scaleX, height: 1.45 * scaleY)
        NSBezierPath(ovalIn: NSRect(x: 4.9 * scaleX, y: 6.0 * scaleY, width: eyeSize.width, height: eyeSize.height)).fill()
        NSBezierPath(ovalIn: NSRect(x: 11.9 * scaleX, y: 6.0 * scaleY, width: eyeSize.width, height: eyeSize.height)).fill()

        let search = NSBezierPath(roundedRect: searchRect, xRadius: 1.2 * scaleX, yRadius: 1.2 * scaleY)
        search.lineWidth = lineWidth
        search.stroke()

        let graph = NSBezierPath()
        graph.move(to: graphStart)
        for point in graphPoints {
            graph.line(to: point)
        }
        graph.lineWidth = lineWidth
        graph.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }
}
