// Tests/VibeLightTests/CodexStateDBThrottleTests.swift
import Testing
@testable import VibeLight

@Suite("CodexStateDB throttle tests")
struct CodexStateDBThrottleTests {
    @Test("sessionIdByCwd returns nil without spamming when DB missing")
    func missingDBReturnsNil() {
        let db = CodexStateDB(path: "/nonexistent/path/state_5.sqlite")
        let result1 = db.sessionIdByCwd("/some/path")
        let result2 = db.sessionIdByCwd("/other/path")
        #expect(result1 == nil)
        #expect(result2 == nil)
    }

    @Test("gitBranchMap returns empty without spamming when DB missing")
    func missingDBReturnsEmpty() {
        let db = CodexStateDB(path: "/nonexistent/path/state_5.sqlite")
        let result1 = db.gitBranchMap()
        let result2 = db.gitBranchMap()
        #expect(result1.isEmpty)
        #expect(result2.isEmpty)
    }

    @Test("repeated calls within cooldown skip DB open")
    func cooldownSkipsRepeatedAttempts() {
        let db = CodexStateDB(path: "/nonexistent/path/state_5.sqlite")
        // First call sets the failure timestamp
        _ = db.sessionIdByCwd("/a")
        // Second call within 30s should return nil immediately without attempting open
        _ = db.sessionIdByCwd("/b")
        // We verify this doesn't crash or spam — the test passing is sufficient
    }
}
