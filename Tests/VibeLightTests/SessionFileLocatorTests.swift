import Foundation
import Testing
@testable import Flare

private func makeSessionFileLocatorResolution(root: URL) -> SessionSourceResolution {
    SessionSourceResolution(
        claudeRootPath: root.appendingPathComponent(".claude", isDirectory: true).path,
        codexRootPath: root.appendingPathComponent(".codex", isDirectory: true).path,
        claudeProjectsPath: root.appendingPathComponent(".claude/projects", isDirectory: true).path,
        claudeSessionsPath: root.appendingPathComponent(".claude/sessions", isDirectory: true).path,
        codexSessionsPath: root.appendingPathComponent(".codex/sessions", isDirectory: true).path,
        codexStatePath: root.appendingPathComponent(".codex/state_5.sqlite").path,
        autoClaudeAvailable: true,
        autoCodexAvailable: true,
        usingCustomClaude: true,
        usingCustomCodex: true,
        customRequestedButUnavailable: false,
        autoFallbackForClaude: false,
        autoFallbackForCodex: false,
        requestedMode: .custom
    )
}

@Test("locator reuses cached file URLs by session id")
func locatorReusesCachedFileURLsBySessionID() {
    let locator = SessionFileLocator()
    let url = URL(fileURLWithPath: "/tmp/s-1.jsonl")

    locator.record(sessionID: "s-1", fileURL: url)
    let cached = locator.cachedFileURL(sessionID: "s-1")

    #expect(cached == url)
}

@Test("locator finds Claude and Codex session files under the resolved source root")
func locatorFindsClaudeAndCodexSessionFiles() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("session-file-locator-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let resolution = makeSessionFileLocatorResolution(root: tempRoot)
    let locator = SessionFileLocator()

    let claudeProject = tempRoot
        .appendingPathComponent(".claude/projects", isDirectory: true)
        .appendingPathComponent("-Users-me-project", isDirectory: true)
    let codexSessions = tempRoot
        .appendingPathComponent(".codex/sessions", isDirectory: true)
        .appendingPathComponent("2026/04/18", isDirectory: true)

    try fileManager.createDirectory(at: claudeProject, withIntermediateDirectories: true, attributes: nil)
    try fileManager.createDirectory(at: codexSessions, withIntermediateDirectories: true, attributes: nil)

    let claudeSessionID = "11111111-1111-1111-1111-111111111111"
    let codexSessionID = "22222222-2222-2222-2222-222222222222"

    let claudeFile = claudeProject
        .appendingPathComponent(claudeSessionID)
        .appendingPathExtension("jsonl")
    let codexFile = codexSessions
        .appendingPathComponent("rollout-preview-\(codexSessionID)")
        .appendingPathExtension("jsonl")

    try "".write(to: claudeFile, atomically: true, encoding: .utf8)
    try "".write(to: codexFile, atomically: true, encoding: .utf8)

    let locatedClaude = locator.fileURL(sessionID: claudeSessionID, sourceResolution: resolution)
    let locatedCodex = locator.fileURL(sessionID: codexSessionID, sourceResolution: resolution)

    #expect(locatedClaude?.standardizedFileURL == claudeFile.standardizedFileURL)
    #expect(locatedCodex?.standardizedFileURL == codexFile.standardizedFileURL)
}
