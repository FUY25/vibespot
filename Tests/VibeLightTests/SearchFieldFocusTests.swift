import AppKit
import Foundation
import Testing
@testable import VibeLight

@MainActor
@Test
func searchFieldRetainsInsertionPointAfterResultsRefreshSelectionChange() async throws {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("search_focus_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "fix auth bug",
        project: "/Users/me/terminalrail",
        projectName: "terminalrail",
        gitBranch: "feat/auth",
        status: "live",
        startedAt: Date(),
        pid: 123
    )

    let controller = SearchPanelController()
    controller.sessionIndex = index
    controller.show()
    defer { controller.hide() }

    let searchField = try #require(
        Mirror(reflecting: controller).children.first(where: { $0.label == "searchField" })?.value as? SearchField
    )

    searchField.stringValue = "auth bug"
    let panel = try #require(searchField.window)
    panel.makeFirstResponder(searchField)

    let editorBeforeRefresh = try #require(searchField.currentEditor())
    let length = searchField.stringValue.utf16.count
    editorBeforeRefresh.selectedRange = NSRange(location: length, length: 0)

    // Force focus away so restoreSearchFieldFocus() must run the refocus branch.
    panel.makeFirstResponder(panel.contentView)
    controller.tableViewSelectionDidChange(
        Notification(name: NSTableView.selectionDidChangeNotification, object: nil)
    )
    let editorDeadline = Date().addingTimeInterval(0.5)
    while searchField.currentEditor() == nil, Date() < editorDeadline {
        await Task.yield()
    }

    let editorAfterRefresh = try #require(searchField.currentEditor())
    #expect(editorAfterRefresh.selectedRange == NSRange(location: length, length: 0))
}

@MainActor
@Test
func tabAcceptsGhostSuggestionBeforeClosedHistoryDrillIn() async throws {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("search_tab_precedence_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    try index.upsertSession(
        id: "closed-1",
        tool: "claude",
        title: "Build notes",
        project: "/Users/me/archiver",
        projectName: "archiver",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(),
        pid: nil
    )

    let controller = SearchPanelController()
    controller.sessionIndex = index
    controller.show()
    defer { controller.hide() }

    let searchField = try #require(
        Mirror(reflecting: controller).children.first(where: { $0.label == "searchField" })?.value as? SearchField
    )

    searchField.stringValue = "ar"
    searchField.ghostSuggestion = "archiver"

    #expect(searchField.ghostSuggestion == "archiver")

    let editor = try #require(searchField.currentEditor() as? NSTextView)
    let handled = controller.control(
        searchField,
        textView: editor,
        doCommandBy: #selector(NSResponder.insertTab(_:))
    )

    #expect(handled)
    #expect(searchField.stringValue == "archiver")
}
