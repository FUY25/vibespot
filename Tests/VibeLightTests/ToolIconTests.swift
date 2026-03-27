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
        guard ToolIcon.resourceURL(for: tool) != nil else {
            Issue.record("Missing bundled PNG resource for \(tool).")
            continue
        }

        let actualImage = ToolIcon.image(for: tool, size: 22)
        #expect(actualImage.size.width == 22)
        #expect(actualImage.size.height == 22)
    }
}

@MainActor
@Test
func knownToolsFallBackWhenPNGResourceIsMissing() {
    let emptyBundle = Bundle(for: MissingResourceBundleToken.self)

    #expect(ToolIcon.resourceURL(for: "claude", in: emptyBundle) == nil)
    #expect(
        renderedPNGData(for: ToolIcon.image(for: "claude", size: 22, in: emptyBundle), size: 22)
            == renderedPNGData(for: ToolIcon.image(for: "custom", size: 22), size: 22)
    )
}

@MainActor
@Test
func unknownToolsStillRenderFallbackIcons() {
    let unknownImage = ToolIcon.image(for: "unknown", size: 22)
    let umbrellaImage = ToolIcon.image(for: "umbrella", size: 22)
    let codexImage = ToolIcon.image(for: "codex", size: 22)

    #expect(renderedPNGData(for: unknownImage, size: 22) == renderedPNGData(for: umbrellaImage, size: 22))
    #expect(renderedPNGData(for: unknownImage, size: 22) != renderedPNGData(for: codexImage, size: 22))
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
