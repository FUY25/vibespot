import AppKit

enum ToolIcon {
    private static let fallbackResourceSubdirectory = "ToolIcons"

    static func image(for tool: String, size: CGFloat = DesignTokens.Spacing.toolIconSize) -> NSImage {
        image(for: tool, size: size, in: .module)
    }

    static func image(for tool: String, size: CGFloat = DesignTokens.Spacing.toolIconSize, in bundle: Bundle) -> NSImage {
        guard let resourceURL = resourceURL(for: tool, in: bundle) else {
            return fallbackImage(for: tool, size: size)
        }

        guard let image = bundledPNG(at: resourceURL, size: size) else {
            return fallbackImage(for: tool, size: size)
        }

        return image
    }

    static func resourceURL(for tool: String, in bundle: Bundle = .module) -> URL? {
        guard let assetName = assetName(for: tool) else {
            return nil
        }

        if let resourceURL = bundle.url(
            forResource: assetName,
            withExtension: "png"
        ) {
            return resourceURL
        }

        return bundle.url(
            forResource: assetName,
            withExtension: "png",
            subdirectory: fallbackResourceSubdirectory
        )
    }

    private static func assetName(for tool: String) -> String? {
        switch tool.lowercased() {
        case "claude":
            return "claude-icon"
        case "codex":
            return "codex-icon"
        case "gemini":
            return "gemini-icon"
        default:
            return nil
        }
    }

    private static func bundledPNG(at resourceURL: URL, size: CGFloat) -> NSImage? {
        guard let image = NSImage(contentsOf: resourceURL) else {
            return nil
        }

        let canvas = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let path = NSBezierPath(roundedRect: rect, xRadius: DesignTokens.Radius.logo, yRadius: DesignTokens.Radius.logo)
            path.addClip()
            image.draw(in: rect)
            return true
        }
        canvas.isTemplate = false
        return canvas
    }

    private static func fallbackImage(for tool: String, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.systemGray.setFill()
            let insetRect = rect.insetBy(dx: 1, dy: 1)
            NSBezierPath(roundedRect: insetRect, xRadius: DesignTokens.Radius.icon, yRadius: DesignTokens.Radius.icon).fill()

            let letter = String(tool.prefix(1)).uppercased()
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: size * 0.48, weight: .bold),
                .foregroundColor: NSColor.white,
            ]
            let attributed = NSAttributedString(string: letter, attributes: attributes)
            let textSize = attributed.size()
            attributed.draw(at: NSPoint(
                x: rect.midX - textSize.width / 2,
                y: rect.midY - textSize.height / 2
            ))
            return true
        }

        image.isTemplate = false
        return image
    }
}
