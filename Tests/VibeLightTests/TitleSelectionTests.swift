import Foundation
import Testing
@testable import VibeLight

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
