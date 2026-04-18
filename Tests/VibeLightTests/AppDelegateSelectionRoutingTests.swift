import Foundation
import Testing
@testable import Flare

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

@MainActor
@Test("fuzzy launch intent helpers detect codex and claude queries")
func fuzzyLaunchIntentHelpersDetectToolQueries() {
    #expect(SearchPanelController.matchesCodexLaunchIntent("co"))
    #expect(SearchPanelController.matchesCodexLaunchIntent("new cod"))
    #expect(!SearchPanelController.matchesCodexLaunchIntent("c"))
    #expect(!SearchPanelController.matchesCodexLaunchIntent("claude"))

    #expect(SearchPanelController.matchesClaudeLaunchIntent("cla"))
    #expect(SearchPanelController.matchesClaudeLaunchIntent("new cl"))
    #expect(!SearchPanelController.matchesClaudeLaunchIntent("c"))
    #expect(!SearchPanelController.matchesClaudeLaunchIntent("codex"))

    #expect(SearchPanelController.looksLikeNewSessionIntent("new"))
    #expect(SearchPanelController.looksLikeNewSessionIntent("co"))
    #expect(SearchPanelController.looksLikeNewSessionIntent("new claude"))
    #expect(!SearchPanelController.looksLikeNewSessionIntent("n"))
    #expect(!SearchPanelController.looksLikeNewSessionIntent("ne"))
    #expect(!SearchPanelController.looksLikeNewSessionIntent("c"))
    #expect(!SearchPanelController.looksLikeNewSessionIntent("resume old session"))
}

@MainActor
@Test("results render signature changes when only the query changes")
func resultsRenderSignatureChangesWhenOnlyQueryChanges() {
    let result = SearchResult(
        sessionId: "sess-cache-key",
        tool: "claude",
        title: "Renderer cleanup",
        project: "/Users/fuyuming/Desktop/project/vibelight",
        projectName: "vibelight",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(timeIntervalSince1970: 1_700_000_000),
        pid: nil,
        tokenCount: 0,
        lastActivityAt: Date(timeIntervalSince1970: 1_700_000_100),
        activityPreview: nil,
        activityStatus: .closed,
        snippet: nil
    )
    let resultsJSON = WebBridge.resultsToJSONString([result])

    let signatureA = SearchPanelController.resultsRenderSignature(resultsJSON: resultsJSON, query: "vi")
    let signatureB = SearchPanelController.resultsRenderSignature(resultsJSON: resultsJSON, query: "vibe")
    let signatureC = SearchPanelController.resultsRenderSignature(resultsJSON: resultsJSON, query: "vibe")

    #expect(signatureA != signatureB)
    #expect(signatureB == signatureC)
}

@MainActor
@Test("new-session command parser keeps allowlisted flags and turns the rest into prompt")
func newSessionCommandParserKeepsFlagsAndPrompt() {
    let codex = SearchPanelController.parseNewSessionCommand(from: "new codex --yolo fix auth bug")
    #expect(codex == NewSessionCommand(tool: "codex", flags: ["--yolo"], prompt: "fix auth bug"))

    let codexWithSessionFiller = SearchPanelController.parseNewSessionCommand(from: "new codex session")
    #expect(codexWithSessionFiller == NewSessionCommand(tool: "codex", flags: [], prompt: ""))

    let claudeWithSessionFillerAndPrompt = SearchPanelController.parseNewSessionCommand(
        from: "new claude session summarize this thread"
    )
    #expect(claudeWithSessionFillerAndPrompt == NewSessionCommand(
        tool: "claude",
        flags: [],
        prompt: "summarize this thread"
    ))

    let codexStopAtUnknownFlag = SearchPanelController.parseNewSessionCommand(
        from: "codex --help --verbose draft release notes"
    )
    #expect(codexStopAtUnknownFlag == NewSessionCommand(
        tool: "codex",
        flags: ["--help"],
        prompt: "--verbose draft release notes"
    ))

    let claude = SearchPanelController.parseNewSessionCommand(from: "claude --help summarize this thread")
    #expect(claude == NewSessionCommand(tool: "claude", flags: ["--help"], prompt: "summarize this thread"))

    let claudeUnsupportedFlag = SearchPanelController.parseNewSessionCommand(from: "claude --yolo quick idea")
    #expect(claudeUnsupportedFlag == NewSessionCommand(tool: "claude", flags: [], prompt: "--yolo quick idea"))

    #expect(SearchPanelController.parseNewSessionCommand(from: "new session") == nil)
}

