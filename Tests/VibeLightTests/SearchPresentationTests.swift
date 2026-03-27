import AppKit
import Foundation
import Testing
@testable import VibeLight

@MainActor
@Test
func searchPanelUsesManualDeactivationHandling() {
    let controller = SearchPanelController()
    #expect(controller.hidesOnDeactivate == false)
}

@MainActor
@Test
func resultRowHeightReflectsActivityState() {
    let closedResult = SearchResult(
        sessionId: "closed",
        tool: "claude",
        title: "Closed session",
        project: "/tmp/project",
        projectName: "project",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(timeIntervalSince1970: 50_880),
        pid: nil,
        tokenCount: 0,
        lastActivityAt: Date(timeIntervalSince1970: 50_880),
        activityPreview: nil,
        activityStatus: .closed,
        snippet: nil
    )

    let liveResult = SearchResult(
        sessionId: "live",
        tool: "codex",
        title: "Working session",
        project: "/tmp/project",
        projectName: "project",
        gitBranch: "main",
        status: "live",
        startedAt: Date(timeIntervalSince1970: 50_880),
        pid: 42,
        tokenCount: 4200,
        lastActivityAt: Date(timeIntervalSince1970: 50_900),
        activityPreview: ActivityPreview(text: "▶ Running swift test", kind: .tool),
        activityStatus: .working,
        snippet: nil
    )

    #expect(ResultRowView.height(for: closedResult) == ResultRowView.rowHeightWithoutActivity)
    #expect(ResultRowView.height(for: liveResult) == ResultRowView.rowHeightWithActivity)
}

@MainActor
@Test
func closedRowsHideRightSideStatusText() throws {
    let rowView = ResultRowView(frame: NSRect(x: 0, y: 0, width: 480, height: ResultRowView.rowHeightWithoutActivity))
    let closedResult = SearchResult(
        sessionId: "closed",
        tool: "claude",
        title: "Closed session",
        project: "/tmp/project",
        projectName: "project",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(timeIntervalSince1970: 50_880),
        pid: nil,
        tokenCount: 0,
        lastActivityAt: Date(timeIntervalSince1970: 50_910),
        activityPreview: nil,
        activityStatus: .closed,
        snippet: nil
    )

    rowView.configure(with: closedResult)
    rowView.layoutSubtreeIfNeeded()

    let statusLabel = try #require(statusTextField(in: rowView))
    #expect(statusLabel.isHidden)
}

@MainActor
@Test
func waitingRowsShowAwaitingInputWithBreathingAnimation() throws {
    let rowView = ResultRowView(frame: NSRect(x: 0, y: 0, width: 480, height: ResultRowView.rowHeightWithActivity))
    let waitingResult = SearchResult(
        sessionId: "waiting",
        tool: "codex",
        title: "Waiting session",
        project: "/tmp/project",
        projectName: "project",
        gitBranch: "main",
        status: "live",
        startedAt: Date(timeIntervalSince1970: 50_880),
        pid: 42,
        tokenCount: 1_200,
        lastActivityAt: Date(timeIntervalSince1970: 50_910),
        activityPreview: ActivityPreview(text: "Assistant is paused", kind: .assistant),
        activityStatus: .waiting,
        snippet: nil
    )

    rowView.configure(with: waitingResult)
    rowView.layoutSubtreeIfNeeded()

    let statusLabel = try #require(statusTextField(in: rowView))
    #expect(statusLabel.isHidden == false)
    #expect(statusLabel.stringValue == "AWAITING")
    let textColor = try #require(statusLabel.textColor?.usingColorSpace(.deviceRGB))
    // #FFC965 = (1.0, 0.788, 0.396)
    #expect(abs(textColor.redComponent - 1.0) < 0.01)
    #expect(abs(textColor.greenComponent - 0.788) < 0.02)
    #expect(abs(textColor.blueComponent - 0.396) < 0.02)
    let layer = try #require(statusLabel.layer)
    #expect(layer.animation(forKey: "breathe") != nil)
}

