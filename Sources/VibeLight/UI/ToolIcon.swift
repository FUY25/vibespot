import AppKit

enum ToolIcon {
    private static let fallbackResourceSubdirectory = "ToolIcons"

    static func image(for tool: String, size: CGFloat = 20) -> NSImage {
        image(for: tool, size: size, in: .module)
    }

    static func image(for tool: String, size: CGFloat = 20, in bundle: Bundle) -> NSImage {
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

        let resized = image.copy() as? NSImage ?? image
        resized.size = NSSize(width: size, height: size)
        resized.isTemplate = false
        return resized
    }

    private static func fallbackImage(for tool: String, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            NSColor.systemGray.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()

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
