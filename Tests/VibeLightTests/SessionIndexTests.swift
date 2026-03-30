import Foundation
import SQLite3
import Testing
@testable import Flare

@Test
func testInsertAndSearchSession() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)

    try index.upsertSession(
        id: "abc-123",
        tool: "claude",
        title: "fix auth bug",
        project: "/Users/me/terminalrail",
        projectName: "terminalrail",
        gitBranch: "feat/auth",
        status: "live",
        startedAt: Date(),
        pid: 12345
    )

    try index.insertTranscript(
        sessionId: "abc-123",
        role: "user",
        content: "the JWT token expires because refreshToken was never persisted",
        timestamp: Date()
    )

    let results = try index.search(query: "JWT token", includeHistory: false)
    #expect(results.count == 1)
    #expect(results[0].sessionId == "abc-123")
    #expect(results[0].snippet?.contains("token") == true)
}

@Test
func testSearchMetadataOnly() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)

    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "fix auth bug",
        project: "/p",
        projectName: "myproject",
        gitBranch: "main",
        status: "live",
        startedAt: Date(),
        pid: 111
    )
    try index.upsertSession(
        id: "s2",
        tool: "codex",
        title: "write API tests",
        project: "/p",
        projectName: "myproject",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(),
        pid: nil
    )

    let live = try index.search(query: "myproject", includeHistory: false)
    #expect(live.count == 1)
    #expect(live[0].sessionId == "s1")

    let all = try index.search(query: "myproject", includeHistory: true)
    #expect(all.count == 2)
}

@Test
func testTranscriptSearchDeduplicatesSessionsBeforeLimit() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    let now = Date()

    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "session one",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: now,
        pid: 1
    )
    try index.upsertSession(
        id: "s2",
        tool: "codex",
        title: "session two",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: now.addingTimeInterval(-1),
        pid: 2
    )

    for indexValue in 0..<60 {
        try index.insertTranscript(
            sessionId: "s1",
            role: "user",
            content: "needle phrase repeated \(indexValue)",
            timestamp: now.addingTimeInterval(TimeInterval(indexValue))
        )
    }

    try index.insertTranscript(
        sessionId: "s2",
        role: "assistant",
        content: "needle phrase appears once here",
        timestamp: now
    )

    let results = try index.search(query: "needle phrase", includeHistory: false)

    #expect(Set(results.map(\.sessionId)) == ["s1", "s2"])
}

@Test
func testTranscriptSearchIgnoresRoleAndSessionIDMatchesWithoutContentMatch() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    try index.upsertSession(
        id: "session-needle-123",
        tool: "claude",
        title: "transcript decoy",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: now,
        pid: 11
    )

    try index.insertTranscript(
        sessionId: "session-needle-123",
        role: "assistant",
        content: "completely unrelated transcript content",
        timestamp: now
    )

    #expect(try index.search(query: "assistant", includeHistory: true).isEmpty)
    #expect(try index.search(query: "needle", includeHistory: true).isEmpty)
}

@Test
func testTranscriptMatchesStillSurfaceWhenMetadataAlreadyHasFiftyHits() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    for offset in 0..<50 {
        try index.upsertSession(
            id: "metadata-\(offset)",
            tool: "claude",
            title: "needle metadata \(offset)",
            project: "/p",
            projectName: "proj",
            gitBranch: "main",
            status: "live",
            startedAt: now.addingTimeInterval(TimeInterval(-offset)),
            pid: nil
        )
    }

    try index.upsertSession(
        id: "transcript-only",
        tool: "codex",
        title: "content match only",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: now.addingTimeInterval(60),
        pid: nil
    )
    try index.insertTranscript(
        sessionId: "transcript-only",
        role: "user",
        content: "needle appears only inside transcript content",
        timestamp: now
    )

    let results = try index.search(query: "needle", includeHistory: true)
    let sessionIDs = results.map(\.sessionId)

    #expect(results.count == 50)
    #expect(sessionIDs.contains("transcript-only"))
    #expect(sessionIDs.filter { $0.hasPrefix("metadata-") }.count == 49)
}

@Test
func testReplacingTranscriptContentTwiceDoesNotDuplicateTranscriptRows() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "idempotent transcript indexing",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: now,
        pid: 101
    )

    let entries: [(role: String, content: String, timestamp: Date)] = [
        ("user", "first transcript line", now),
        ("assistant", "second transcript line", now.addingTimeInterval(1)),
    ]

    try index.replaceTranscripts(sessionId: "s1", entries: entries)
    try index.replaceTranscripts(sessionId: "s1", entries: entries)

    #expect(try transcriptRowCount(dbPath: dbPath, sessionId: "s1") == 2)
}

@Test
func testReplaceTranscriptsRollsBackWhenReplacementFails() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "transactional transcript replacement",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: now,
        pid: 202
    )

    let originalEntries: [(role: String, content: String, timestamp: Date)] = [
        ("user", "keep this original transcript entry", now),
        ("assistant", "keep this reply too", now.addingTimeInterval(1)),
    ]
    try index.replaceTranscripts(sessionId: "s1", entries: originalEntries)

    let handle = try databaseHandle(for: index)
    let previousLengthLimit = sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, 64)

    let failingEntries: [(role: String, content: String, timestamp: Date)] = [
        (
            "user",
            String(repeating: "replacement that should fail ", count: 8),
            now.addingTimeInterval(2)
        ),
    ]

    do {
        try index.replaceTranscripts(sessionId: "s1", entries: failingEntries)
        Issue.record("Expected transcript replacement to fail when SQLite rejects oversized content.")
    } catch {
    }
    sqlite3_limit(handle, SQLITE_LIMIT_LENGTH, previousLengthLimit)

    #expect(
        try transcriptContents(dbPath: dbPath, sessionId: "s1") == originalEntries.map(\.content)
    )
    #expect(
        try index.search(query: "original transcript entry", includeHistory: true).map(\.sessionId) == ["s1"]
    )
}

