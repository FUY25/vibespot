import AppKit

enum ToolIcon {
    static func image(for tool: String, size: CGFloat = 20) -> NSImage {
        let assetName: String

        switch tool.lowercased() {
        case "claude":
            assetName = "claude-icon"
        case "codex":
            assetName = "codex-icon"
        case "gemini":
            assetName = "gemini-icon"
        default:
            return fallbackImage(for: tool, size: size)
        }

        if let image = Bundle.module.image(forResource: NSImage.Name(assetName)) {
            let resized = image.copy() as? NSImage ?? image
            resized.size = NSSize(width: size, height: size)
            resized.isTemplate = false
            return resized
        }

        return fallbackImage(for: tool, size: size)
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
