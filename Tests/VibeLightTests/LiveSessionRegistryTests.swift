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

    #expect(LiveSessionRegistry.parseCodexPIDs(from: psOutput) == [111, 333, 555])
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

    #expect(LiveSessionRegistry.parseCwd(from: lsofOutput) == "/Users/me/project")
}

@Test
func parseCwdReturnsNilForEmptyOrInvalidOutput() {
    #expect(LiveSessionRegistry.parseCwd(from: "") == nil)
    #expect(LiveSessionRegistry.parseCwd(from: "p12345\nfcwd\n") == nil)
    #expect(LiveSessionRegistry.parseCwd(from: "p12345\n") == nil)
    #expect(LiveSessionRegistry.parseCwd(from: "n\n") == nil)
}