@Test
func testLiveSessionCount() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "a",
        project: "/p",
        projectName: "p",
        gitBranch: "",
        status: "live",
        startedAt: Date(),
        pid: 1
    )
    try index.upsertSession(
        id: "s2",
        tool: "codex",
        title: "b",
        project: "/p",
        projectName: "p",
        gitBranch: "",
        status: "live",
        startedAt: Date(),
        pid: 2
    )
    try index.upsertSession(
        id: "s3",
        tool: "claude",
        title: "c",
        project: "/p",
        projectName: "p",
        gitBranch: "",
        status: "closed",
        startedAt: Date(),
        pid: nil
    )
    #expect(try index.liveSessionCount() == 2)
}

@Test
func testMostRecentProjectReturnsLatestSessionProjectAndProjectName() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try index.upsertSession(
        id: "older",
        tool: "claude",
        title: "older project",
        project: "/Users/me/older",
        projectName: "older",
        gitBranch: "main",
        status: "closed",
        startedAt: now.addingTimeInterval(-120),
        pid: nil,
        lastActivityAt: now.addingTimeInterval(-120)
    )
    try index.upsertSession(
        id: "latest",
        tool: "codex",
        title: "latest project",
        project: "/Users/me/latest",
        projectName: "latest",
        gitBranch: "main",
        status: "live",
        startedAt: now,
        pid: 1,
        lastActivityAt: now
    )

    let mostRecent = try index.mostRecentProject()
    #expect(mostRecent?.project == "/Users/me/latest")
    #expect(mostRecent?.projectName == "latest")
}

@Test
func testMostRecentProjectReturnsNilWhenEmpty() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    #expect(try index.mostRecentProject() == nil)
}

@Test
func testMostRecentProjectReturnsNewestRowEvenWhenProjectNameIsEmpty() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try index.upsertSession(
        id: "named-project",
        tool: "claude",
        title: "named",
        project: "/Users/me/named",
        projectName: "named",
        gitBranch: "main",
        status: "closed",
        startedAt: now.addingTimeInterval(-120),
        pid: nil,
        lastActivityAt: now.addingTimeInterval(-120)
    )
    try index.upsertSession(
        id: "empty-name",
        tool: "codex",
        title: "empty project name",
        project: "/Users/me/empty",
        projectName: "",
        gitBranch: "main",
        status: "closed",
        startedAt: now,
        pid: nil,
        lastActivityAt: now
    )

    let mostRecent = try index.mostRecentProject()
    #expect(mostRecent?.project == "/Users/me/empty")
    #expect(mostRecent?.projectName == "")
}

@Test
func testMostRecentProjectUsesStartedAtWhenLastActivityIsNil() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try index.upsertSession(
        id: "older-nil-last-activity",
        tool: "claude",
        title: "older",
        project: "/Users/me/older-fallback",
        projectName: "older-fallback",
        gitBranch: "main",
        status: "closed",
        startedAt: now.addingTimeInterval(-120),
        pid: nil,
        lastActivityAt: nil
    )
    try index.upsertSession(
        id: "newer-nil-last-activity",
        tool: "codex",
        title: "newer",
        project: "/Users/me/newer-fallback",
        projectName: "newer-fallback",
        gitBranch: "main",
        status: "closed",
        startedAt: now,
        pid: nil,
        lastActivityAt: nil
    )

    let mostRecent = try index.mostRecentProject()
    #expect(mostRecent?.project == "/Users/me/newer-fallback")
    #expect(mostRecent?.projectName == "newer-fallback")
}

@Test
func testEmptyQueryListsSessionsRespectingHistoryMode() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)

    try index.upsertSession(
        id: "live",
        tool: "claude",
        title: "active work",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: Date(),
        pid: 42
    )
    try index.upsertSession(
        id: "closed",
        tool: "codex",
        title: "finished work",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(),
        pid: nil
    )

    let liveOnly = try index.search(query: "   ", includeHistory: false)
    #expect(liveOnly.map(\.sessionId) == ["live"])

    let all = try index.search(query: "", includeHistory: true)
    #expect(Set(all.map(\.sessionId)) == ["live", "closed"])
}

@Test
func testUpdateStatusChangesLiveQueriesAndCounts() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)

    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "fix auth bug",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: Date(),
        pid: 7
    )

    #expect(try index.liveSessionCount() == 1)
    #expect(try index.search(query: "", includeHistory: false).map(\.sessionId) == ["s1"])

    try index.updateStatus(sessionId: "s1", status: "closed")

    #expect(try index.liveSessionCount() == 0)
    #expect(try index.search(query: "", includeHistory: false).isEmpty)
    #expect(try index.search(query: "", includeHistory: true).map(\.status) == ["closed"])
}

