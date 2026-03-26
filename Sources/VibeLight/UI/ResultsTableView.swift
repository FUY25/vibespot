import AppKit

final class ResultsTableView: NSTableView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var acceptsFirstResponder: Bool {
        false
    }

    private func configure() {
        headerView = nil
        focusRingType = .none
        backgroundColor = .clear
        usesAlternatingRowBackgroundColors = false
        selectionHighlightStyle = .regular
        intercellSpacing = NSSize(width: 0, height: 6)
        rowSizeStyle = .custom
        gridStyleMask = []
        allowsTypeSelect = false
        allowsEmptySelection = true
        allowsMultipleSelection = false
        columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        column.isEditable = false
        column.resizingMask = .autoresizingMask
        addTableColumn(column)
        autoresizingMask = [.width]
    }
}

final class ResultsTableRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else {
            return
        }

        let selectionRect = bounds.insetBy(dx: 4, dy: 1)
        let path = NSBezierPath(roundedRect: selectionRect, xRadius: 12, yRadius: 12)
        let color = NSColor.controlAccentColor.withAlphaComponent(isEmphasized ? 0.24 : 0.14)
        color.setFill()
        path.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {}
}
