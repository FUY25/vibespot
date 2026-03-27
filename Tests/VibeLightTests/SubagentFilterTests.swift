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