@Test
func testUpdateRuntimeStatePersistsPIDForLiveResults() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    let startedAt = Date(timeIntervalSince1970: 1_774_505_680)

    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "jump target",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "closed",
        startedAt: startedAt,
        pid: nil
    )

    try index.updateRuntimeState(sessionId: "s1", status: "live", pid: 72611)

    let liveResults = try index.search(query: "", includeHistory: false)
    #expect(liveResults.map(\.sessionId) == ["s1"])
    #expect(liveResults.first?.status == "live")
    #expect(liveResults.first?.pid == 72611)

    try index.updateRuntimeState(sessionId: "s1", status: "closed", pid: nil)

    let allResults = try index.search(query: "", includeHistory: true)
    #expect(allResults.map(\.sessionId) == ["s1"])
    #expect(allResults.first?.status == "closed")
    #expect(allResults.first?.pid == nil)
}

@Test
func testMigrationAddsHealthFieldsForLegacySchema() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_legacy_health.sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try createLegacySessionsTable(at: dbPath)
    try insertLegacySessionRow(
        dbPath: dbPath,
        id: "legacy-session",
        tool: "claude",
        title: "legacy schema session",
        project: "/legacy/project",
        projectName: "legacy",
        gitBranch: "main",
        status: "live",
        startedAt: Date(),
        pid: nil
    )

    let index = try SessionIndex(dbPath: dbPath)

    let metadataResults = try index.search(query: "legacy schema", includeHistory: true)
    #expect(metadataResults.count == 1)
    #expect(metadataResults[0].sessionId == "legacy-session")
    #expect(metadataResults[0].healthStatus == "ok")
    #expect(metadataResults[0].healthDetail == "")
    #expect(metadataResults[0].effectiveModel == nil)
    #expect(metadataResults[0].contextWindowTokens == nil)
    #expect(metadataResults[0].contextUsedEstimate == nil)
    #expect(metadataResults[0].contextPercentEstimate == nil)
    #expect(metadataResults[0].contextConfidence == .unknown)
    #expect(metadataResults[0].contextSource == nil)
    #expect(metadataResults[0].lastContextSampleAt == nil)

    let listResults = try index.search(query: "", includeHistory: true)
    #expect(listResults.count == 1)
    #expect(listResults[0].sessionId == "legacy-session")
    #expect(listResults[0].healthStatus == "ok")
    #expect(listResults[0].healthDetail == "")
    #expect(listResults[0].effectiveModel == nil)
    #expect(listResults[0].contextWindowTokens == nil)
    #expect(listResults[0].contextUsedEstimate == nil)
    #expect(listResults[0].contextPercentEstimate == nil)
    #expect(listResults[0].contextConfidence == .unknown)
    #expect(listResults[0].contextSource == nil)
    #expect(listResults[0].lastContextSampleAt == nil)

    let columns = try sessionTableColumnNames(dbPath: dbPath)
    #expect(columns.contains("effective_model"))
    #expect(columns.contains("context_window_tokens"))
    #expect(columns.contains("context_used_estimate"))
    #expect(columns.contains("context_percent_estimate"))
    #expect(columns.contains("context_confidence"))
    #expect(columns.contains("context_source"))
    #expect(columns.contains("last_context_sample_at"))
}

@Test
func testHealthStatusDefaultsToOk() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try index.upsertSession(
        id: "s-health-default",
        tool: "claude",
        title: "test health default",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: Date(),
        pid: 77
    )

    let results = try index.search(query: "test", includeHistory: true)
    #expect(results.count == 1)
    #expect(results[0].healthStatus == "ok")
    #expect(results[0].healthDetail == "")
}

@Test
func testTranscriptSearchReturnsEffectiveModelAndContextTelemetry() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    let now = Date()

    try index.upsertSession(
        id: "ctx-1",
        tool: "codex",
        title: "context telemetry test",
        project: "/Users/me/project",
        projectName: "project",
        gitBranch: "feat/ctx",
        status: "live",
        startedAt: now,
        pid: 123,
        tokenCount: 41000,
        lastActivityAt: now,
        telemetry: SessionContextTelemetry(
            effectiveModel: "gpt-5.2-codex",
            contextWindowTokens: 258400,
            contextUsedEstimate: 43027,
            contextPercentEstimate: 16,
            contextConfidence: .high,
            contextSource: "codex:last_token_usage",
            lastContextSampleAt: now
        )
    )

    try index.insertTranscript(
        sessionId: "ctx-1",
        role: "assistant",
        content: "transcript-only needle for telemetry search coverage",
        timestamp: now
    )

    let results = try index.search(query: "transcript-only needle", includeHistory: true)
    let result = try #require(results.first)

    #expect(result.effectiveModel == "gpt-5.2-codex")
    #expect(result.contextWindowTokens == 258400)
    #expect(result.contextUsedEstimate == 43027)
    #expect(result.contextPercentEstimate == 16)
    #expect(result.contextConfidence == .high)
    #expect(result.contextSource == "codex:last_token_usage")
    let lastContextSampleAt = try #require(result.lastContextSampleAt)
    #expect(abs(lastContextSampleAt.timeIntervalSince1970 - now.timeIntervalSince1970) < 0.001)
}

