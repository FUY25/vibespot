import Foundation
import Testing
@testable import Flare

@MainActor
@Test
func testFullScanStoresCleanedTitle() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("fullscan-title-clean-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let dbPath = tempRoot.appendingPathComponent("index.sqlite3").path

    let codexRoot = tempRoot.appendingPathComponent(".codex", isDirectory: true)
    let sessionsDirectory = codexRoot
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent("2026", isDirectory: true)
        .appendingPathComponent("03", isDirectory: true)
    try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

    let sessionId = "title-clean-001"
    let sessionFile = sessionsDirectory.appendingPathComponent("\(sessionId).jsonl")
    let sessionIndexFile = codexRoot.appendingPathComponent("session_index.jsonl")

    // JSON does not permit raw control characters, so ANSI ESC must be encoded as a unicode escape.
    let rawTitleJSON =
        "\\u001b[31mHow do we truncate this title without cutting supercalifragilisticexpialidocious while keeping the session title readable for fast scanning inside a crowded menu bar search result when the original prompt keeps going and going and going?\\u001b[0m"
    let expectedTitle =
        "How do we truncate this title without cutting supercalifragilisticexpialidocious while keeping the session title readable for fast scanning inside a crowded…?"

    let sessionIndexJSONL = """
    {"id":"\(sessionId)","thread_name":"\(rawTitleJSON)","updated_at":"2026-03-22T13:17:39.96871Z"}
    """
    try sessionIndexJSONL.write(to: sessionIndexFile, atomically: true, encoding: .utf8)

    let sessionJSONL = """
    {"timestamp":"2026-03-22T13:17:39.96871Z","type":"session_meta","payload":{"id":"\(sessionId)","cwd":"/Users/me/project","cli_version":"0.78.0"}}
    {"timestamp":"2026-03-22T13:17:40.00000Z","type":"response_item","payload":{"type":"message","role":"user","content":"hello"}}
    """
    try sessionJSONL.write(to: sessionFile, atomically: true, encoding: .utf8)

    let index = try SessionIndex(dbPath: dbPath)
    let indexer = Indexer(sessionIndex: index, homeDirectoryPath: tempRoot.path)
    indexer.performFullScan()

    let results = try index.search(query: "", includeHistory: true)
    // Filter to the test session only — real running processes may
    // leak via LiveSessionRegistry.scan() during performFullScan().
    let testResults = results.filter { $0.sessionId == sessionId }
    #expect(testResults.count == 1)

    let stored = testResults[0].title
    #expect(stored == expectedTitle)
    #expect(!stored.contains("\u{001b}"))
    #expect(stored.count <= 161)
}

@MainActor
@Test
func testFullScanPrefersLatestCodexPromptOverStalePromptDerivedThreadName() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("fullscan-codex-prompt-title-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let dbPath = tempRoot.appendingPathComponent("index.sqlite3").path

    let codexRoot = tempRoot.appendingPathComponent(".codex", isDirectory: true)
    let sessionsDirectory = codexRoot
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent("2026", isDirectory: true)
        .appendingPathComponent("04", isDirectory: true)
    try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)

    let sessionId = "codex-prompt-title-001"
    let sessionFile = sessionsDirectory.appendingPathComponent("\(sessionId).jsonl")
    let sessionIndexFile = codexRoot.appendingPathComponent("session_index.jsonl")

    let sessionIndexJSONL = """
    {"id":"\(sessionId)","thread_name":"old prompt","updated_at":"2026-04-08T09:00:00Z"}
    """
    try sessionIndexJSONL.write(to: sessionIndexFile, atomically: true, encoding: .utf8)

    let sessionJSONL = """
    {"timestamp":"2026-04-08T09:00:00Z","type":"session_meta","payload":{"id":"\(sessionId)","cwd":"/Users/me/project","cli_version":"0.78.0"}}
    {"timestamp":"2026-04-08T09:00:01Z","type":"response_item","payload":{"type":"message","role":"user","content":"old prompt"}}
    {"timestamp":"2026-04-08T09:00:02Z","type":"response_item","payload":{"type":"message","role":"assistant","content":"working"}}
    {"timestamp":"2026-04-08T09:00:03Z","type":"response_item","payload":{"type":"message","role":"user","content":"new prompt"}}
    """
    try sessionJSONL.write(to: sessionFile, atomically: true, encoding: .utf8)

    let index = try SessionIndex(dbPath: dbPath)
    let indexer = Indexer(sessionIndex: index, homeDirectoryPath: tempRoot.path)
    indexer.performFullScan()

    let result = try #require(try index.search(query: "", includeHistory: true).first(where: { $0.sessionId == sessionId }))
    #expect(result.title == "new prompt")
}

@MainActor
@Test
func testFullScanPrefersLatestClaudePromptOverFirstPromptMetadata() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("fullscan-claude-prompt-title-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let dbPath = tempRoot.appendingPathComponent("index.sqlite3").path

    let claudeProject = tempRoot
        .appendingPathComponent(".claude", isDirectory: true)
        .appendingPathComponent("projects", isDirectory: true)
        .appendingPathComponent("-Users-me-project", isDirectory: true)
    try fileManager.createDirectory(at: claudeProject, withIntermediateDirectories: true)

    let sessionId = "11111111-1111-1111-1111-111111111111"
    let sessionFile = claudeProject.appendingPathComponent(sessionId).appendingPathExtension("jsonl")
    let sessionsIndexFile = claudeProject.appendingPathComponent("sessions-index.json")

    let sessionsIndexJSON = """
    {
      "entries": [
        {
          "sessionId": "\(sessionId)",
          "firstPrompt": "old prompt",
          "projectPath": "/Users/me/project",
          "created": "2026-04-08T09:00:00Z"
        }
      ]
    }
    """
    try sessionsIndexJSON.write(to: sessionsIndexFile, atomically: true, encoding: .utf8)

    let sessionJSONL = """
    {"timestamp":"2026-04-08T09:00:00Z","type":"user","message":{"content":"old prompt"},"sessionId":"\(sessionId)","cwd":"/Users/me/project"}
    {"timestamp":"2026-04-08T09:00:02Z","type":"assistant","message":{"content":[{"type":"text","text":"working"}]},"sessionId":"\(sessionId)","cwd":"/Users/me/project"}
    {"timestamp":"2026-04-08T09:00:03Z","type":"user","message":{"content":"new prompt"},"sessionId":"\(sessionId)","cwd":"/Users/me/project"}
    """
    try sessionJSONL.write(to: sessionFile, atomically: true, encoding: .utf8)

    let index = try SessionIndex(dbPath: dbPath)
    let indexer = Indexer(sessionIndex: index, homeDirectoryPath: tempRoot.path)
    indexer.performFullScan()

    let result = try #require(try index.search(query: "", includeHistory: true).first(where: { $0.sessionId == sessionId }))
    #expect(result.title == "new prompt")
}
