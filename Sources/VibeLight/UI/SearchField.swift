import AppKit

final class SearchField: NSTextField {
    var ghostSuggestion: String? {
        didSet {
            needsDisplay = true
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = max(size.height, 40)
        return size
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard
            let ghostSuggestion,
            !ghostSuggestion.isEmpty
        else {
            return
        }

        let typedText = stringValue
        guard
            !typedText.isEmpty,
            ghostSuggestion.lowercased().hasPrefix(typedText.lowercased()),
            typedText.count < ghostSuggestion.count
        else {
            return
        }

        let suffix = String(ghostSuggestion.dropFirst(typedText.count))
        let textFont = font ?? DesignTokens.Font.searchInput
        let typedAttributes: [NSAttributedString.Key: Any] = [.font: textFont]
        let typedWidth = (typedText as NSString).size(withAttributes: typedAttributes).width
        let ghostAttributes: [NSAttributedString.Key: Any] = [
            .font: textFont,
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]
        let ghostString = NSAttributedString(string: suffix, attributes: ghostAttributes)
        let ghostSize = ghostString.size()
        let origin = NSPoint(
            x: typedWidth + 1,
            y: (bounds.height - ghostSize.height) / 2 - 1
        )
        ghostString.draw(at: origin)
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = DesignTokens.Font.searchInput
        textColor = .labelColor
        placeholderString = "Search sessions"
        lineBreakMode = .byTruncatingTail

        if let textCell = cell as? NSTextFieldCell {
            textCell.wraps = false
            textCell.isScrollable = true
            textCell.usesSingleLineMode = true
            textCell.lineBreakMode = .byTruncatingTail
            textCell.placeholderAttributedString = NSAttributedString(
                string: "Search sessions",
                attributes: [
                    .font: DesignTokens.Font.searchInput,
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
            )
        }
    }
}
