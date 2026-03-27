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
        Mirror(reflecting: controller).children.first(where: { $0.label == "searchField" })?.value as? NSSearchField
    )

    searchField.stringValue = "auth bug"
    let panel = try #require(searchField.window)
    panel.makeFirstResponder(searchField)

    let editorBeforeRefresh = try #require(searchField.currentEditor())
    let length = searchField.stringValue.utf16.count
    editorBeforeRefresh.selectedRange = NSRange(location: length, length: 0)

    controller.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: searchField)
    )
    try await Task.sleep(for: .milliseconds(250))

    let editorAfterRefresh = try #require(searchField.currentEditor())
    #expect(editorAfterRefresh.selectedRange == NSRange(location: length, length: 0))
}
