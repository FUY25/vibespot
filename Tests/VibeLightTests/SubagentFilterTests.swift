import Foundation
import Testing
@testable import VibeLight

@Test
func testCodexSubagentSessionsAreSkipped() throws {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-subagent-\(UUID().uuidString)")
        .appendingPathExtension("jsonl")
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let jsonl = """
    {"timestamp":"2026-03-22T13:17:39.96871Z","type":"session_meta","payload":{"id":"session-subagent-001","cwd":"/Users/me/project","cli_version":"0.78.0","source":{"subagent":"code-reviewer"}}}
    {"timestamp":"2026-03-22T13:17:40.00000Z","type":"response_item","payload":{"type":"message","role":"user","content":"hello"}}
    """
    try jsonl.write(to: tempURL, atomically: true, encoding: .utf8)

    let (meta, _) = try CodexParser.parseSessionFile(url: tempURL)
    let parsedMeta = try #require(meta)

    #expect(parsedMeta.isSubagent == true)
}

@MainActor
@Test
func testCodexSubagentSessionsDoNotEnterSearchIndex() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("codex-subagent-index-\(UUID().uuidString)", isDirectory: true)
    let dbPath = tempRoot.appendingPathComponent("index.sqlite3").path
    let codexRoot = tempRoot.appendingPathComponent(".codex", isDirectory: true)
    let sessionsDirectory = codexRoot
        .appendingPathComponent("sessions", isDirectory: true)
        .appendingPathComponent("2026", isDirectory: true)
        .appendingPathComponent("03", isDirectory: true)
    let sessionFile = sessionsDirectory.appendingPathComponent("subagent-session.jsonl")
    let sessionIndexFile = codexRoot.appendingPathComponent("session_index.jsonl")

    try fileManager.createDirectory(at: sessionsDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let sessionIndexJSONL = """
    {"id":"subagent-session","thread_name":"Review subagent output","updated_at":"2026-03-22T13:17:39.96871Z"}
    """
    try sessionIndexJSONL.write(to: sessionIndexFile, atomically: true, encoding: .utf8)

    let sessionJSONL = """
    {"timestamp":"2026-03-22T13:17:39.96871Z","type":"session_meta","payload":{"id":"subagent-session","cwd":"/Users/me/project","cli_version":"0.78.0","source":{"subagent":"code-reviewer"}}}
    {"timestamp":"2026-03-22T13:17:40.00000Z","type":"response_item","payload":{"type":"message","role":"user","content":"review this code"}}
    """
    try sessionJSONL.write(to: sessionFile, atomically: true, encoding: .utf8)

    let index = try SessionIndex(dbPath: dbPath)
    let indexer = Indexer(sessionIndex: index, homeDirectoryPath: tempRoot.path)
    indexer.performFullScan()

    let results = try index.search(query: "", includeHistory: true)
    #expect(results.isEmpty)
}
