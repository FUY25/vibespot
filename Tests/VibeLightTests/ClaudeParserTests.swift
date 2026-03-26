import Foundation
import Testing
@testable import VibeLight

@Test
func testParseSessionJSONL() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "claude_session", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let messages = try ClaudeParser.parseSessionFile(url: fixtureURL)
    let toolMessage = try #require(messages.first(where: { !$0.toolCalls.isEmpty }))
    let toolResultMessage = try #require(messages.first(where: { $0.role == "user" && $0.content.contains("RefreshToken") }))
    let finalAssistantMessage = try #require(messages.last)

    #expect(messages.count == 5)
    #expect(messages[0].role == "user")
    #expect(messages[0].content.contains("auth token expiration"))
    #expect(messages.first(where: { $0.content.contains("boilerplate instructions that should be ignored") }) == nil)
    #expect(toolMessage.toolCalls == ["Read: /Users/me/project/auth/token.go"])
    #expect(toolResultMessage.content.contains("RefreshToken"))
    #expect(finalAssistantMessage.content.contains("refreshToken was never persisted"))
    #expect(finalAssistantMessage.sessionId == "session-001")
    #expect(finalAssistantMessage.gitBranch == "feat/auth")
    #expect(finalAssistantMessage.cwd == "/Users/me/project")
}

@Test
func testParseSessionsIndex() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "sessions_index", withExtension: "json", subdirectory: "Fixtures")
    )

    let entries = try ClaudeParser.parseSessionsIndex(url: fixtureURL)

    #expect(entries.count == 1)
    #expect(entries[0].sessionId == "session-001")
    #expect(entries[0].title == "Auth Token Bug Fix")
    #expect(entries[0].firstPrompt == "fix the auth token expiration bug")
    #expect(entries[0].projectPath == "/Users/me/project")
    #expect(entries[0].gitBranch == "feat/auth")
}

@Test
func testParseHistoryJSONL() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "claude_history", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let entries = try ClaudeParser.parseHistory(url: fixtureURL)

    #expect(entries.count == 2)
    #expect(entries[0].sessionId == "session-001")
    #expect(entries[0].prompt == "fix the auth token expiration bug")
    #expect(entries[0].project == "/Users/me/project")
    #expect(entries[1].sessionId == "session-002")
}

@Test
func testParsePidRegistry() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "pid_registry", withExtension: "json", subdirectory: "Fixtures")
    )

    let entry = try ClaudeParser.parsePidFile(url: fixtureURL)

    #expect(entry.pid == 12345)
    #expect(entry.sessionId == "session-001")
    #expect(entry.cwd == "/Users/me/project")
}

@Test
func testDecodeProjectPath() {
    let decoded = ClaudeParser.decodeProjectPath("-Users-fuyuming-Desktop-project-terminalrail")

    #expect(decoded == "/Users/fuyuming/Desktop/project/terminalrail")
}

@Test
func testDecodeProjectPathPrefersFilesystemProbeForHyphenatedPaths() throws {
    let tempRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeParserTests-\(UUID().uuidString)", isDirectory: true)
    let projectsRoot = tempRoot.appendingPathComponent("projects", isDirectory: true)
    let encoded = "-Users-me-work-my-project-with-hyphen"
    let encodedDir = projectsRoot.appendingPathComponent(encoded, isDirectory: true)
    let expectedPath = "/Users/me/work/my-project-with-hyphen"

    try FileManager.default.createDirectory(at: encodedDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempRoot) }

    let sessionsIndexURL = encodedDir.appendingPathComponent("sessions-index.json")
    let sessionsIndexJSON = """
    {
      "entries": [
        {
          "sessionId": "session-001",
          "projectPath": "\(expectedPath)"
        }
      ]
    }
    """
    try sessionsIndexJSON.write(to: sessionsIndexURL, atomically: true, encoding: .utf8)

    let decoded = ClaudeParser.decodeProjectPath(encoded, projectsRoot: projectsRoot)

    #expect(decoded == expectedPath)
}
