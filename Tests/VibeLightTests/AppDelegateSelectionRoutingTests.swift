import Foundation
import Testing
@testable import VibeLight

@MainActor
@Test
func routesSelectionByStatusAndTool() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let actionCodex = SearchResult(
        sessionId: "new-codex",
        tool: "codex",
        title: "New Codex Session",
        project: "/tmp/proj-a",
        projectName: "proj-a",
        gitBranch: "",
        status: "action",
        startedAt: now,
        pid: nil,
        tokenCount: 0,
        lastActivityAt: now,
        activityPreview: nil,
        activityStatus: .closed,
        snippet: nil
    )

    let actionClaude = SearchResult(
        sessionId: "new-claude",
        tool: "claude",
        title: "New Claude Session",
        project: "/tmp/proj-b",
        projectName: "proj-b",
        gitBranch: "",
        status: "action",
        startedAt: now,
        pid: nil,
        tokenCount: 0,
        lastActivityAt: now,
        activityPreview: nil,
        activityStatus: .closed,
        snippet: nil
    )

    let live = SearchResult(
        sessionId: "live-session",
        tool: "claude",
        title: "Live Session",
        project: "/tmp/proj-live",
        projectName: "proj-live",
        gitBranch: "",
        status: "live",
        startedAt: now,
        pid: 42,
        tokenCount: 0,
        lastActivityAt: now,
        activityPreview: nil,
        activityStatus: .closed,
        snippet: nil
    )

    let closedCodex = SearchResult(
        sessionId: "codex-123",
        tool: "codex",
        title: "Closed Codex",
        project: "/tmp/proj-c",
        projectName: "proj-c",
        gitBranch: "",
        status: "closed",
        startedAt: now,
        pid: nil,
        tokenCount: 0,
        lastActivityAt: now,
        activityPreview: nil,
        activityStatus: .closed,
        snippet: nil
    )

    let closedClaude = SearchResult(
        sessionId: "claude-999",
        tool: "claude",
        title: "Closed Claude",
        project: "/tmp/proj-d",
        projectName: "proj-d",
        gitBranch: "",
        status: "closed",
        startedAt: now,
        pid: nil,
        tokenCount: 0,
        lastActivityAt: now,
        activityPreview: nil,
        activityStatus: .closed,
        snippet: nil
    )
    let closedClaudeNoProject = SearchResult(
        sessionId: "claude-empty-project",
        tool: "claude",
        title: "Closed Claude Empty Project",
        project: "   ",
        projectName: "",
        gitBranch: "",
        status: "closed",
        startedAt: now,
        pid: nil,
        tokenCount: 0,
        lastActivityAt: now,
        activityPreview: nil,
        activityStatus: .closed,
        snippet: nil
    )

    var launched: [(command: String, directory: String)] = []
    var jumped: [SearchResult] = []
    let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path

    AppDelegate.routeSelection(actionCodex, launch: { command, directory in
        launched.append((command, directory))
    }, jump: { result in
        jumped.append(result)
    })

    AppDelegate.routeSelection(actionClaude, launch: { command, directory in
        launched.append((command, directory))
    }, jump: { result in
        jumped.append(result)
    })

    AppDelegate.routeSelection(live, launch: { command, directory in
        launched.append((command, directory))
    }, jump: { result in
        jumped.append(result)
    })

    AppDelegate.routeSelection(closedCodex, launch: { command, directory in
        launched.append((command, directory))
    }, jump: { result in
        jumped.append(result)
    })

    AppDelegate.routeSelection(closedClaude, launch: { command, directory in
        launched.append((command, directory))
    }, jump: { result in
        jumped.append(result)
    })
    AppDelegate.routeSelection(closedClaudeNoProject, launch: { command, directory in
        launched.append((command, directory))
    }, jump: { result in
        jumped.append(result)
    })

    #expect(launched.count == 5)
    #expect(launched[0].command == "codex")
    #expect(launched[0].directory == "/tmp/proj-a")
    #expect(launched[1].command == "claude")
    #expect(launched[1].directory == "/tmp/proj-b")
    #expect(launched[2].command == "codex resume codex-123")
    #expect(launched[2].directory == "/tmp/proj-c")
    #expect(launched[3].command == "claude --resume claude-999")
    #expect(launched[3].directory == "/tmp/proj-d")
    #expect(launched[4].command == "claude --resume claude-empty-project")
    #expect(launched[4].directory == homeDirectory)

    #expect(jumped.map(\.sessionId) == ["live-session"])
}