@MainActor
@Test("new-session launch command uses parsed flags and prompt for selected action tool")
func newSessionLaunchCommandUsesParsedFlagsAndPrompt() {
    let codexCommand = SearchPanelController.newSessionLaunchCommand(
        selectedTool: "codex",
        query: "new codex --yolo fix auth bug"
    )
    #expect(codexCommand == "codex --yolo 'fix auth bug'")

    let claudeCommand = SearchPanelController.newSessionLaunchCommand(
        selectedTool: "claude",
        query: "new claude --help summarize this thread"
    )
    #expect(claudeCommand == "claude --help 'summarize this thread'")
}

@MainActor
@Test("new-session launch command falls back to selected tool when parse tool does not match")
func newSessionLaunchCommandFallsBackToSelectedTool() {
    let command = SearchPanelController.newSessionLaunchCommand(
        selectedTool: "claude",
        query: "new codex --yolo fix auth bug"
    )
    #expect(command == "claude '--yolo fix auth bug'")
}

@MainActor
@Test("new-session launch command does not send launcher control words as prompt")
func newSessionLaunchCommandDoesNotSendLauncherControlWordsAsPrompt() {
    let bareNew = SearchPanelController.newSessionLaunchCommand(
        selectedTool: "claude",
        query: "new"
    )
    #expect(bareNew == "claude")

    let newClaude = SearchPanelController.newSessionLaunchCommand(
        selectedTool: "claude",
        query: "New claude"
    )
    #expect(newClaude == "claude")

    let newCodex = SearchPanelController.newSessionLaunchCommand(
        selectedTool: "codex",
        query: "new codex"
    )
    #expect(newCodex == "codex")
}

@MainActor
@Test("controller action selection uses stored query and launch hook")
func controllerActionSelectionUsesStoredQueryAndLaunchHook() throws {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibelight-controller-action-\(UUID().uuidString).sqlite3")
        .path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    let now = Date()
    try index.upsertSession(
        id: "seed-session",
        tool: "codex",
        title: "Seed",
        project: "/tmp/controller-launch",
        projectName: "controller-launch",
        gitBranch: "",
        status: "closed",
        startedAt: now,
        pid: nil
    )

    let controller = SearchPanelController()
    controller.sessionIndex = index

    var launched: [(command: String, directory: String)] = []
    var selected: [SearchResult] = []
    controller.onLaunchAction = { command, directory in
        launched.append((command, directory))
    }
    controller.onSelect = { result in
        selected.append(result)
    }

    let bridge = WebBridge()
    controller.webBridge(bridge, didReceiveSearch: "new codex --yolo fix auth bug")
    controller.webBridge(
        bridge,
        didSelectSession: "new-codex",
        status: "action",
        tool: "codex",
        query: "new codex --yolo fix auth bug"
    )

    #expect(launched.count == 1)
    #expect(launched[0].command == "codex --yolo 'fix auth bug'")
    #expect(launched[0].directory == "/tmp/controller-launch")
    #expect(selected.isEmpty)
}

@MainActor
@Test("controller action selection prefers explicit select query over stale debounced search state")
func controllerActionSelectionPrefersExplicitSelectQuery() throws {
    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("vibelight-controller-action-stale-\(UUID().uuidString).sqlite3")
        .path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    let now = Date()
    try index.upsertSession(
        id: "seed-session",
        tool: "codex",
        title: "Seed",
        project: "/tmp/controller-launch",
        projectName: "controller-launch",
        gitBranch: "",
        status: "closed",
        startedAt: now,
        pid: nil
    )

    let controller = SearchPanelController()
    controller.sessionIndex = index

    var launched: [(command: String, directory: String)] = []
    controller.onLaunchAction = { command, directory in
        launched.append((command, directory))
    }

    let bridge = WebBridge()
    controller.webBridge(bridge, didReceiveSearch: "new")
    controller.webBridge(
        bridge,
        didSelectSession: "new-codex",
        status: "action",
        tool: "codex",
        query: "new codex session"
    )

    #expect(launched.count == 1)
    #expect(launched[0].command == "codex")
    #expect(launched[0].directory == "/tmp/controller-launch")
}
