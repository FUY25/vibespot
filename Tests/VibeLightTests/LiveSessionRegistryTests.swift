import Testing
@testable import VibeLight

@Test
func parseCodexPIDsExtractsOnlyCodexPIDs() {
    let psOutput = """
      501  111 /usr/local/bin/codex
      501  222 /Applications/Claude.app/Contents/MacOS/Claude
      501  333 codex
      501  444 /usr/bin/zsh
      501  555 codex-helper
    """

    #expect(LiveSessionRegistry.parseCodexPIDs(from: psOutput) == [111, 333])
}

@Test
func parseCodexPIDsHandlesEmptyOutput() {
    #expect(LiveSessionRegistry.parseCodexPIDs(from: "").isEmpty)
    #expect(LiveSessionRegistry.parseCodexPIDs(from: "   \n\n").isEmpty)
}

@Test
func parseCodexPIDsIgnoresNonCodexProcesses() {
    let psOutput = """
      501  222 /Applications/Claude.app/Contents/MacOS/Claude
      501  444 /usr/bin/zsh
      501  666 /opt/homebrew/bin/node
    """

    #expect(LiveSessionRegistry.parseCodexPIDs(from: psOutput).isEmpty)
}

@Test
func parseCwdExtractsWorkingDirectoryFromLsofOutput() {
    let lsofOutput = """
    p12345
    fcwd
    n/Users/me/project
    """

    #expect(LiveSessionRegistry.parseCwd(from: lsofOutput, pid: 12345) == "/Users/me/project")
}

@Test
func parseCwdReturnsNilForEmptyOrInvalidOutput() {
    #expect(LiveSessionRegistry.parseCwd(from: "", pid: 12345) == nil)
    #expect(LiveSessionRegistry.parseCwd(from: "p12345\nfcwd\n", pid: 12345) == nil)
    #expect(LiveSessionRegistry.parseCwd(from: "p12345\n", pid: 12345) == nil)
    #expect(LiveSessionRegistry.parseCwd(from: "n\n", pid: 12345) == nil)
}

@Test
func parseCwdIgnoresOtherProcesses() {
    let lsofOutput = """
    p172
    fcwd
    n/
    p487
    fcwd
    n/Users/me/other-project
    p12345
    fcwd
    n/Users/me/target-project
    """

    #expect(LiveSessionRegistry.parseCwd(from: lsofOutput, pid: 12345) == "/Users/me/target-project")
}

@Test
func parseCwdReturnsNilWhenTargetPidNotFound() {
    let lsofOutput = """
    p172
    fcwd
    n/
    p487
    fcwd
    n/Users/me/other-project
    """

    #expect(LiveSessionRegistry.parseCwd(from: lsofOutput, pid: 99999) == nil)
}

@Test
func parseRolloutPathExtractsCodexSessionJSONLFromBatchedLsofOutput() {
    let lsofOutput = """
    p172
    fcwd
    n/Users/me/other-project
    f11
    n/Users/me/.codex/sessions/2026/03/28/rollout-other.jsonl
    p12345
    fcwd
    n/Users/me/project
    f21
    n/Users/me/.codex/sessions/2026/03/28/rollout-target.jsonl
    f22
    n/Users/me/project/README.md
    """

    #expect(
        LiveSessionRegistry.parseRolloutPath(from: lsofOutput, pid: 12345)
            == "/Users/me/.codex/sessions/2026/03/28/rollout-target.jsonl"
    )
}

@Test
func parseRolloutPathReturnsNilWhenTargetPidHasNoCodexSessionJSONL() {
    let lsofOutput = """
    p12345
    fcwd
    n/Users/me/project
    f21
    n/Users/me/project/README.md
    f22
    n/Users/me/.codex/sessions/2026/03/28/not-a-rollout.jsonl
    """

    #expect(LiveSessionRegistry.parseRolloutPath(from: lsofOutput, pid: 12345) == nil)
}

@Test
func parseRolloutPathReturnsNilWhenMultipleCodexSessionJSONLCandidatesExist() {
    let lsofOutput = """
    p12345
    fcwd
    n/Users/me/project
    f21
    n/Users/me/.codex/sessions/2026/03/28/rollout-first.jsonl
    f22
    n/Users/me/.codex/sessions/2026/03/28/rollout-second.jsonl
    """

    #expect(LiveSessionRegistry.parseRolloutPath(from: lsofOutput, pid: 12345) == nil)
}

@Test
func resolveCodexSessionIDPrefersRolloutPathDBMapping() {
    let sessionId = LiveSessionRegistry.resolveCodexSessionID(
        rolloutPath: "/Users/me/.codex/sessions/2026/03/28/rollout-abc-11111111-2222-3333-4444-555555555555.jsonl",
        cwd: "/Users/me/project",
        sessionIdByRolloutPath: { _ in "db-rollout-id" },
        sessionIdByCwd: { _ in "db-cwd-id" }
    )

    #expect(sessionId == "db-rollout-id")
}

@Test
func resolveCodexSessionIDFallsBackToUUIDEmbeddedInRolloutPath() {
    let sessionId = LiveSessionRegistry.resolveCodexSessionID(
        rolloutPath: "/Users/me/.codex/sessions/2026/03/28/rollout-abc-11111111-2222-3333-4444-555555555555.jsonl",
        cwd: "/Users/me/project",
        sessionIdByRolloutPath: { _ in nil as String? },
        sessionIdByCwd: { _ in "db-cwd-id" }
    )

    #expect(sessionId == "11111111-2222-3333-4444-555555555555")
}

@Test
func resolveCodexSessionIDFallsBackToCwdWhenRolloutPathCannotResolve() {
    let sessionId = LiveSessionRegistry.resolveCodexSessionID(
        rolloutPath: "/Users/me/.codex/sessions/2026/03/28/rollout-no-uuid.jsonl",
        cwd: "/Users/me/project",
        sessionIdByRolloutPath: { _ in nil as String? },
        sessionIdByCwd: { _ in "db-cwd-id" }
    )

    #expect(sessionId == "db-cwd-id")
}
