import Dispatch
import Testing
@testable import Flare

private func makeCustomResolution() -> SessionSourceResolution {
    SessionSourceResolution(
        claudeRootPath: "/tmp/custom/.claude",
        codexRootPath: "/tmp/custom/.codex",
        claudeProjectsPath: "/tmp/custom/.claude/projects",
        claudeSessionsPath: "/tmp/custom/.claude/sessions",
        codexSessionsPath: "/tmp/custom/.codex/sessions",
        codexStatePath: "/tmp/custom/.codex/state_5.sqlite",
        autoClaudeAvailable: true,
        autoCodexAvailable: true,
        usingCustomClaude: true,
        usingCustomCodex: true,
        customRequestedButUnavailable: false,
        autoFallbackForClaude: false,
        autoFallbackForCodex: false,
        requestedMode: .custom
    )
}

@Test
func codexAndClaudeTranscriptChangesTriggerImmediateLiveRefresh() {
    let changedPaths = [
        "/Users/me/.claude/projects/project-a/session-1.jsonl",
        "/Users/me/.codex/sessions/2026/03/29/rollout-abc.jsonl",
    ]

    #expect(Indexer.shouldRefreshLiveSessions(forChangedPaths: changedPaths))
}

@Test
func shouldRefreshLiveSessionsUsesResolvedSourcePaths() {
    let customResolution = makeCustomResolution()

    let changedPaths = [
        "/tmp/custom/.claude/projects/project-a/session-1.jsonl",
        "/tmp/custom/.codex/sessions/2026/03/29/rollout-abc.jsonl",
    ]

    #expect(Indexer.shouldRefreshLiveSessions(forChangedPaths: changedPaths, sourceResolution: customResolution))
}

@Test
func unrelatedChangesDoNotForceImmediateLiveRefresh() {
    let changedPaths = [
        "/Users/me/.claude/projects/project-a/sessions-index.json",
        "/Users/me/.codex/session_index.jsonl",
        "/Users/me/project/README.md",
    ]

    #expect(Indexer.shouldRefreshLiveSessions(forChangedPaths: changedPaths) == false)
}

@Test
func codexMetadataChangesUseTargetedRefreshInsteadOfFullReindex() {
    let refreshPlan = Indexer.codexMetadataRefreshPlan(
        forChangedPaths: [
            "/tmp/custom/.codex/session_index.jsonl",
            "/tmp/custom/.codex/state_5.sqlite",
        ],
        sourceResolution: makeCustomResolution()
    )

    #expect(refreshPlan.forceFullTranscriptReindex == false)
    #expect(refreshPlan.refreshTitles)
    #expect(refreshPlan.refreshGitBranches)
}

@Test
func fileWatcherDefaultsToBackgroundQueue() {
    #expect(FileWatcher.defaultCallbackQueueLabel != DispatchQueue.main.label)
}

@Test
func indexerHeavyChangeHandlingUsesBackgroundQueue() {
    #expect(Indexer.changeHandlingQueueLabel != DispatchQueue.main.label)
}

@Test
func promptDerivedTitlesStayWeakForFastLiveRefresh() {
    #expect(
        IndexingHelpers.hasWeakLiveTitle(
            currentTitle: "old prompt",
            projectName: "vibelight",
            storedLastUserPrompt: "old prompt"
        )
    )
}

@Test
func smartTitlesDoNotStayWeakForFastLiveRefresh() {
    #expect(
        IndexingHelpers.hasWeakLiveTitle(
            currentTitle: "Ship telemetry in the panel",
            projectName: "vibelight",
            storedLastUserPrompt: "old prompt"
        ) == false
    )
}