@Test
func testUpdateHealthStatus() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try index.upsertSession(
        id: "s-health-update",
        tool: "claude",
        title: "test health update",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: Date(),
        pid: 88
    )

    try index.updateHealthStatus(
        sessionId: "s-health-update",
        healthStatus: "error",
        healthDetail: "API 400: model unavailable"
    )

    let results = try index.search(query: "test", includeHistory: true)
    #expect(results.count == 1)
    #expect(results[0].healthStatus == "error")
    #expect(results[0].healthDetail == "API 400: model unavailable")
}

@Test
func testTranscriptMatchesFromClosedSessionsAreExcludedWhenHistoryDisabled() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    try index.upsertSession(
        id: "closed-hit",
        tool: "claude",
        title: "archived work",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "closed",
        startedAt: now,
        pid: nil
    )
    try index.insertTranscript(
        sessionId: "closed-hit",
        role: "user",
        content: "history only transcript needle",
        timestamp: now
    )

    try index.upsertSession(
        id: "live-decoy",
        tool: "codex",
        title: "active work",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: now.addingTimeInterval(1),
        pid: 7
    )
    try index.insertTranscript(
        sessionId: "live-decoy",
        role: "assistant",
        content: "completely unrelated active transcript",
        timestamp: now.addingTimeInterval(1)
    )

    #expect(
        try index.search(query: "history only transcript needle", includeHistory: true).map(\.sessionId)
            == ["closed-hit"]
    )
    #expect(
        try index.search(query: "history only transcript needle", includeHistory: false).isEmpty
    )
}

@Test
func testHistoryTranscriptSearchOrdersLiveSessionsAheadOfClosedSessions() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    try index.upsertSession(
        id: "live-hit",
        tool: "claude",
        title: "active work",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: now.addingTimeInterval(-60),
        pid: 17
    )
    try index.insertTranscript(
        sessionId: "live-hit",
        role: "assistant",
        content: "needle ranking appears once in the active transcript",
        timestamp: now.addingTimeInterval(-60)
    )

    try index.upsertSession(
        id: "closed-hit",
        tool: "codex",
        title: "archived work",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "closed",
        startedAt: now,
        pid: nil
    )
    try index.insertTranscript(
        sessionId: "closed-hit",
        role: "assistant",
        content: "needle ranking needle ranking needle ranking in the archived transcript",
        timestamp: now
    )

    let results = try index.search(query: "needle ranking", includeHistory: true)

    #expect(results.map(\.sessionId) == ["live-hit", "closed-hit"])
    #expect(results.map(\.status) == ["live", "closed"])
}

@Test
func testTranscriptSearchBreaksEqualSessionRanksByNewestMatchingTranscript() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    try index.upsertSession(
        id: "tie-session",
        tool: "claude",
        title: "tie breaker session",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: now,
        pid: nil
    )
    try index.insertTranscript(
        sessionId: "tie-session",
        role: "assistant",
        content: "needle newer result",
        timestamp: now.addingTimeInterval(1)
    )
    try index.insertTranscript(
        sessionId: "tie-session",
        role: "assistant",
        content: "needle older result",
        timestamp: now
    )

    let results = try index.search(query: "needle", includeHistory: true)

    #expect(results.map(\.sessionId) == ["tie-session"])
    #expect(results[0].snippet?.contains("newer") == true)
}

@Test
func testTranscriptSearchBreaksEqualSessionRanksByNewestSession() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let base = Date(timeIntervalSince1970: 1_700_000_000)
    let sharedTranscriptTimestamp = base.addingTimeInterval(0.5)
    try index.upsertSession(
        id: "newer-session",
        tool: "codex",
        title: "newer session",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: base.addingTimeInterval(0.75),
        pid: nil
    )
    try index.insertTranscript(
        sessionId: "newer-session",
        role: "assistant",
        content: "needle shared rank",
        timestamp: sharedTranscriptTimestamp
    )

    try index.upsertSession(
        id: "older-session",
        tool: "claude",
        title: "older session",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: base.addingTimeInterval(0.25),
        pid: nil
    )
    try index.insertTranscript(
        sessionId: "older-session",
        role: "assistant",
        content: "needle shared rank",
        timestamp: sharedTranscriptTimestamp
    )

    let results = try index.search(query: "needle", includeHistory: true)

    #expect(results.map(\.sessionId) == ["newer-session", "older-session"])
}

@Test
func testSearchMetadataQueriesWithFTSUnsafeShapes() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    let sessions: [(id: String, title: String, project: String, projectName: String, gitBranch: String)] = [
        ("slash", "auth work", "/repo/app", "terminalrail", "feat/auth"),
        ("dash", "branch cleanup", "/repo/app", "terminalrail", "fix-auth"),
        ("path", "swift file touch", "/repo/src/App.swift", "terminalrail", "main"),
        ("underscore", "search branch", "/repo/app", "terminalrail", "feature_search"),
        ("underscore-decoy", "search branch", "/repo/app", "terminalrail", "featureXsearch"),
        ("punctuation", "review: api", "/repo/app", "terminalrail", "main"),
    ]

    for session in sessions {
        try index.upsertSession(
            id: session.id,
            tool: "claude",
            title: session.title,
            project: session.project,
            projectName: session.projectName,
            gitBranch: session.gitBranch,
            status: "live",
            startedAt: now,
            pid: nil
        )
    }

    let cases: [(query: String, expectedIDs: Set<String>)] = [
        ("feat/auth", ["slash"]),
        ("fix-auth", ["dash"]),
        ("src/App.swift", ["path"]),
        ("feature_search", ["underscore"]),
        (":", ["punctuation"]),
    ]

    for queryCase in cases {
        let results = try index.search(query: queryCase.query, includeHistory: true)
        #expect(
            Set(results.map(\.sessionId)) == queryCase.expectedIDs,
            "query=\(queryCase.query) results=\(results.map(\.sessionId))"
        )
    }
}

