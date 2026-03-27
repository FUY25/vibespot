import AppKit
import Foundation
import Testing
@testable import VibeLight

@MainActor
@Test
func searchPanelHidesOnDeactivate() {
    let controller = SearchPanelController()
    #expect(controller.hidesOnDeactivate == true)
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
