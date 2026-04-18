import Foundation
import Testing
@testable import Flare

@Test
func testParseSessionJSONL() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "claude_session", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let (messages, telemetry) = try ClaudeParser.parseSessionFile(url: fixtureURL)
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
    #expect(telemetry?.effectiveModel == "claude-sonnet-4-5-20250514")
    #expect(telemetry?.contextWindowTokens == nil)
    #expect(telemetry?.contextUsedEstimate == 300)
    #expect(telemetry?.contextPercentEstimate == nil)
    #expect(telemetry?.contextConfidence == .unknown)
    #expect(telemetry?.contextSource == "claude:assistant_usage")
}

@Test
func testParseSessionJSONLExtractsKnownClaudeContextTelemetryConservatively() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "claude_context_session", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let (messages, telemetry) = try ClaudeParser.parseSessionFile(url: fixtureURL)
    let parsedTelemetry = try #require(telemetry)

    #expect(messages.count == 2)
    #expect(parsedTelemetry.effectiveModel == "claude-haiku-4-5")
    #expect(parsedTelemetry.contextWindowTokens == 200000)
    #expect(parsedTelemetry.contextUsedEstimate == 60777)
    #expect(parsedTelemetry.contextPercentEstimate == 30)
    #expect(parsedTelemetry.contextConfidence == .medium)
    #expect(parsedTelemetry.contextSource == "claude:assistant_usage")
}

@Test
func testParseSessionJSONLReturnsPendingModelSwitchTelemetryWithoutBluffingContextWindow() throws {
    let fixtureURL = try #require(
        Bundle.module.url(
            forResource: "claude_context_session_model_switch",
            withExtension: "jsonl",
            subdirectory: "Fixtures"
        )
    )

    let (messages, telemetry) = try ClaudeParser.parseSessionFile(url: fixtureURL)
    let parsedTelemetry = try #require(telemetry)

    #expect(messages.count == 1)
    #expect(messages[0].role == "user")
    #expect(parsedTelemetry.effectiveModel == "claude-opus-4-6")
    #expect(parsedTelemetry.contextWindowTokens == nil)
    #expect(parsedTelemetry.contextUsedEstimate == nil)
    #expect(parsedTelemetry.contextPercentEstimate == nil)
    #expect(parsedTelemetry.contextConfidence == .unknown)
    #expect(parsedTelemetry.contextSource == "claude:model_switch_command")
}

@Test
func testParseSessionJSONLDoesNotTreatArbitraryUserTextAsModelSwitch() throws {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeParserTests-\(UUID().uuidString)", isDirectory: true)
    let fixtureURL = tempDirectory.appendingPathComponent("plain-user-text.jsonl")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let jsonl = """
    {"type":"user","timestamp":"2026-03-28T10:00:00Z","message":{"role":"user","content":"Set model to Opus 4.6 in the docs and explain the tradeoffs."}}
    """
    try jsonl.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let (messages, telemetry) = try ClaudeParser.parseSessionFile(url: fixtureURL)

    #expect(messages.count == 1)
    #expect(messages[0].role == "user")
    #expect(telemetry == nil)
}

@Test
func testParseSessionJSONLDoesNotTreatQuotedLocalCommandStdoutAsModelSwitch() throws {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeParserTests-\(UUID().uuidString)", isDirectory: true)
    let fixtureURL = tempDirectory.appendingPathComponent("quoted-stdout.jsonl")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let jsonl = """
    {"type":"user","timestamp":"2026-03-28T10:00:00Z","message":{"role":"user","content":[{"type":"text","text":"Please explain this snippet:\\nlocal command stdout:\\nSet model to Opus 4.6"}]}}
    """
    try jsonl.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let (messages, telemetry) = try ClaudeParser.parseSessionFile(url: fixtureURL)

    #expect(messages.count == 1)
    #expect(messages[0].role == "user")
    #expect(telemetry == nil)
}

@Test
func testParseSessionJSONLRecognizesLocalCommandStdoutPrefixModelSwitchWithAnnotatedTarget() throws {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeParserTests-\(UUID().uuidString)", isDirectory: true)
    let fixtureURL = tempDirectory.appendingPathComponent("stdout-switch.jsonl")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let jsonl = """
    {"type":"user","timestamp":"2026-03-28T10:00:00Z","message":{"role":"user","content":[{"type":"text","text":"local command stdout:\\nSet model to Opus 4.6 (1M beta)"}]}}
    """
    try jsonl.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let (messages, telemetry) = try ClaudeParser.parseSessionFile(url: fixtureURL)
    let parsedTelemetry = try #require(telemetry)

    #expect(messages.count == 1)
    #expect(messages[0].role == "user")
    #expect(parsedTelemetry.effectiveModel == "claude-opus-4-6")
    #expect(parsedTelemetry.contextWindowTokens == nil)
    #expect(parsedTelemetry.contextPercentEstimate == nil)
    #expect(parsedTelemetry.contextConfidence == .unknown)
    #expect(parsedTelemetry.contextSource == "claude:model_switch_command")
}