@Test
func testPunctuationHeavyMetadataQuerySkipsTranscriptFTSFalsePositives() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    try index.upsertSession(
        id: "path-hit",
        tool: "claude",
        title: "path lookup",
        project: "/repo/src/App.swift",
        projectName: "terminalrail",
        gitBranch: "feature/src/App.swift",
        status: "live",
        startedAt: now.addingTimeInterval(120),
        pid: nil
    )

    for offset in 0..<60 {
        let sessionID = "transcript-decoy-\(offset)"
        try index.upsertSession(
            id: sessionID,
            tool: "codex",
            title: "decoy \(offset)",
            project: "/repo/other",
            projectName: "terminalrail",
            gitBranch: "main",
            status: "live",
            startedAt: now.addingTimeInterval(TimeInterval(-offset)),
            pid: nil
        )
        try index.insertTranscript(
            sessionId: sessionID,
            role: "assistant",
            content: "Discussed src App swift refactor number \(offset)",
            timestamp: now.addingTimeInterval(TimeInterval(offset))
        )
    }

    let results = try index.search(query: "src/App.swift", includeHistory: true)

    #expect(results.map(\.sessionId) == ["path-hit"])
    #expect(results[0].snippet == nil)
}

@Test
func testPunctuationHeavyTranscriptQueryFallsBackToLiteralContentSearch() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    try index.upsertSession(
        id: "transcript-path-hit",
        tool: "claude",
        title: "content-only hit",
        project: "/repo/other",
        projectName: "terminalrail",
        gitBranch: "main",
        status: "live",
        startedAt: now,
        pid: nil
    )
    try index.insertTranscript(
        sessionId: "transcript-path-hit",
        role: "assistant",
        content: "Touched src/App.swift while tracing the renderer issue.",
        timestamp: now
    )

    let results = try index.search(query: "src/App.swift", includeHistory: true)

    #expect(results.map(\.sessionId) == ["transcript-path-hit"])
}

@Test
func testPunctuationOnlyTranscriptQueryFallsBackToLiteralContentSearch() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    try index.upsertSession(
        id: "transcript-punctuation-hit",
        tool: "claude",
        title: "content only punctuation hit",
        project: "/repo/other",
        projectName: "terminalrail",
        gitBranch: "main",
        status: "live",
        startedAt: now,
        pid: nil
    )
    try index.insertTranscript(
        sessionId: "transcript-punctuation-hit",
        role: "assistant",
        content: "The parser maps tokens -> AST nodes before rendering.",
        timestamp: now
    )

    let results = try index.search(query: "->", includeHistory: true)

    #expect(results.map(\.sessionId) == ["transcript-punctuation-hit"])
}

@Test
func testPunctuationHeavyTranscriptFallbackIgnoresRoleAndSessionIDMatchesWithoutContentMatch() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    try index.upsertSession(
        id: "session-feature_search-123",
        tool: "claude",
        title: "decoy",
        project: "/repo/other",
        projectName: "terminalrail",
        gitBranch: "main",
        status: "live",
        startedAt: now,
        pid: nil
    )
    try index.insertTranscript(
        sessionId: "session-feature_search-123",
        role: "assistant",
        content: "completely unrelated transcript content",
        timestamp: now
    )

    let results = try index.search(query: "feature_search", includeHistory: true)

    #expect(results.isEmpty)
}

@Test
func testSearchMetadataTreatsLikeWildcardsLiterally() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    let sessions: [(id: String, title: String, project: String)] = [
        ("percent", "progress 100% done", "/repo/app"),
        ("percent-decoy", "progress 100x done", "/repo/app"),
        ("backslash", "windows path", #"C:\repo\app"#),
        ("backslash-decoy", "unix path", "C:/repo/app"),
    ]

    for session in sessions {
        try index.upsertSession(
            id: session.id,
            tool: "claude",
            title: session.title,
            project: session.project,
            projectName: "terminalrail",
            gitBranch: "main",
            status: "live",
            startedAt: now,
            pid: nil
        )
    }

    let percentResults = try index.search(query: "100%", includeHistory: true)
    #expect(Set(percentResults.map(\.sessionId)) == ["percent"])

    let backslashResults = try index.search(query: #"C:\repo"#, includeHistory: true)
    #expect(Set(backslashResults.map(\.sessionId)) == ["backslash"])
}

@Test
func testUpsertSessionStoresLastIndexedMtime() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let mtime = Date(timeIntervalSince1970: 1_700_000_000)
    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "mtime test",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(),
        pid: nil,
        lastIndexedMtime: mtime
    )

    let storedMtime = try index.lastIndexedMtime(sessionId: "s1")
    #expect(storedMtime == mtime)
}

