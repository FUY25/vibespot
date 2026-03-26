import Foundation
import Testing
@testable import VibeLight

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