@Test
func testParseSessionJSONLDoesNotTreatFailedModelCommandAsSuccessfulSwitch() throws {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeParserTests-\(UUID().uuidString)", isDirectory: true)
    let fixtureURL = tempDirectory.appendingPathComponent("failed-switch.jsonl")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let jsonl = """
    {"type":"user","timestamp":"2026-03-28T10:00:00Z","message":{"role":"user","content":[{"type":"text","text":"<local-command-stdout>Failed to set model to Opus 4.6</local-command-stdout>"}]}}
    """
    try jsonl.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let (messages, telemetry) = try ClaudeParser.parseSessionFile(url: fixtureURL)

    #expect(messages.count == 1)
    #expect(messages[0].role == "user")
    #expect(telemetry == nil)
}

@Test
func testParseSessionJSONLCapturesTelemetryFromUsageOnlyAssistantTurnWithoutCreatingMessage() throws {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeParserTests-\(UUID().uuidString)", isDirectory: true)
    let fixtureURL = tempDirectory.appendingPathComponent("usage-only.jsonl")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let jsonl = """
    {"type":"assistant","timestamp":"2026-03-28T10:00:00Z","message":{"model":"claude-sonnet-4-5-20250514","usage":{"input_tokens":1234,"cache_read_input_tokens":4321,"cache_creation_input_tokens":0},"content":[{"type":"thinking","thinking":"internal only"}]}}
    """
    try jsonl.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let (messages, telemetry) = try ClaudeParser.parseSessionFile(url: fixtureURL)
    let parsedTelemetry = try #require(telemetry)

    #expect(messages.isEmpty)
    #expect(parsedTelemetry.effectiveModel == "claude-sonnet-4-5-20250514")
    #expect(parsedTelemetry.contextWindowTokens == nil)
    #expect(parsedTelemetry.contextUsedEstimate == 5555)
    #expect(parsedTelemetry.contextPercentEstimate == nil)
    #expect(parsedTelemetry.contextConfidence == .unknown)
    #expect(parsedTelemetry.contextSource == "claude:assistant_usage")
}

@Test
func testParseSessionJSONLFromByteOffsetReadsOnlyAppendedRecords() throws {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeParserTests-\(UUID().uuidString)", isDirectory: true)
    let fixtureURL = tempDirectory.appendingPathComponent("incremental.jsonl")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let original = #"{"type":"user","timestamp":"2026-03-28T10:00:00Z","message":{"role":"user","content":[{"type":"text","text":"first"}]}}"#
    try original.write(to: fixtureURL, atomically: true, encoding: .utf8)
    let originalLength = UInt64(try Data(contentsOf: fixtureURL).count)

    let appended = [
        original,
        #"{"type":"assistant","timestamp":"2026-03-28T10:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"second"}]}}"#,
    ].joined(separator: "\n")
    try appended.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let parsed = try ClaudeParser.parseSessionFile(url: fixtureURL, startingAtOffset: originalLength)

    #expect(parsed.requiresFullRebuild == false)
    #expect(parsed.messages.count == 1)
    #expect(parsed.messages[0].role == "assistant")
    #expect(parsed.messages[0].content == "second")
}

@Test
func testParseSessionJSONLFromMisalignedByteOffsetRequestsFullRebuild() throws {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClaudeParserTests-\(UUID().uuidString)", isDirectory: true)
    let fixtureURL = tempDirectory.appendingPathComponent("incremental-misaligned.jsonl")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

    let contents = [
        #"{"type":"user","timestamp":"2026-03-28T10:00:00Z","message":{"role":"user","content":[{"type":"text","text":"first"}]}}"#,
        #"{"type":"assistant","timestamp":"2026-03-28T10:00:01Z","message":{"role":"assistant","content":[{"type":"text","text":"second"}]}}"#,
    ].joined(separator: "\n")
    try contents.write(to: fixtureURL, atomically: true, encoding: .utf8)

    let parsed = try ClaudeParser.parseSessionFile(url: fixtureURL, startingAtOffset: 1)

    #expect(parsed.requiresFullRebuild == true)
    #expect(parsed.messages.isEmpty)
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
