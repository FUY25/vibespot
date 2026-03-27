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