@Test
func testIndexerSkipsFileWhenMtimeUnchanged() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let mtime = Date(timeIntervalSince1970: 1_700_000_000)

    // Simulate a session that was already indexed with this mtime
    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "original title",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(),
        pid: nil,
        lastIndexedMtime: mtime
    )

    // Verify the stored mtime matches
    let stored = try index.lastIndexedMtime(sessionId: "s1")
    #expect(stored == mtime)

    // A second upsert with the same mtime should preserve the stored value
    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "same mtime title",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(),
        pid: nil,
        lastIndexedMtime: mtime
    )

    let unchangedMtime = try index.lastIndexedMtime(sessionId: "s1")
    #expect(unchangedMtime == mtime)

    // A third upsert with a newer mtime should update
    let newerMtime = Date(timeIntervalSince1970: 1_700_001_000)
    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "updated title",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(),
        pid: nil,
        lastIndexedMtime: newerMtime
    )

    let updatedMtime = try index.lastIndexedMtime(sessionId: "s1")
    #expect(updatedMtime == newerMtime)
}

@Test
func testLastIndexedMtimeReturnsNilForUnknownSession() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    #expect(try index.lastIndexedMtime(sessionId: "nonexistent") == nil)
}

@Test
func testUpsertSessionPreservesLastIndexedMtimeWhenArgumentOmitted() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let originalMtime = Date(timeIntervalSince1970: 1_700_000_100)
    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "initial mtime",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(),
        pid: nil,
        lastIndexedMtime: originalMtime
    )

    try index.upsertSession(
        id: "s1",
        tool: "claude",
        title: "updated title without mtime",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(),
        pid: nil
    )

    #expect(try index.lastIndexedMtime(sessionId: "s1") == originalMtime)
}

@Test
func testUpsertSessionPreservesTelemetryWhenArgumentsAreOmitted() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date(timeIntervalSince1970: 1_700_000_000)
    try index.upsertSession(
        id: "s-telemetry",
        tool: "codex",
        title: "telemetry baseline",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: now,
        pid: 1,
        telemetry: SessionContextTelemetry(
            effectiveModel: "gpt-5.2-codex",
            contextWindowTokens: 200_000,
            contextUsedEstimate: 12_345,
            contextPercentEstimate: 6,
            contextConfidence: .high,
            contextSource: "codex:last_token_usage",
            lastContextSampleAt: now
        )
    )

    try index.upsertSession(
        id: "s-telemetry",
        tool: "codex",
        title: "telemetry baseline updated title",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: now.addingTimeInterval(30),
        pid: 2
    )

    let result = try #require(try index.search(query: "baseline updated", includeHistory: true).first)
    #expect(result.effectiveModel == "gpt-5.2-codex")
    #expect(result.contextWindowTokens == 200_000)
    #expect(result.contextUsedEstimate == 12_345)
    #expect(result.contextPercentEstimate == 6)
    #expect(result.contextConfidence == .high)
    #expect(result.contextSource == "codex:last_token_usage")
    let lastContextSampleAt = try #require(result.lastContextSampleAt)
    #expect(abs(lastContextSampleAt.timeIntervalSince1970 - now.timeIntervalSince1970) < 0.001)
}

@Test
func testUpsertSessionTreatsTelemetryAsSingleSnapshot() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let originalSampleAt = Date(timeIntervalSince1970: 1_700_000_000)
    let updatedSampleAt = originalSampleAt.addingTimeInterval(60)

    try index.upsertSession(
        id: "s-snapshot",
        tool: "codex",
        title: "telemetry snapshot",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: originalSampleAt,
        pid: 1,
        telemetry: SessionContextTelemetry(
            effectiveModel: "gpt-5.2-codex",
            contextWindowTokens: 200_000,
            contextUsedEstimate: 12_345,
            contextPercentEstimate: 6,
            contextConfidence: .high,
            contextSource: "codex:last_token_usage",
            lastContextSampleAt: originalSampleAt
        )
    )

    try index.upsertSession(
        id: "s-snapshot",
        tool: "codex",
        title: "telemetry snapshot",
        project: "/p",
        projectName: "proj",
        gitBranch: "main",
        status: "live",
        startedAt: updatedSampleAt,
        pid: 2,
        telemetry: SessionContextTelemetry(
            effectiveModel: "gpt-5.2-mini",
            contextWindowTokens: nil,
            contextUsedEstimate: 54_321,
            contextPercentEstimate: nil,
            contextConfidence: .low,
            contextSource: nil,
            lastContextSampleAt: updatedSampleAt
        )
    )

    let result = try #require(try index.search(query: "telemetry snapshot", includeHistory: true).first)
    #expect(result.effectiveModel == "gpt-5.2-mini")
    #expect(result.contextWindowTokens == nil)
    #expect(result.contextUsedEstimate == 54_321)
    #expect(result.contextPercentEstimate == nil)
    #expect(result.contextConfidence == .low)
    #expect(result.contextSource == nil)
    let lastContextSampleAt = try #require(result.lastContextSampleAt)
    #expect(abs(lastContextSampleAt.timeIntervalSince1970 - updatedSampleAt.timeIntervalSince1970) < 0.001)
}

