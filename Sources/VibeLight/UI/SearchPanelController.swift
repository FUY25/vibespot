import AppKit

@MainActor
final class SearchPanelController: NSObject, NSSearchFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((SearchResult) -> Void)?
    var sessionIndex: SessionIndex?
    var isVisible: Bool { panel.isVisible }
    var hidesOnDeactivate: Bool { panel.hidesOnDeactivate }

    private let panel: SearchPanel
    private let visualEffectView = NSVisualEffectView(frame: .zero)
    private let searchField = SearchField(frame: .zero)
    private let modeLabel = NSTextField(labelWithString: "")
    private let resultsScrollView = NSScrollView(frame: .zero)
    private let resultsTableView = ResultsTableView(frame: .zero)
    private let resultsHeightConstraint: NSLayoutConstraint
    private let searchDebouncer = Debouncer(delay: 0.08)

    private var includeHistory = false
    private var results: [SearchResult] = []

    private let panelWidth: CGFloat = 600
    private let minPanelHeight: CGFloat = 80
    private let maxVisibleRows = 8
    private let searchFieldHeight: CGFloat = 34
    private let topInset: CGFloat = 16
    private let bottomInset: CGFloat = 14
    private let resultsTopSpacing: CGFloat = 10

    override init() {
        self.panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: minPanelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        self.resultsHeightConstraint = resultsScrollView.heightAnchor.constraint(equalToConstant: 0)

        super.init()

        configurePanel()
        configureViews()
        configureInteractions()
        refreshModeLabel()
        applyResults([])
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        searchDebouncer.cancel()
        includeHistory = false
        refreshModeLabel()
        searchField.stringValue = ""
        refreshResults()

        if !panel.isVisible {
            centerPanelOnActiveScreen()
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func hide() {
        searchDebouncer.cancel()
        panel.orderOut(nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard results.indices.contains(row) else {
            return ResultRowView.rowHeightWithoutSnippet
        }

        return ResultRowView.height(for: results[row])
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        ResultsTableRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else {
            return nil
        }

        let identifier = NSUserInterfaceItemIdentifier("ResultRowView")
        let view = tableView.makeView(withIdentifier: identifier, owner: self) as? ResultRowView ?? ResultRowView(frame: .zero)
        view.identifier = identifier
        view.configure(with: results[row])
        return view
    }

    func controlTextDidChange(_ notification: Notification) {
        searchDebouncer.schedule { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshResults()
            }
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        restoreSearchFieldFocus()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            hide()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            activateSelectedResult()
            return true
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveToBeginningOfParagraph(_:)):
            moveSelection(delta: -1)
            return true
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveToEndOfParagraph(_:)):
            moveSelection(delta: 1)
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            toggleMode()
            return true
        default:
            return false
        }
    }

    @objc
    private func handleTableDoubleAction() {
        activateSelectedResult()
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = true
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow
    }

    private func configureViews() {
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .hudWindow
        visualEffectView.state = .active
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = 20
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        modeLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        modeLabel.textColor = .secondaryLabelColor
        modeLabel.alignment = .right
        modeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        resultsScrollView.translatesAutoresizingMaskIntoConstraints = false
        resultsScrollView.drawsBackground = false
        resultsScrollView.backgroundColor = .clear
        resultsScrollView.borderType = .noBorder
        resultsScrollView.hasVerticalScroller = false
        resultsScrollView.autohidesScrollers = true
        resultsScrollView.documentView = resultsTableView

        resultsTableView.delegate = self
        resultsTableView.dataSource = self
        resultsTableView.doubleAction = #selector(handleTableDoubleAction)
        resultsTableView.target = self

        panel.contentView = visualEffectView
        visualEffectView.addSubview(searchField)
        visualEffectView.addSubview(modeLabel)
        visualEffectView.addSubview(resultsScrollView)

        NSLayoutConstraint.activate([
            searchField.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 16),
            searchField.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: topInset),
            searchField.trailingAnchor.constraint(equalTo: modeLabel.leadingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: searchFieldHeight),

            modeLabel.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -16),
            modeLabel.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),

            resultsScrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 10),
            resultsScrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -10),
            resultsScrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: resultsTopSpacing),
            resultsScrollView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor, constant: -bottomInset),
            resultsHeightConstraint,
        ])
    }

    private func configureInteractions() {
        searchField.delegate = self
    }

    private func refreshResults() {
        guard let sessionIndex else {
            applyResults([])
            return
        }

        do {
            let matches = try sessionIndex.search(
                query: searchField.stringValue,
                includeHistory: includeHistory
            )
            applyResults(matches)
        } catch {
            applyResults([])
            print("SearchPanelController search failed: \(error)")
        }
    }

    private func applyResults(_ newResults: [SearchResult]) {
        results = newResults
        resultsTableView.reloadData()

        if results.isEmpty {
            resultsTableView.deselectAll(nil)
        } else {
            resultsTableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            resultsTableView.scrollRowToVisible(0)
        }

        updatePanelSize()
    }

    private func refreshModeLabel() {
        modeLabel.stringValue = includeHistory ? "○ History" : "● Live"
    }

    private func toggleMode() {
        includeHistory.toggle()
        refreshModeLabel()
        refreshResults()
    }

    private func moveSelection(delta: Int) {
        guard !results.isEmpty else {
            return
        }

        let selectedRow = resultsTableView.selectedRow
        let fallbackRow = delta >= 0 ? 0 : results.count - 1
        let currentRow = selectedRow >= 0 ? selectedRow : fallbackRow
        let nextRow = max(0, min(results.count - 1, currentRow + delta))

        resultsTableView.selectRowIndexes(IndexSet(integer: nextRow), byExtendingSelection: false)
        resultsTableView.scrollRowToVisible(nextRow)
    }

    private func activateSelectedResult() {
        guard !results.isEmpty else {
            return
        }

        let row = resultsTableView.selectedRow >= 0 ? resultsTableView.selectedRow : 0
        guard results.indices.contains(row) else {
            return
        }

        let result = results[row]
        hide()
        onSelect?(result)
    }

    private func updatePanelSize() {
        let visibleResults = min(results.count, maxVisibleRows)
        let visibleHeights = results.prefix(visibleResults).enumerated().reduce(CGFloat(0)) { partial, entry in
            let rowHeight = ResultRowView.height(for: entry.element)
            let spacing = entry.offset == 0 ? CGFloat(0) : resultsTableView.intercellSpacing.height
            return partial + rowHeight + spacing
        }

        let totalHeights = results.enumerated().reduce(CGFloat(0)) { partial, entry in
            let rowHeight = ResultRowView.height(for: entry.element)
            let spacing = entry.offset == 0 ? CGFloat(0) : resultsTableView.intercellSpacing.height
            return partial + rowHeight + spacing
        }

        let scrollHeight = results.isEmpty ? CGFloat(0) : visibleHeights
        resultsHeightConstraint.constant = scrollHeight
        resultsScrollView.hasVerticalScroller = totalHeights > visibleHeights
        resultsScrollView.verticalScroller?.alphaValue = totalHeights > visibleHeights ? 1 : 0

        let targetHeight = max(
            minPanelHeight,
            topInset + searchFieldHeight + (results.isEmpty ? 0 : resultsTopSpacing + scrollHeight) + bottomInset
        )

        var frame = panel.frame
        let maxY = frame.maxY
        frame.size = NSSize(width: panelWidth, height: targetHeight)
        frame.origin.y = maxY - targetHeight
        panel.setFrame(frame, display: true, animate: panel.isVisible)
        synchronizeResultsDocumentFrame(totalHeight: totalHeights, visibleHeight: scrollHeight)
    }

    private func centerPanelOnActiveScreen() {
        guard let screen = activeScreen() else {
            panel.center()
            return
        }

        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - panelWidth / 2,
            y: visibleFrame.midY - panel.frame.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
    }

    private func restoreSearchFieldFocus() {
        guard panel.isVisible else { return }

        // Only restore focus if the search field lost it.
        // Do NOT call makeFirstResponder unconditionally; that selects all text.
        if panel.firstResponder != searchField.currentEditor(),
           panel.firstResponder != searchField {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.panel.makeFirstResponder(self.searchField)
                // Restore cursor to end instead of selecting all text.
                if let editor = self.searchField.currentEditor() {
                    let length = self.searchField.stringValue.utf16.count
                    editor.selectedRange = NSRange(location: length, length: 0)
                }
            }
        }
    }

    private func synchronizeResultsDocumentFrame(totalHeight: CGFloat, visibleHeight: CGFloat) {
        visualEffectView.layoutSubtreeIfNeeded()

        let documentWidth = max(resultsScrollView.contentView.bounds.width, 0)
        guard let column = resultsTableView.tableColumns.first else {
            return
        }

        column.width = documentWidth
        resultsTableView.frame = NSRect(
            x: 0,
            y: 0,
            width: documentWidth,
            height: max(totalHeight, visibleHeight)
        )
    }
}

private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        false
    }
}
