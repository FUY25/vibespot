import Foundation
import SQLite3
import Testing
@testable import VibeLight

private func makeTempDBPath() -> String {
    let tmpDir = FileManager.default.temporaryDirectory
    return tmpDir.appendingPathComponent("codex_state_\(UUID().uuidString).sqlite3").path
}

private func withWritableSQLiteDB(at path: String, _ body: (OpaquePointer) throws -> Void) throws {
    var handle: OpaquePointer?
    let rc = sqlite3_open_v2(path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
    guard rc == SQLITE_OK, let db = handle else {
        let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        if let handle {
            sqlite3_close(handle)
        }
        throw NSError(domain: "CodexStateDBTests", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: message])
    }

    defer { sqlite3_close(db) }
    try body(db)
}

private func exec(_ sql: String, on db: OpaquePointer) throws {
    var errorMessage: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)
    guard rc == SQLITE_OK else {
        let message = errorMessage.map { String(cString: $0) } ?? "unknown"
        sqlite3_free(errorMessage)
        throw NSError(domain: "CodexStateDBTests", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: message])
    }
}

private func createThreadsTable(on db: OpaquePointer) throws {
    try exec(
        """
        CREATE TABLE threads (
            id TEXT PRIMARY KEY,
            cwd TEXT NOT NULL,
            updated_at INTEGER NOT NULL,
            git_branch TEXT,
            rollout_path TEXT NOT NULL DEFAULT ''
        );
        """,
        on: db
    )
}

@Test
func sessionIdByCwdReturnsMatchingSession() throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try withWritableSQLiteDB(at: dbPath) { db in
        try createThreadsTable(on: db)
        try exec("INSERT INTO threads (id, cwd, updated_at, git_branch) VALUES ('thread-1', '/tmp/project-a', 100, 'main')", on: db)
        try exec("INSERT INTO threads (id, cwd, updated_at, git_branch) VALUES ('thread-2', '/tmp/project-b', 200, 'feature')", on: db)
    }

    let stateDB = CodexStateDB(path: dbPath)
    #expect(stateDB.sessionIdByCwd("/tmp/project-b") == "thread-2")
}

@Test
func sameCwdReturnsMostRecentUpdatedAtSession() throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try withWritableSQLiteDB(at: dbPath) { db in
        try createThreadsTable(on: db)
        try exec("INSERT INTO threads (id, cwd, updated_at, git_branch) VALUES ('older', '/tmp/shared', 100, 'main')", on: db)
        try exec("INSERT INTO threads (id, cwd, updated_at, git_branch) VALUES ('newer', '/tmp/shared', 500, 'main')", on: db)
    }

    let stateDB = CodexStateDB(path: dbPath)
    #expect(stateDB.sessionIdByCwd("/tmp/shared") == "newer")
}

@Test
func unknownCwdReturnsNil() throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try withWritableSQLiteDB(at: dbPath) { db in
        try createThreadsTable(on: db)
        try exec("INSERT INTO threads (id, cwd, updated_at, git_branch) VALUES ('thread-1', '/tmp/project-a', 100, 'main')", on: db)
    }

    let stateDB = CodexStateDB(path: dbPath)
    #expect(stateDB.sessionIdByCwd("/tmp/does-not-exist") == nil)
}

@Test
func sessionIdByRolloutPathReturnsMatchingSession() throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try withWritableSQLiteDB(at: dbPath) { db in
        try createThreadsTable(on: db)
        try exec(
            """
            INSERT INTO threads (id, cwd, updated_at, git_branch, rollout_path)
            VALUES ('thread-1', '/tmp/project-a', 100, 'main', '/Users/me/.codex/sessions/2026/03/28/rollout-a.jsonl')
            """,
            on: db
        )
        try exec(
            """
            INSERT INTO threads (id, cwd, updated_at, git_branch, rollout_path)
            VALUES ('thread-2', '/tmp/project-a', 200, 'feature', '/Users/me/.codex/sessions/2026/03/28/rollout-b.jsonl')
            """,
            on: db
        )
    }

    let stateDB = CodexStateDB(path: dbPath)
    #expect(
        stateDB.sessionIdByRolloutPath("/Users/me/.codex/sessions/2026/03/28/rollout-a.jsonl")
            == "thread-1"
    )
}

@Test
func unknownRolloutPathReturnsNil() throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try withWritableSQLiteDB(at: dbPath) { db in
        try createThreadsTable(on: db)
        try exec(
            """
            INSERT INTO threads (id, cwd, updated_at, git_branch, rollout_path)
            VALUES ('thread-1', '/tmp/project-a', 100, 'main', '/Users/me/.codex/sessions/2026/03/28/rollout-a.jsonl')
            """,
            on: db
        )
    }

    let stateDB = CodexStateDB(path: dbPath)
    #expect(stateDB.sessionIdByRolloutPath("/Users/me/.codex/sessions/2026/03/28/missing.jsonl") == nil)
}

@Test
func duplicateRolloutPathReturnsNilToAvoidAmbiguousLiveIdentity() throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try withWritableSQLiteDB(at: dbPath) { db in
        try createThreadsTable(on: db)
        try exec(
            """
            INSERT INTO threads (id, cwd, updated_at, git_branch, rollout_path)
            VALUES ('thread-1', '/tmp/project-a', 100, 'main', '/Users/me/.codex/sessions/2026/03/28/rollout-shared.jsonl')
            """,
            on: db
        )
        try exec(
            """
            INSERT INTO threads (id, cwd, updated_at, git_branch, rollout_path)
            VALUES ('thread-2', '/tmp/project-b', 200, 'feature', '/Users/me/.codex/sessions/2026/03/28/rollout-shared.jsonl')
            """,
            on: db
        )
    }

    let stateDB = CodexStateDB(path: dbPath)
    #expect(stateDB.sessionIdByRolloutPath("/Users/me/.codex/sessions/2026/03/28/rollout-shared.jsonl") == nil)
}

@Test
func gitBranchMapReturnsBranchesAndFiltersEmptyBranch() throws {
    let dbPath = makeTempDBPath()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try withWritableSQLiteDB(at: dbPath) { db in
        try createThreadsTable(on: db)
        try exec("INSERT INTO threads (id, cwd, updated_at, git_branch) VALUES ('thread-1', '/tmp/project-a', 100, 'main')", on: db)
        try exec("INSERT INTO threads (id, cwd, updated_at, git_branch) VALUES ('thread-2', '/tmp/project-b', 200, '')", on: db)
        try exec("INSERT INTO threads (id, cwd, updated_at, git_branch) VALUES ('thread-3', '/tmp/project-c', 300, 'feature/search')", on: db)
        try exec("INSERT INTO threads (id, cwd, updated_at, git_branch) VALUES ('thread-4', '/tmp/project-d', 400, NULL)", on: db)
        try exec("INSERT INTO threads (id, cwd, updated_at, git_branch) VALUES ('thread-5', '/tmp/project-e', 500, '   ')", on: db)
    }

    let stateDB = CodexStateDB(path: dbPath)
    #expect(stateDB.gitBranchMap() == [
        "thread-1": "main",
        "thread-3": "feature/search",
    ])
}

@Test
func nonexistentDBReturnsNilAndEmptyMap() {
    let dbPath = makeTempDBPath()

    let stateDB = CodexStateDB(path: dbPath)
    #expect(stateDB.sessionIdByCwd("/tmp/anything") == nil)
    #expect(stateDB.gitBranchMap().isEmpty)
}
