import Testing
@testable import VibeLight

@Test
func testBuildScriptEscapesDoubleQuotes() {
    let script = TerminalLauncher.buildScript(
        command: "claude --resume \"abc-123\"",
        directory: "/Users/me/my project"
    )

    #expect(script.contains("quoted form of \"/Users/me/my project\""))
    #expect(script.contains("claude --resume \\\"abc-123\\\""))
    #expect(script.contains("tell application \"Terminal\""))
    #expect(script.contains("do script"))
    #expect(script.contains("activate"))
}

@Test
func testBuildScriptEscapesBackslashesInPath() {
    let script = TerminalLauncher.buildScript(
        command: "codex",
        directory: "/Users/me/path\\with\\backslash"
    )

    #expect(script.contains("quoted form of \"/Users/me/path\\\\with\\\\backslash\""))
}

@Test
func testBuildScriptHandlesSimpleCommand() {
    let script = TerminalLauncher.buildScript(
        command: "claude",
        directory: "/Users/me/project"
    )

    #expect(script.contains("\"cd \" & quoted form of \"/Users/me/project\" & \" && claude\""))
}
