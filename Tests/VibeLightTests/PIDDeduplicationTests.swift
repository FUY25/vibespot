// Tests/VibeLightTests/PIDDeduplicationTests.swift
import Testing
import Foundation
@testable import VibeLight

@Suite("PID deduplication tests")
struct PIDDeduplicationTests {
    @Test("deduplicateLiveSessions keeps only newest session per PID")
    func deduplicatesByPID() throws {
        let now = Date()
        let older = now.addingTimeInterval(-60)
        let newest = now.addingTimeInterval(-5)

        let sessions: [(sessionId: String, pid: Int, startedAt: Date)] = [
            ("session-old", 1234, older),
            ("session-new", 1234, newest),
            ("session-other", 5678, now),
        ]

        let staleIDs = Indexer.sessionIDsToCloseByPID(sessions: sessions)

        #expect(staleIDs == ["session-old"])
    }

    @Test("deduplicateLiveSessions returns empty when no shared PIDs")
    func noSharedPIDs() throws {
        let now = Date()
        let sessions: [(sessionId: String, pid: Int, startedAt: Date)] = [
            ("session-a", 111, now),
            ("session-b", 222, now),
        ]

        let staleIDs = Indexer.sessionIDsToCloseByPID(sessions: sessions)

        #expect(staleIDs.isEmpty)
    }

    @Test("deduplicateLiveSessions handles three sessions sharing a PID")
    func threeSessionsSamePID() throws {
        let now = Date()
        let sessions: [(sessionId: String, pid: Int, startedAt: Date)] = [
            ("oldest", 1234, now.addingTimeInterval(-120)),
            ("middle", 1234, now.addingTimeInterval(-60)),
            ("newest", 1234, now),
        ]

        let staleIDs = Indexer.sessionIDsToCloseByPID(sessions: sessions)

        #expect(Set(staleIDs) == Set(["oldest", "middle"]))
    }

    @Test("deduplicateLiveSessions excludes sessions with missing startedAt from closure decisions")
    func missingStartedAtIsExcludedFromDedupDecision() throws {
        let now = Date()
        let aliveSessionsByID: [String: LiveSession] = [
            "known": LiveSession(pid: 1234, sessionId: "known", cwd: "/tmp/a", isAlive: true),
            "unknown": LiveSession(pid: 1234, sessionId: "unknown", cwd: "/tmp/b", isAlive: true),
        ]
        let startedAtBySessionID: [String: Date] = [
            "known": now,
            // "unknown" intentionally missing
        ]

        let tuples = Indexer.dedupTuplesFromAliveSessions(
            aliveSessionsByID: aliveSessionsByID,
            startedAtBySessionID: startedAtBySessionID
        )
        let staleIDs = Indexer.sessionIDsToCloseByPID(sessions: tuples)

        #expect(tuples.count == 1)
        #expect(tuples.first?.sessionId == "known")
        #expect(staleIDs.isEmpty)
    }
}