@Test
func testUpdateTelemetryPreservesSessionMetadata() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let startedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let sampledAt = startedAt.addingTimeInterval(60)
    let indexedMtime = startedAt.addingTimeInterval(120)

    try index.upsertSession(
        id: "s-telemetry-only",
        tool: "claude",
        title: "Existing title",
        project: "/Users/me/project",
        projectName: "project",
        gitBranch: "feat/ctx",
        status: "closed",
        startedAt: startedAt,
        pid: nil,
        lastActivityAt: startedAt
    )

    try index.updateTelemetry(
        sessionId: "s-telemetry-only",
        telemetry: SessionContextTelemetry(
            effectiveModel: "claude-opus-4-6",
            contextWindowTokens: 1_000_000,
            contextUsedEstimate: 240_000,
            contextPercentEstimate: 24,
            contextConfidence: .low,
            contextSource: "claude:assistant_usage",
            lastContextSampleAt: sampledAt
        ),
        lastIndexedMtime: indexedMtime
    )

    let result = try #require(try index.search(query: "Existing title", includeHistory: true).first)
    #expect(result.title == "Existing title")
    #expect(result.project == "/Users/me/project")
    #expect(result.projectName == "project")
    #expect(result.gitBranch == "feat/ctx")
    #expect(result.startedAt == startedAt)
    #expect(result.effectiveModel == "claude-opus-4-6")
    #expect(result.contextWindowTokens == 1_000_000)
    #expect(result.contextUsedEstimate == 240_000)
    #expect(result.contextPercentEstimate == 24)
    #expect(result.contextConfidence == .low)
    #expect(result.contextSource == "claude:assistant_usage")
    let lastContextSampleAt = try #require(result.lastContextSampleAt)
    #expect(abs(lastContextSampleAt.timeIntervalSince1970 - sampledAt.timeIntervalSince1970) < 0.001)
    #expect(try index.lastIndexedMtime(sessionId: "s-telemetry-only") == indexedMtime)
}

@Test
func testStripANSI() {
    let raw = "\u{001b}[1;31mHello\u{001b}[0m world"
    #expect(SessionIndex.stripANSI(raw) == "Hello world")
}

@Test
func testStripANSINoEscapes() {
    let raw = "Hello [1;31m world"
    #expect(SessionIndex.stripANSI(raw) == raw)
}

@Test
func testSmartTruncateShortText() {
    #expect(SessionIndex.smartTruncate("  hi there \n") == "hi there")
}

@Test
func testSmartTruncateLongText() {
    let raw = String(repeating: "word ", count: 20)
    let expected = Array(repeating: "word", count: 12).joined(separator: " ") + "…"
    #expect(SessionIndex.smartTruncate(raw) == expected)
}

@Test
func testSmartTruncatePreservesQuestion() {
    // Use a multi-word question with a long final word so truncation must not cut mid-word.
    // Prior behavior would include a partial "supercalifragilisticexpialidocious" fragment.
    let raw = "How do we truncate this title without cutting supercalifragilisticexpialidocious?"
    let expected = "How do we truncate this title without cutting…?"
    let truncated = SessionIndex.smartTruncate(raw)
    #expect(truncated == expected)
    #expect(truncated.hasSuffix("…?"))
    #expect(!truncated.contains("super"))
    #expect(truncated.count <= 61)
}

@Test
func testCleanTitleCombined() {
    let raw = "\u{001b}[32m" + String(repeating: "word ", count: 20) + "\u{001b}[0m"
    let cleaned = SessionIndex.cleanTitle(raw)
    let expected = Array(repeating: "word", count: 12).joined(separator: " ") + "…"
    #expect(cleaned == expected)
    #expect(!cleaned.contains("\u{001b}"))
    #expect(cleaned.count <= 61)
}

@Test
func testUpsertSessionCleansTitleBeforeStorage() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let raw =
        "\u{001b}[1;31mHow do we truncate this title without cutting supercalifragilisticexpialidocious?\u{001b}[0m"
    let expected = "How do we truncate this title without cutting…?"

    try index.upsertSession(
        id: "t1",
        tool: "codex",
        title: raw,
        project: "/p",
        projectName: "p",
        gitBranch: "main",
        status: "closed",
        startedAt: Date(),
        pid: nil
    )

    let results = try index.search(query: "", includeHistory: true)
    #expect(results.count == 1)
    #expect(results[0].title == expected)
    #expect(!results[0].title.contains("\u{001b}"))
    #expect(results[0].title.count <= 61)
}

private func makeTestIndex() throws -> (SessionIndex, String) {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    return (try SessionIndex(dbPath: dbPath), dbPath)
}

private func createLegacySessionsTable(at dbPath: String) throws {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(dbPath, &connection, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
        defer { sqlite3_close(connection) }
        throw TestDatabaseError.openFailed
    }
    defer { sqlite3_close(connection) }

    let sql = """
        CREATE TABLE sessions (
            id TEXT PRIMARY KEY,
            tool TEXT NOT NULL,
            title TEXT NOT NULL,
            project TEXT NOT NULL,
            project_name TEXT NOT NULL,
            git_branch TEXT NOT NULL DEFAULT '',
            status TEXT NOT NULL DEFAULT 'closed',
            started_at REAL NOT NULL,
            pid INTEGER,
            token_count INTEGER NOT NULL DEFAULT 0,
            last_activity_at REAL,
            last_file_mod REAL,
            last_entry_type TEXT,
            activity_preview TEXT,
            activity_preview_kind TEXT,
            updated_at REAL NOT NULL DEFAULT 0,
            last_indexed_mtime REAL
        )
        """

    guard sqlite3_exec(connection, sql, nil, nil, nil) == SQLITE_OK else {
        throw TestDatabaseError.stepFailed
    }
}

