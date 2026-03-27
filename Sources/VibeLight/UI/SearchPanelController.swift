// Research notes for Task 5 (2026-03-27):
// - Apple Support's current Spotlight article ("Search for anything with Spotlight on Mac")
//   shows the Sequoia Spotlight window in an official screenshot asset
//   (`SharedArt/S2861_SpotlightSearch.png`, served at 1144x745 on 2026-03-27). The article
//   also explicitly says Spotlight can be dragged anywhere on the desktop and resized, so the
//   window is no longer a tiny fixed center popup.
// - The Apple screenshot and the Sequoia screenshot-library references both show Spotlight as a
//   wide, softly rounded translucent panel parked in the upper portion of the screen rather than
//   dead center. The top chrome is visually integrated: large plain text input, magnifying glass
//   on the left, subtle separator below, and a light material instead of the older dark HUD look.
// - Exact measurements are not published, so the values below are approximations inferred from the
//   current screenshots: width roughly ~700-740 px, corner radius ~28 px, search text around the
//   high-20 pt range, compact result rows with gentle inset selection, and a very soft border/shadow.
import AppKit

@MainActor
final class SearchPanelController: NSObject, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: ((SearchResult) -> Void)?
    var sessionIndex: SessionIndex?
    var isVisible: Bool { panel.isVisible }
    var hidesOnDeactivate: Bool { panel.hidesOnDeactivate }

    private let panel: SearchPanel
    private let visualEffectView = NSVisualEffectView(frame: .zero)
    private let searchIconView = NSImageView(frame: .zero)
    private let searchField = SearchField(frame: .zero)
    private let actionHintLabel = NSTextField(labelWithString: "")
    private let searchBarProductIcon = NSImageView(frame: .zero)
    private let separatorBox = NSBox(frame: .zero)
    private let resultsScrollView = NSScrollView(frame: .zero)
    private let resultsTableView = ResultsTableView(frame: .zero)
    private let resultsHeightConstraint: NSLayoutConstraint
    private let searchDebouncer = Debouncer(delay: 0.08)

    private var results: [SearchResult] = []
    private var deactivationObserver: NSObjectProtocol?
    private var panelResignKeyObserver: NSObjectProtocol?

    private let panelWidth: CGFloat = DesignTokens.Spacing.panelWidth
    private let minPanelHeight: CGFloat = 104
    private let maxVisibleRows = DesignTokens.Spacing.maxVisibleRows
    private let searchFieldHeight: CGFloat = DesignTokens.Spacing.searchFieldHeight
    private let topInset: CGFloat = DesignTokens.Spacing.searchBarTopPadding
    private let bottomInset: CGFloat = DesignTokens.Spacing.resultsBottomPadding
    private let resultsTopSpacing: CGFloat = 10
    private let separatorTopSpacing: CGFloat = 14
    private let separatorHeight: CGFloat = 1
    private static let isRunningTests: Bool = {
        if NSClassFromString("XCTestCase") != nil {
            return true
        }

        let processName = ProcessInfo.processInfo.processName.lowercased()
        if processName.contains("xctest") {
            return true
        }

        return ProcessInfo.processInfo.environment.keys.contains { key in
            key.localizedCaseInsensitiveContains("xctest")
                || key.localizedCaseInsensitiveContains("swift_testing")
        }
    }()

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
        applyResults([])
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        searchDebouncer.cancel()
        searchField.stringValue = ""
        searchField.ghostSuggestion = nil
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
        searchField.ghostSuggestion = nil
        panel.orderOut(nil)
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        results.count
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard results.indices.contains(row) else {
            return ResultRowView.rowHeightWithoutActivity
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
        if searchField.stringValue.isEmpty {
            searchField.ghostSuggestion = nil
        }
        searchDebouncer.schedule { [weak self] in
            Task { @MainActor [weak self] in
                self?.refreshResults()
            }
        }
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        restoreSearchFieldFocus()
        updateActionHint()
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
            return acceptGhostSuggestionIfNeeded() || drillIntoSelectedHistory()
        case #selector(NSResponder.moveRight(_:)):
            return acceptGhostSuggestionIfNeeded()
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
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow
    }

    private func configureViews() {
        visualEffectView.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.material = .popover
        visualEffectView.state = .active
        visualEffectView.blendingMode = .withinWindow
        visualEffectView.wantsLayer = true
        visualEffectView.layer?.cornerRadius = DesignTokens.Radius.panel
        visualEffectView.layer?.masksToBounds = true
        visualEffectView.layer?.borderWidth = 1
        visualEffectView.layer?.borderColor = DesignTokens.Color.ghostBorder.cgColor

        searchIconView.translatesAutoresizingMaskIntoConstraints = false
        searchIconView.image = NSImage(
            systemSymbolName: "magnifyingglass",
            accessibilityDescription: "Search"
        )
        searchIconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
        searchIconView.contentTintColor = .secondaryLabelColor
        searchIconView.imageScaling = .scaleProportionallyUpOrDown

        actionHintLabel.translatesAutoresizingMaskIntoConstraints = false
        actionHintLabel.font = DesignTokens.Font.actionHint
        actionHintLabel.textColor = .tertiaryLabelColor
        actionHintLabel.alignment = .right
        actionHintLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        actionHintLabel.setContentHuggingPriority(.required, for: .horizontal)

        searchBarProductIcon.translatesAutoresizingMaskIntoConstraints = false
        searchBarProductIcon.imageScaling = .scaleProportionallyUpOrDown

        separatorBox.translatesAutoresizingMaskIntoConstraints = false
        separatorBox.boxType = .separator

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
        visualEffectView.addSubview(searchIconView)
        visualEffectView.addSubview(searchField)
        visualEffectView.addSubview(actionHintLabel)
        visualEffectView.addSubview(searchBarProductIcon)
        visualEffectView.addSubview(separatorBox)
        visualEffectView.addSubview(resultsScrollView)

        NSLayoutConstraint.activate([
            searchIconView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: DesignTokens.Spacing.searchBarHorizontalPadding),
            searchIconView.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            searchIconView.widthAnchor.constraint(equalToConstant: 18),
            searchIconView.heightAnchor.constraint(equalToConstant: 18),

            searchField.leadingAnchor.constraint(equalTo: searchIconView.trailingAnchor, constant: 12),
            searchField.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: topInset),
            searchField.trailingAnchor.constraint(equalTo: actionHintLabel.leadingAnchor, constant: -12),
            searchField.heightAnchor.constraint(equalToConstant: searchFieldHeight),

            actionHintLabel.trailingAnchor.constraint(equalTo: searchBarProductIcon.leadingAnchor, constant: -8),
            actionHintLabel.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),

            searchBarProductIcon.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -DesignTokens.Spacing.searchBarHorizontalPadding),
            searchBarProductIcon.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            searchBarProductIcon.widthAnchor.constraint(equalToConstant: DesignTokens.Spacing.toolIconSize),
            searchBarProductIcon.heightAnchor.constraint(equalToConstant: DesignTokens.Spacing.toolIconSize),

            separatorBox.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: 20),
            separatorBox.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -20),
            separatorBox.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: separatorTopSpacing),
            separatorBox.heightAnchor.constraint(equalToConstant: separatorHeight),

            resultsScrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor, constant: DesignTokens.Spacing.resultsHorizontalPadding),
            resultsScrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor, constant: -DesignTokens.Spacing.resultsHorizontalPadding),
            resultsScrollView.topAnchor.constraint(equalTo: separatorBox.bottomAnchor, constant: resultsTopSpacing),
            resultsScrollView.bottomAnchor.constraint(lessThanOrEqualTo: visualEffectView.bottomAnchor, constant: -bottomInset),
            resultsHeightConstraint,
        ])
    }

    private func configureInteractions() {
        searchField.delegate = self
        guard !Self.isRunningTests else { return }
        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hide()
            }
        }
        panelResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard NSApp.isActive else { return }

                // Avoid hiding during transient key-window churn while showing/focusing controls.
                try? await Task.sleep(for: .milliseconds(50))
                guard panel.isVisible, !panel.isKeyWindow, NSApp.isActive else { return }
                guard let keyWindow = NSApp.keyWindow, keyWindow !== panel else { return }
                hide()
            }
        }
    }

    @MainActor
    deinit {
        if let observer = deactivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = panelResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func refreshResults() {
        guard let sessionIndex else {
            applyResults([])
            return
        }

        do {
            let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = try sessionIndex.search(query: query, liveOnly: query.isEmpty)
            if query.lowercased().hasPrefix("new") {
                applyResults(makeNewSessionActionRows() + matches)
            } else {
                applyResults(matches)
            }
        } catch {
            applyResults([])
            print("SearchPanelController search failed: \(error)")
        }
    }

    private func makeNewSessionActionRows() -> [SearchResult] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let recentProject = (try? sessionIndex?.mostRecentProject()) ?? nil
        let project = recentProject?.project.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectName = recentProject?.projectName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedProject = project.isEmpty ? homePath : project
        let resolvedProjectName = projectName.isEmpty ? "~" : projectName
        let now = Date()

        return [
            SearchResult(
                sessionId: "new-claude",
                tool: "claude",
                title: "New Claude session",
                project: resolvedProject,
                projectName: resolvedProjectName,
                gitBranch: "",
                status: "action",
                startedAt: now,
                pid: nil,
                tokenCount: 0,
                lastActivityAt: now,
                activityPreview: nil,
                activityStatus: .closed,
                snippet: nil
            ),
            SearchResult(
                sessionId: "new-codex",
                tool: "codex",
                title: "New Codex session",
                project: resolvedProject,
                projectName: resolvedProjectName,
                gitBranch: "",
                status: "action",
                startedAt: now,
                pid: nil,
                tokenCount: 0,
                lastActivityAt: now,
                activityPreview: nil,
                activityStatus: .closed,
                snippet: nil
            ),
        ]
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

        updateGhostSuggestion()
        updateActionHint()
        updatePanelSize()
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
        updateActionHint()
    }

    private func updateActionHint() {
        guard !results.isEmpty else {
            actionHintLabel.stringValue = ""
            searchBarProductIcon.image = nil
            return
        }

        let row = resultsTableView.selectedRow >= 0 ? resultsTableView.selectedRow : 0
        guard results.indices.contains(row) else {
            actionHintLabel.stringValue = ""
            searchBarProductIcon.image = nil
            return
        }

        let result = results[row]
        searchBarProductIcon.image = ToolIcon.image(for: result.tool, size: DesignTokens.Spacing.toolIconSize)

        if result.status == "action" {
            actionHintLabel.stringValue = "↩ Launch"
        } else if result.status == "live" {
            actionHintLabel.stringValue = "↩ Switch"
        } else {
            actionHintLabel.stringValue = "↩ Resume ⇥ History"
        }
    }

    private func drillIntoSelectedHistory() -> Bool {
        guard !results.isEmpty else {
            return false
        }

        let row = resultsTableView.selectedRow >= 0 ? resultsTableView.selectedRow : 0
        guard results.indices.contains(row) else {
            return false
        }

        let result = results[row]
        guard result.status != "live", result.status != "action", !result.title.isEmpty else {
            return false
        }

        searchField.stringValue = result.title
        refreshResults()

        if let editor = searchField.currentEditor() {
            editor.selectedRange = NSRange(location: result.title.utf16.count, length: 0)
        }

        return true
    }

    private func updateGhostSuggestion() {
        guard !results.isEmpty else {
            searchField.ghostSuggestion = nil
            return
        }

        let query = searchField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            searchField.ghostSuggestion = nil
            return
        }

        let titleSuggestion = results.first(where: {
            $0.title.lowercased().hasPrefix(query.lowercased())
        })?.title

        let projectSuggestion = titleSuggestion ?? results.first(where: {
            let name = $0.projectName.isEmpty
                ? URL(fileURLWithPath: $0.project).lastPathComponent
                : $0.projectName
            return name.lowercased().hasPrefix(query.lowercased())
        }).map {
            $0.projectName.isEmpty
                ? URL(fileURLWithPath: $0.project).lastPathComponent
                : $0.projectName
        }

        searchField.ghostSuggestion = titleSuggestion ?? projectSuggestion
    }

    private func acceptGhostSuggestionIfNeeded() -> Bool {
        guard
            let ghostSuggestion = searchField.ghostSuggestion,
            !ghostSuggestion.isEmpty,
            ghostSuggestion != searchField.stringValue
        else {
            return false
        }

        searchField.stringValue = ghostSuggestion
        searchField.ghostSuggestion = nil

        if let editor = searchField.currentEditor() {
            editor.selectedRange = NSRange(location: ghostSuggestion.utf16.count, length: 0)
        }

        refreshResults()
        return true
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
            topInset + searchFieldHeight + separatorTopSpacing + separatorHeight +
                resultsTopSpacing + scrollHeight + bottomInset
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
        let topOffset = max(visibleFrame.height * 0.18, 96)
        let origin = NSPoint(
            x: visibleFrame.midX - panelWidth / 2,
            y: max(visibleFrame.minY + 24, visibleFrame.maxY - panel.frame.height - topOffset)
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
