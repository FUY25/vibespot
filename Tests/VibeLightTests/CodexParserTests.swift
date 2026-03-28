import Foundation
import Testing
@testable import VibeLight

@Test
func testParseCodexSessionIndex() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "codex_session_index", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let entries = try CodexParser.parseSessionIndex(url: fixtureURL)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    #expect(entries.count == 2)
    #expect(entries[0].sessionId == "codex-001")
    #expect(entries[0].title == "Analyze folder structure")
    #expect(entries[0].projectPath.isEmpty)
    #expect(entries[0].gitBranch.isEmpty)
    #expect(entries[0].firstPrompt == nil)
    #expect(entries[0].isSidechain == false)
    #expect(entries[0].startedAt == formatter.date(from: "2026-03-22T13:17:39.96871Z"))
    #expect(entries[1].sessionId == "codex-002")
    #expect(entries[1].title == "Move OCR files and plan batch run")
}

@Test
func testParseCodexSessionFile() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "codex_session", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let (meta, messages, telemetry) = try CodexParser.parseSessionFile(url: fixtureURL)
    let parsedMeta = try #require(meta)

    #expect(parsedMeta.id == "codex-001")
    #expect(parsedMeta.cwd == "/Users/me/project")
    #expect(parsedMeta.cliVersion == "0.78.0")
    #expect(parsedMeta.source == "codex_cli")
    #expect(parsedMeta.isSubagent == false)

    #expect(messages.count == 7)
    #expect(messages[0].role == "user")
    #expect(messages[0].content == "analyze the folder structure of this project\nfocus on src and tests")
    #expect(messages[1].role == "assistant")
    #expect(messages[1].content == "I'll analyze the project structure.\nThe main directories are src/, tests/, and docs/.")
    #expect(messages.first(where: { $0.content.contains("sandbox_mode is danger-full-access") }) == nil)

    let functionCallMessage = try #require(
        messages.first(where: { message in
            message.toolCalls.contains(where: { $0.contains("shell") && $0.contains("ls") })
        })
    )
    #expect(functionCallMessage.role == "assistant")

    let customToolCallMessage = try #require(
        messages.first(where: { message in
            message.toolCalls.contains(where: { $0.contains("grep_search") && $0.contains("TODO") })
        })
    )
    #expect(customToolCallMessage.role == "assistant")

    let functionOutputMessage = try #require(
        messages.first(where: { $0.content.contains("file1") && $0.content.contains("file2") })
    )
    #expect(functionOutputMessage.role == "assistant")

    let customToolOutputMessage = try #require(
        messages.first(where: { $0.content.contains("Found TODO in Sources/App.swift") })
    )
    #expect(customToolOutputMessage.role == "assistant")

    #expect(messages.last?.role == "assistant")
    #expect(messages.last?.content == "Running quick checks before final answer.")
    #expect(messages.allSatisfy { $0.sessionId == "codex-001" })
    #expect(messages.allSatisfy { $0.cwd == "/Users/me/project" })
    #expect(telemetry == nil)
}

@Test
func testParseCodexSessionFileExtractsLatestUsableContextTelemetry() throws {
    let fixtureURL = try #require(
        Bundle.module.url(forResource: "codex_context_session", withExtension: "jsonl", subdirectory: "Fixtures")
    )

    let (meta, messages, telemetry) = try CodexParser.parseSessionFile(url: fixtureURL)
    let parsedMeta = try #require(meta)
    let parsedTelemetry = try #require(telemetry)

    #expect(parsedMeta.id == "codex-ctx-001")
    #expect(parsedTelemetry.effectiveModel == "gpt-5.2-codex")
    #expect(parsedTelemetry.contextWindowTokens == 258400)
    #expect(parsedTelemetry.contextUsedEstimate == 84833)
    #expect(parsedTelemetry.contextPercentEstimate == 32)
    #expect(parsedTelemetry.contextConfidence == .high)
    #expect(parsedTelemetry.contextSource == "codex:last_token_usage")
    #expect(messages.count > 0)
}

@Test
func testParseCodexSessionFileDoesNotRetrofitLaterModelOntoExistingTelemetrySnapshot() throws {
    let fixtureURL = try writeTemporaryCodexSession(lines: [
        #"{"timestamp":"2026-01-14T10:06:14.970Z","type":"session_meta","payload":{"id":"codex-ctx-002","cwd":"/Users/me/project","originator":"codex_cli","cli_version":"0.78.0"}}"#,
        #"{"timestamp":"2026-01-14T10:06:15.000Z","type":"turn_context","payload":{"cwd":"/Users/me/project","model":"gpt-5.2-codex"}}"#,
        #"{"timestamp":"2026-01-14T10:06:16.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":400,"cached_input_tokens":100},"model_context_window":1000}}}"#,
        #"{"timestamp":"2026-01-14T10:06:17.000Z","type":"turn_context","payload":{"cwd":"/Users/me/project","model":"gpt-5.3-codex"}}"#,
    ])

    let (_, _, telemetry) = try CodexParser.parseSessionFile(url: fixtureURL)
    let parsedTelemetry = try #require(telemetry)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    #expect(parsedTelemetry.effectiveModel == "gpt-5.2-codex")
    #expect(parsedTelemetry.contextWindowTokens == 1000)
    #expect(parsedTelemetry.contextUsedEstimate == 500)
    #expect(parsedTelemetry.contextPercentEstimate == 50)
    #expect(parsedTelemetry.contextConfidence == .high)
    #expect(parsedTelemetry.contextSource == "codex:last_token_usage")
    #expect(parsedTelemetry.lastContextSampleAt == formatter.date(from: "2026-01-14T10:06:16.000Z"))
}

@Test
func testParseCodexSessionFileKeepsLatestUsableTelemetryWhenLaterTokenCountIsIncomplete() throws {
    let fixtureURL = try writeTemporaryCodexSession(lines: [
        #"{"timestamp":"2026-01-14T10:06:14.970Z","type":"session_meta","payload":{"id":"codex-ctx-003","cwd":"/Users/me/project","originator":"codex_cli","cli_version":"0.78.0"}}"#,
        #"{"timestamp":"2026-01-14T10:06:15.000Z","type":"turn_context","payload":{"cwd":"/Users/me/project","model":"gpt-5.2-codex"}}"#,
        #"{"timestamp":"2026-01-14T10:06:16.000Z","type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":500,"cached_input_tokens":50},"model_context_window":1000}}}"#,
        #"{"timestamp":"2026-01-14T10:06:17.000Z","type":"event_msg","payload":{"type":"token_count","info":{"model_context_window":2000}}}"#,
    ])

    let (_, _, telemetry) = try CodexParser.parseSessionFile(url: fixtureURL)
    let parsedTelemetry = try #require(telemetry)
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

    #expect(parsedTelemetry.effectiveModel == "gpt-5.2-codex")
    #expect(parsedTelemetry.contextWindowTokens == 1000)
    #expect(parsedTelemetry.contextUsedEstimate == 550)
    #expect(parsedTelemetry.contextPercentEstimate == 55)
    #expect(parsedTelemetry.contextConfidence == .high)
    #expect(parsedTelemetry.contextSource == "codex:last_token_usage")
    #expect(parsedTelemetry.lastContextSampleAt == formatter.date(from: "2026-01-14T10:06:16.000Z"))
}

private func writeTemporaryCodexSession(lines: [String]) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

    let fixtureURL = directory.appendingPathComponent("codex-session.jsonl")
    try lines.joined(separator: "\n").write(to: fixtureURL, atomically: true, encoding: .utf8)
    return fixtureURL
}