private func insertLegacySessionRow(
    dbPath: String,
    id: String,
    tool: String,
    title: String,
    project: String,
    projectName: String,
    gitBranch: String,
    status: String,
    startedAt: Date,
    pid: Int?
) throws {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(dbPath, &connection, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
        defer { sqlite3_close(connection) }
        throw TestDatabaseError.openFailed
    }
    defer { sqlite3_close(connection) }

    let sql = """
        INSERT INTO sessions (
            id, tool, title, project, project_name, git_branch, status, started_at, pid,
            token_count, last_activity_at, last_file_mod, last_entry_type, activity_preview,
            activity_preview_kind, updated_at, last_indexed_mtime
        ) VALUES (
            ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17
        )
        """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
        defer { sqlite3_finalize(statement) }
        throw TestDatabaseError.prepareFailed
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_bind_text(statement, 1, id, -1, transientDestructor) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_text(statement, 2, tool, -1, transientDestructor) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_text(statement, 3, title, -1, transientDestructor) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_text(statement, 4, project, -1, transientDestructor) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_text(statement, 5, projectName, -1, transientDestructor) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_text(statement, 6, gitBranch, -1, transientDestructor) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_text(statement, 7, status, -1, transientDestructor) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_double(statement, 8, startedAt.timeIntervalSince1970) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    if let pid {
        guard sqlite3_bind_int64(statement, 9, Int64(pid)) == SQLITE_OK else {
            throw TestDatabaseError.bindFailed
        }
    } else {
        guard sqlite3_bind_null(statement, 9) == SQLITE_OK else {
            throw TestDatabaseError.bindFailed
        }
    }
    guard sqlite3_bind_int64(statement, 10, 0) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_double(statement, 11, startedAt.timeIntervalSince1970) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_null(statement, 12) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_null(statement, 13) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_null(statement, 14) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_null(statement, 15) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_double(statement, 16, startedAt.timeIntervalSince1970) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }
    guard sqlite3_bind_null(statement, 17) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }

    guard sqlite3_step(statement) == SQLITE_DONE else {
        throw TestDatabaseError.stepFailed
    }
}

private func sessionTableColumnNames(dbPath: String) throws -> Set<String> {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(dbPath, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        defer { sqlite3_close(connection) }
        throw TestDatabaseError.openFailed
    }
    defer { sqlite3_close(connection) }

    let sql = "PRAGMA table_info(sessions)"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
        sqlite3_finalize(statement)
        throw TestDatabaseError.prepareFailed
    }
    defer { sqlite3_finalize(statement) }

    var columns: Set<String> = []
    while sqlite3_step(statement) == SQLITE_ROW {
        guard let namePointer = sqlite3_column_text(statement, 1) else {
            continue
        }
        columns.insert(String(cString: namePointer))
    }

    return columns
}

private func transcriptRowCount(dbPath: String, sessionId: String) throws -> Int {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(dbPath, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        defer { sqlite3_close(connection) }
        throw TestDatabaseError.openFailed
    }
    defer { sqlite3_close(connection) }

    let sql = "SELECT COUNT(*) FROM transcripts WHERE session_id = ?1"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
        defer { sqlite3_finalize(statement) }
        throw TestDatabaseError.prepareFailed
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_bind_text(statement, 1, sessionId, -1, transientDestructor) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }

    guard sqlite3_step(statement) == SQLITE_ROW else {
        throw TestDatabaseError.stepFailed
    }

    return Int(sqlite3_column_int64(statement, 0))
}

private func transcriptContents(dbPath: String, sessionId: String) throws -> [String] {
    var connection: OpaquePointer?
    guard sqlite3_open_v2(dbPath, &connection, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        defer { sqlite3_close(connection) }
        throw TestDatabaseError.openFailed
    }
    defer { sqlite3_close(connection) }

    let sql = "SELECT content FROM transcripts WHERE session_id = ?1 ORDER BY rowid"
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(connection, sql, -1, &statement, nil) == SQLITE_OK else {
        defer { sqlite3_finalize(statement) }
        throw TestDatabaseError.prepareFailed
    }
    defer { sqlite3_finalize(statement) }

    guard sqlite3_bind_text(statement, 1, sessionId, -1, transientDestructor) == SQLITE_OK else {
        throw TestDatabaseError.bindFailed
    }

    var results: [String] = []
    while true {
        switch sqlite3_step(statement) {
        case SQLITE_ROW:
            guard let value = sqlite3_column_text(statement, 0) else {
                throw TestDatabaseError.stepFailed
            }
            results.append(String(cString: value))
        case SQLITE_DONE:
            return results
        default:
            throw TestDatabaseError.stepFailed
        }
    }
}

private func databaseHandle(for index: SessionIndex) throws -> OpaquePointer {
    let indexMirror = Mirror(reflecting: index)
    guard
        let database = indexMirror.children.first(where: { $0.label == "db" })?.value as? Database
    else {
        throw TestDatabaseError.handleLookupFailed
    }

    let databaseMirror = Mirror(reflecting: database)
    guard let handleValue = databaseMirror.children.first(where: { $0.label == "db" })?.value else {
        throw TestDatabaseError.handleLookupFailed
    }

    let handleMirror = Mirror(reflecting: handleValue)
    guard
        handleMirror.displayStyle == .optional,
        let handle = handleMirror.children.first?.value as? OpaquePointer
    else {
        throw TestDatabaseError.handleLookupFailed
    }

    return handle
}

private enum TestDatabaseError: Error {
    case openFailed
    case prepareFailed
    case bindFailed
    case stepFailed
    case handleLookupFailed
}

private let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
