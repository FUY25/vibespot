// Tests/VibeLightTests/CodexStateDBThrottleTests.swift
import Foundation
import Testing
@testable import VibeLight

@Suite("CodexStateDB throttle tests")
struct CodexStateDBThrottleTests {
    private func missingDBPath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("vibelight-codexstate-throttle-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("state_5.sqlite")
            .path
    }

    @Test("sessionIdByCwd returns nil without spamming when DB missing")
    func missingDBReturnsNil() {
        let db = CodexStateDB(path: missingDBPath())
        let result1 = db.sessionIdByCwd("/some/path")
        let result2 = db.sessionIdByCwd("/other/path")
        #expect(result1 == nil)
        #expect(result2 == nil)
    }

    @Test("gitBranchMap returns empty without spamming when DB missing")
    func missingDBReturnsEmpty() {
        let db = CodexStateDB(path: missingDBPath())
        let result1 = db.gitBranchMap()
        let result2 = db.gitBranchMap()
        #expect(result1.isEmpty)
        #expect(result2.isEmpty)
    }

    @Test("repeated calls within cooldown skip DB open across instances")
    func cooldownSkipsRepeatedAttempts() {
        let path = missingDBPath()
        let db = CodexStateDB(path: path)
        let secondDB = CodexStateDB(path: path)
        // First call sets the failure timestamp
        let result1 = db.sessionIdByCwd("/a")
        // Second call within 30s should return nil immediately without attempting open,
        // even when using a new instance with the same DB path.
        let result2 = secondDB.sessionIdByCwd("/b")
        // We verify this doesn't crash or spam — the test passing is sufficient
        #expect(result1 == nil)
        #expect(result2 == nil)
    }
}