@MainActor
@Test
func searchPanelActionHintMatchesSelectedSessionStatus() async throws {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("search_hint_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    try index.upsertSession(
        id: "live",
        tool: "codex",
        title: "Working session",
        project: "/Users/me/project",
        projectName: "project",
        gitBranch: "main",
        status: "live",
        startedAt: Date(timeIntervalSince1970: 50_880),
        pid: 4242
    )
    try index.upsertSession(
        id: "closed",
        tool: "claude",
        title: "Archived session",
        project: "/Users/me/project",
        projectName: "project",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(timeIntervalSince1970: 50_800),
        pid: nil
    )

    let controller = SearchPanelController()
    controller.sessionIndex = index
    controller.show()
    defer { controller.hide() }

    let searchField = try controllerChild(named: "searchField", in: controller, as: SearchField.self)
    let actionHintLabel = try controllerChild(named: "actionHintLabel", in: controller, as: NSTextField.self)
    let resultsTableView = try controllerChild(named: "resultsTableView", in: controller, as: NSTableView.self)

    #expect(actionHintLabel.stringValue == "↩ Switch")

    searchField.stringValue = "Archived"
    controller.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: searchField)
    )

    let deadline = Date().addingTimeInterval(3.0)
    var leadingResultIsClosed = false
    while Date() < deadline {
        let currentResults = try controllerChild(named: "results", in: controller, as: [SearchResult].self)
        if currentResults.first?.status == "closed" {
            leadingResultIsClosed = true
            break
        }
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(leadingResultIsClosed)
    controller.tableViewSelectionDidChange(
        Notification(name: NSTableView.selectionDidChangeNotification, object: resultsTableView)
    )

    #expect(actionHintLabel.stringValue == "↩ Resume ⇥ History")
}

@MainActor
@Test
func searchPanelInjectsNewSessionActionsAndShowsLaunchHint() async throws {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("search_new_actions_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    try index.upsertSession(
        id: "existing-new-match",
        tool: "claude",
        title: "new feature notes",
        project: "/Users/me/project",
        projectName: "project",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(timeIntervalSince1970: 50_800),
        pid: nil
    )

    let controller = SearchPanelController()
    controller.sessionIndex = index
    controller.show()
    defer { controller.hide() }

    let searchField = try controllerChild(named: "searchField", in: controller, as: SearchField.self)
    let actionHintLabel = try controllerChild(named: "actionHintLabel", in: controller, as: NSTextField.self)

    searchField.stringValue = "new"
    controller.controlTextDidChange(
        Notification(name: NSControl.textDidChangeNotification, object: searchField)
    )

    let deadline = Date().addingTimeInterval(3.0)
    var injectedActions = false
    while Date() < deadline {
        let currentResults = try controllerChild(named: "results", in: controller, as: [SearchResult].self)
        if currentResults.count >= 2,
           currentResults[0].sessionId == "new-claude",
           currentResults[0].status == "action",
           currentResults[1].sessionId == "new-codex",
           currentResults[1].status == "action" {
            injectedActions = true
            break
        }
        try await Task.sleep(for: .milliseconds(20))
    }

    #expect(injectedActions)
    #expect(actionHintLabel.stringValue == "↩ Launch")
}

@MainActor
private func statusTextField(in view: NSView) -> NSTextField? {
    allTextFields(in: view).first { $0.alignment == .right }
}

@MainActor
private func allTextFields(in view: NSView) -> [NSTextField] {
    var textFields: [NSTextField] = []
    if let textField = view as? NSTextField {
        textFields.append(textField)
    }

    for subview in view.subviews {
        textFields.append(contentsOf: allTextFields(in: subview))
    }

    return textFields
}

private func controllerChild<Value>(
    named name: String,
    in controller: SearchPanelController,
    as _: Value.Type
) throws -> Value {
    try #require(
        Mirror(reflecting: controller).children.first(where: { $0.label == name })?.value as? Value
    )
}
