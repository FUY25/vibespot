import Foundation
import Testing
@testable import Flare

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

    #expect(script.contains("do script \"cd \" & quoted form of \"/Users/me/project\" & \" && claude\""))
}

@Test
func testBuildScriptOmitsAndForEmptyCommand() {
    let script = TerminalLauncher.buildScript(
        command: "   ",
        directory: "/Users/me/project"
    )

    #expect(script.contains("do script \"cd \" & quoted form of \"/Users/me/project\""))
    #expect(!script.contains("&&"))
}

@Test
func testBuildScriptExpandsTildeDirectory() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let script = TerminalLauncher.buildScript(
        command: "claude",
        directory: "~/project"
    )

    #expect(script.contains("quoted form of \"\(home)/project\""))
}

@Test
func testBuildScriptEscapesQuotesInDirectory() {
    let script = TerminalLauncher.buildScript(
        command: "claude",
        directory: "/Users/me/project\"name"
    )

    #expect(script.contains("quoted form of \"/Users/me/project\\\"name\""))
}

@Test
func testBuildScriptReplacesCommandNewlines() {
    let script = TerminalLauncher.buildScript(
        command: "claude\n--resume abc",
        directory: "/Users/me/project"
    )

    #expect(script.contains("&& claude --resume abc"))
    #expect(!script.contains("&& claude\n--resume abc"))
}
