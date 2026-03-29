import Testing
@testable import VibeLight

@Test
func codexAndClaudeTranscriptChangesTriggerImmediateLiveRefresh() {
    let changedPaths = [
        "/Users/me/.claude/projects/project-a/session-1.jsonl",
        "/Users/me/.codex/sessions/2026/03/29/rollout-abc.jsonl",
    ]

    #expect(Indexer.shouldRefreshLiveSessions(forChangedPaths: changedPaths))
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
