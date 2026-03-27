import AppKit
import Testing
@testable import VibeLight

@MainActor
@Test
func knownToolIconsRenderFromBundledPNGResources() {
    for tool in [
        "claude",
        "codex",
        "gemini",
    ] {
        guard let resourceURL = ToolIcon.resourceURL(for: tool) else {
            Issue.record("Missing bundled PNG resource for \(tool).")
            continue
        }

        guard let expectedImage = NSImage(contentsOf: resourceURL) else {
            Issue.record("Unable to load bundled PNG resource for \(tool).")
            continue
        }

        let actualImage = ToolIcon.image(for: tool, size: 20)

        #expect(renderedPNGData(for: actualImage, size: 20) == renderedPNGData(for: expectedImage, size: 20))
    }
}

@MainActor
@Test
func knownToolsFallBackWhenPNGResourceIsMissing() {
    let emptyBundle = Bundle(for: MissingResourceBundleToken.self)

    #expect(ToolIcon.resourceURL(for: "claude", in: emptyBundle) == nil)
    #expect(
        renderedPNGData(for: ToolIcon.image(for: "claude", size: 20, in: emptyBundle), size: 20)
            == renderedPNGData(for: ToolIcon.image(for: "custom", size: 20), size: 20)
    )
}

@MainActor
@Test
func unknownToolsStillRenderFallbackIcons() {
    let unknownImage = ToolIcon.image(for: "unknown", size: 20)
    let umbrellaImage = ToolIcon.image(for: "umbrella", size: 20)
    let codexImage = ToolIcon.image(for: "codex", size: 20)

    #expect(renderedPNGData(for: unknownImage, size: 20) == renderedPNGData(for: umbrellaImage, size: 20))
    #expect(renderedPNGData(for: unknownImage, size: 20) != renderedPNGData(for: codexImage, size: 20))
}

@MainActor
private func renderedPNGData(for image: NSImage, size: CGFloat) -> Data? {
    let canvasSize = NSSize(width: size, height: size)

    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size),
        pixelsHigh: Int(size),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        return nil
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(origin: .zero, size: canvasSize)).fill()
    image.draw(in: NSRect(origin: .zero, size: canvasSize))
    NSGraphicsContext.restoreGraphicsState()

    return bitmap.representation(using: .png, properties: [:])
}

private final class MissingResourceBundleToken {}
