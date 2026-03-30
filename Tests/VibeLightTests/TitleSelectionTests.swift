import Foundation
import Testing
@testable import Flare

@Test
func testTitleCandidateSkipsClaudeCommandXML() {
    let raw = """
    <command-name>/clear</command-name>
    <command-message>clear</command-message>
    <command-args></command-args>
    """

    let title = SessionTitleNormalizer.titleCandidate(from: raw)

    #expect(title == nil)
}

@Test
func testTitleCandidateSkipsCodexEnvironmentContextXML() {
    let raw = """
    <environment_context>
      <cwd>/Users/me/project</cwd>
      <approval_policy>on-request</approval_policy>
      <sandbox_mode>workspace-write</sandbox_mode>
    </environment_context>
    """

    let title = SessionTitleNormalizer.titleCandidate(from: raw)

    #expect(title == nil)
}

@Test
func testTitleCandidateStripsInlineXMLTags() {
    let raw = "Fix <file>auth/token.go</file> expiration"

    let title = SessionTitleNormalizer.titleCandidate(from: raw)

    #expect(title == "Fix auth/token.go expiration")
}

@Test
func testFirstMeaningfulUserTitleSkipsXMLNoiseMessages() {
    let messages = [
        ParsedMessage(
            role: "user",
            content: "<command-name>/clear</command-name><command-message>clear</command-message>",
            timestamp: .distantPast,
            toolCalls: [],
            sessionId: "session-001",
            gitBranch: nil,
            cwd: nil
        ),
        ParsedMessage(
            role: "user",
            content: "<environment_context><cwd>/Users/me/project</cwd></environment_context>",
            timestamp: .distantPast,
            toolCalls: [],
            sessionId: "session-001",
            gitBranch: nil,
            cwd: nil
        ),
        ParsedMessage(
            role: "user",
            content: "fix the auth token expiration bug",
            timestamp: .distantPast,
            toolCalls: [],
            sessionId: "session-001",
            gitBranch: nil,
            cwd: nil
        ),
    ]

    let title = SessionTitleNormalizer.firstMeaningfulUserTitle(in: messages)

    #expect(title == "fix the auth token expiration bug")
}

@Test
func testDisplayTitleCandidatePrefersCodexRequestSection() {
    let raw = """
    # Context from my IDE setup:

    ## Active file: Sources/VibeLight/Watchers/Indexer.swift

    ## Open tabs:
    - Indexer.swift: Sources/VibeLight/Watchers/Indexer.swift

    ## My request for Codex:
    tighten the title selection heuristics for pasted terminal output
    """

    let title = SessionTitleNormalizer.displayTitleCandidate(from: raw)

    #expect(title == "tighten the title selection heuristics for pasted terminal output")
}

@Test
func testDisplayTitleCandidatePrefersRequestOverContextLines() {
    let raw = """
    # Context from my IDE setup:

    the project is a Swift menu bar app

    ## My request for Codex:
    wire the search panel into AppDelegate
    """

    let title = SessionTitleNormalizer.displayTitleCandidate(from: raw)

    #expect(title == "wire the search panel into AppDelegate")
}

@Test
func testFirstMeaningfulDisplayTitleSkipsOutputLikeUserMessagesWhenLaterPromptExists() {
    let messages = [
        ParsedMessage(
            role: "user",
            content: """
            zsh: command not found: vibelight
            Exit code: 127
            Duration: 0.2s
            """,
            timestamp: .distantPast,
            toolCalls: [],
            sessionId: "session-002",
            gitBranch: nil,
            cwd: nil
        ),
        ParsedMessage(
            role: "user",
            content: "add a display-title heuristic for pasted terminal output",
            timestamp: .distantPast,
            toolCalls: [],
            sessionId: "session-002",
            gitBranch: nil,
            cwd: nil
        ),
    ]

    let title = SessionTitleNormalizer.firstMeaningfulDisplayTitle(in: messages)

    #expect(title == "add a display-title heuristic for pasted terminal output")
}

@Test
func testFirstMeaningfulDisplayTitleSkipsSingleLineErrorWhenLaterPromptExists() {
    let messages = [
        ParsedMessage(
            role: "user",
            content: "Error: command failed with exit code 1",
            timestamp: .distantPast,
            toolCalls: [],
            sessionId: "session-004",
            gitBranch: nil,
            cwd: nil
        ),
        ParsedMessage(
            role: "user",
            content: "fix the failing launch command",
            timestamp: .distantPast,
            toolCalls: [],
            sessionId: "session-004",
            gitBranch: nil,
            cwd: nil
        ),
    ]

    let title = SessionTitleNormalizer.firstMeaningfulDisplayTitle(in: messages)

    #expect(title == "fix the failing launch command")
}

@Test
func testFirstMeaningfulDisplayTitleFallsBackToParserTitleWhenNoBetterCandidateExists() {
    let messages = [
        ParsedMessage(
            role: "user",
            content: """
            zsh: command not found: vibelight
            Exit code: 127
            """,
            timestamp: .distantPast,
            toolCalls: [],
            sessionId: "session-003",
            gitBranch: nil,
            cwd: nil
        ),
    ]

    let title = SessionTitleNormalizer.firstMeaningfulDisplayTitle(in: messages)

    #expect(title == "zsh: command not found: vibelight Exit code: 127")
}
