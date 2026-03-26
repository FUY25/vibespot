import AppKit

final class SearchField: NSSearchField {
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
        size.height = max(size.height, 34)
        return size
    }

    private func configure() {
        translatesAutoresizingMaskIntoConstraints = false
        placeholderString = "Search sessions"
        focusRingType = .none
        font = .systemFont(ofSize: 18, weight: .medium)
        maximumRecents = 0
        recentsAutosaveName = nil

        if let searchCell = cell as? NSSearchFieldCell {
            searchCell.sendsWholeSearchString = false
            searchCell.sendsSearchStringImmediately = true
            searchCell.placeholderString = "Search sessions"
        }
    }
}
