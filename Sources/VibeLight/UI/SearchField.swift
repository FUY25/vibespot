import AppKit

final class SearchField: NSTextField {
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

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        isBordered = false
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 28, weight: .medium)
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
                    .font: NSFont.systemFont(ofSize: 28, weight: .medium),
                    .foregroundColor: NSColor.tertiaryLabelColor,
                ]
            )
        }
    }
}
