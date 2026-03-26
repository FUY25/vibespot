# VibeLight V1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS app that provides a global-hotkey-triggered floating search panel for finding and jumping to AI coding sessions (Claude Code + Codex CLI).

**Architecture:** Menu bar app with a floating `NSPanel`. FSEvents watches `~/.claude/` and `~/.codex/` for JSONL session files. SQLite FTS5 indexes all session transcripts for full-text search. AppleScript maps sessions to Terminal.app windows for jumping.

**Tech Stack:** Swift 6, AppKit, FSEvents, SQLite (via C API), libproc (C interop), NSAppleScript

**Parser origin:** `TranscriptParser.swift` and `SessionLoader.swift` adapted from [Poirot](https://github.com/LeonardoCardoso/Poirot) (MIT license, Copyright 2026 Leonardo Cardoso). Refactored to feed FTS5 indexer instead of in-memory arrays.

---

## File Structure

```
~/Desktop/project/vibelight/
├── Package.swift                        # Swift Package Manager manifest
├── LICENSE                              # MIT
├── README.md                            # (later)
├── Sources/
│   ├── VibeLight/
│   │   ├── App/
│   │   │   ├── AppDelegate.swift        # NSApplication lifecycle, menu bar setup
│   │   │   └── main.swift               # Entry point
│   │   ├── Data/
│   │   │   ├── Database.swift           # SQLite wrapper (open, exec, prepared statements)
│   │   │   ├── SessionIndex.swift       # Schema, insert, query, FTS5 search
│   │   │   └── LiveSessionRegistry.swift # Reads ~/.claude/sessions/<PID>.json
│   │   ├── Parsers/
│   │   │   ├── ClaudeParser.swift       # Parse Claude JSONL + sessions-index.json (from Poirot)
│   │   │   ├── CodexParser.swift        # Parse Codex session_index.jsonl + session JSONL
│   │   │   └── Models.swift             # ParsedSession, ParsedMessage structs
│   │   ├── Watchers/
│   │   │   ├── FileWatcher.swift        # FSEvents wrapper, tracks file offsets
│   │   │   └── Indexer.swift            # Coordinates watchers → parsers → database
│   │   ├── Window/
│   │   │   ├── WindowJumper.swift       # AppleScript TTY→tab mapping + activate
│   │   │   └── ProcessInspector.swift   # libproc CWD/process name lookup
│   │   ├── UI/
│   │   │   ├── SearchPanelController.swift  # NSPanel + NSVisualEffectView
│   │   │   ├── SearchField.swift        # Custom NSTextField for search input
│   │   │   ├── ResultsTableView.swift   # NSTableView with session result rows
│   │   │   └── ResultRowView.swift      # Single result row (tool, title, project, status)
│   │   └── HotkeyManager.swift          # CGEvent tap for global hotkey
│   └── CLibProc/
│       ├── include/
│       │   └── clibproc.h               # C header for libproc imports
│       └── clibproc.c                   # Empty (header-only module)
├── Tests/
│   └── VibeLightTests/
│       ├── ClaudeParserTests.swift
│       ├── CodexParserTests.swift
│       ├── SessionIndexTests.swift
│       ├── DatabaseTests.swift
│       └── Fixtures/
│           ├── claude_session.jsonl
│           ├── claude_history.jsonl
│           ├── sessions_index.json
│           ├── codex_session.jsonl
│           ├── codex_session_index.jsonl
│           └── pid_registry.json
└── docs/
    └── spec.md                          # Symlink or copy of design spec
```

---

## Task 1: Project Scaffold + Build Verification

**Files:**
- Create: `Package.swift`
- Create: `Sources/VibeLight/App/main.swift`
- Create: `Sources/VibeLight/App/AppDelegate.swift`
- Create: `Sources/CLibProc/include/clibproc.h`
- Create: `Sources/CLibProc/clibproc.c`

- [ ] **Step 1: Create project directory and Package.swift**

```bash
mkdir -p ~/Desktop/project/vibelight
cd ~/Desktop/project/vibelight
git init
```

```swift
// Package.swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeLight",
    platforms: [.macOS(.v14)],
    targets: [
        .systemLibrary(
            name: "CLibProc",
            path: "Sources/CLibProc"
        ),
        .executableTarget(
            name: "VibeLight",
            dependencies: ["CLibProc"],
            path: "Sources/VibeLight",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .testTarget(
            name: "VibeLightTests",
            dependencies: ["VibeLight"],
            path: "Tests/VibeLightTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
```

- [ ] **Step 2: Create CLibProc module for libproc access**

```c
// Sources/CLibProc/include/clibproc.h
#ifndef CLIBPROC_H
#define CLIBPROC_H

#include <libproc.h>
#include <sys/sysctl.h>

#endif /* CLIBPROC_H */
```

```c
// Sources/CLibProc/clibproc.c
// Header-only module — this file exists to satisfy SPM
```

```
// Sources/CLibProc/include/module.modulemap
module CLibProc {
    header "clibproc.h"
    link "proc"
    export *
}
```

- [ ] **Step 3: Create minimal AppDelegate with menu bar icon**

```swift
// Sources/VibeLight/App/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "VL"
        }
    }
}
```

```swift
// Sources/VibeLight/App/main.swift
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

- [ ] **Step 4: Build and run to verify scaffold**

```bash
cd ~/Desktop/project/vibelight
swift build 2>&1
```

Expected: Build succeeds. No errors.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: project scaffold with menu bar icon and libproc module"
```

---

## Task 2: SQLite Database Wrapper

**Files:**
- Create: `Sources/VibeLight/Data/Database.swift`
- Create: `Tests/VibeLightTests/DatabaseTests.swift`

- [ ] **Step 1: Write failing test for database open/close**

```swift
// Tests/VibeLightTests/DatabaseTests.swift
import Testing
import Foundation
@testable import VibeLight

@Test func testDatabaseOpenClose() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let db = try Database(path: dbPath)
    try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
    try db.execute("INSERT INTO test (name) VALUES ('hello')")

    let rows = try db.query("SELECT name FROM test") { stmt in
        String(cString: sqlite3_column_text(stmt, 0))
    }
    #expect(rows == ["hello"])
}

@Test func testDatabaseFTS5() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let db = try Database(path: dbPath)
    try db.execute("CREATE VIRTUAL TABLE docs USING fts5(title, body)")
    try db.execute("INSERT INTO docs (title, body) VALUES ('Auth Bug', 'JWT token expires because refreshToken was never persisted')")
    try db.execute("INSERT INTO docs (title, body) VALUES ('API Tests', 'wrote unit tests for payment endpoint')")

    let results = try db.query("SELECT title, snippet(docs, 1, '>>>', '<<<', '...', 10) FROM docs WHERE docs MATCH 'token'") { stmt in
        (String(cString: sqlite3_column_text(stmt, 0)), String(cString: sqlite3_column_text(stmt, 1)))
    }
    #expect(results.count == 1)
    #expect(results[0].0 == "Auth Bug")
    #expect(results[0].1.contains("token"))
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter DatabaseTests 2>&1
```

Expected: FAIL — `Database` type not found.

- [ ] **Step 3: Implement Database wrapper**

```swift
// Sources/VibeLight/Data/Database.swift
import Foundation
import SQLite3

final class Database: @unchecked Sendable {
    private let db: OpaquePointer

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)
        guard rc == SQLITE_OK, let db = handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let h = handle { sqlite3_close(h) }
            throw DatabaseError.openFailed(msg)
        }
        self.db = db
        sqlite3_busy_timeout(db, 5000)
        try execute("PRAGMA journal_mode=WAL")
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String) throws {
        var errMsg: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
        if rc != SQLITE_OK {
            let msg = errMsg.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errMsg)
            throw DatabaseError.execFailed(msg)
        }
    }

    func query<T>(_ sql: String, map: (OpaquePointer) -> T) throws -> [T] {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let s = stmt else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(s) }

        var results: [T] = []
        while sqlite3_step(s) == SQLITE_ROW {
            results.append(map(s))
        }
        return results
    }

    func prepare(_ sql: String) throws -> Statement {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let s = stmt else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        return Statement(stmt: s)
    }

    final class Statement {
        let stmt: OpaquePointer

        init(stmt: OpaquePointer) {
            self.stmt = stmt
        }

        deinit {
            sqlite3_finalize(stmt)
        }

        func bind(index: Int32, text: String) {
            sqlite3_bind_text(stmt, index, (text as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        func bind(index: Int32, int: Int64) {
            sqlite3_bind_int64(stmt, index, int)
        }

        func step() -> Int32 {
            sqlite3_step(stmt)
        }

        func reset() {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
        }
    }
}

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let msg): "Failed to open database: \(msg)"
        case .execFailed(let msg): "SQL execution failed: \(msg)"
        case .prepareFailed(let msg): "Failed to prepare statement: \(msg)"
        }
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter DatabaseTests 2>&1
```

Expected: PASS — both tests green.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: SQLite database wrapper with FTS5 support"
```

---

## Task 3: Session Index Schema + CRUD

**Files:**
- Create: `Sources/VibeLight/Data/SessionIndex.swift`
- Create: `Tests/VibeLightTests/SessionIndexTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// Tests/VibeLightTests/SessionIndexTests.swift
import Testing
import Foundation
@testable import VibeLight

@Test func testInsertAndSearchSession() throws {
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

@Test func testSearchMetadataOnly() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)

    try index.upsertSession(
        id: "s1", tool: "claude", title: "fix auth bug",
        project: "/p", projectName: "myproject", gitBranch: "main",
        status: "live", startedAt: Date(), pid: 111
    )
    try index.upsertSession(
        id: "s2", tool: "codex", title: "write API tests",
        project: "/p", projectName: "myproject", gitBranch: "main",
        status: "closed", startedAt: Date(), pid: nil
    )

    // Live mode: only live sessions
    let live = try index.search(query: "myproject", includeHistory: false)
    #expect(live.count == 1)
    #expect(live[0].sessionId == "s1")

    // History mode: all sessions
    let all = try index.search(query: "myproject", includeHistory: true)
    #expect(all.count == 2)
}

@Test func testLiveSessionCount() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    try index.upsertSession(
        id: "s1", tool: "claude", title: "a", project: "/p", projectName: "p",
        gitBranch: "", status: "live", startedAt: Date(), pid: 1
    )
    try index.upsertSession(
        id: "s2", tool: "codex", title: "b", project: "/p", projectName: "p",
        gitBranch: "", status: "live", startedAt: Date(), pid: 2
    )
    try index.upsertSession(
        id: "s3", tool: "claude", title: "c", project: "/p", projectName: "p",
        gitBranch: "", status: "closed", startedAt: Date(), pid: nil
    )
    #expect(try index.liveSessionCount() == 2)
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
swift test --filter SessionIndexTests 2>&1
```

Expected: FAIL — `SessionIndex` not found.

- [ ] **Step 3: Implement SessionIndex**

```swift
// Sources/VibeLight/Data/SessionIndex.swift
import Foundation
import SQLite3

struct SearchResult {
    let sessionId: String
    let tool: String
    let title: String
    let project: String
    let projectName: String
    let gitBranch: String
    let status: String
    let startedAt: Date
    let pid: Int?
    let snippet: String?
}

final class SessionIndex: @unchecked Sendable {
    private let db: Database

    init(dbPath: String) throws {
        db = try Database(path: dbPath)
        try createSchema()
    }

    private func createSchema() throws {
        try db.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id TEXT PRIMARY KEY,
                tool TEXT NOT NULL,
                title TEXT NOT NULL,
                project TEXT NOT NULL,
                project_name TEXT NOT NULL,
                git_branch TEXT NOT NULL DEFAULT '',
                status TEXT NOT NULL DEFAULT 'closed',
                started_at REAL NOT NULL,
                pid INTEGER,
                updated_at REAL NOT NULL DEFAULT 0
            )
        """)

        try db.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS transcripts USING fts5(
                session_id,
                role,
                content,
                timestamp_str UNINDEXED
            )
        """)

        try db.execute("""
            CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status)
        """)
    }

    func upsertSession(
        id: String, tool: String, title: String,
        project: String, projectName: String, gitBranch: String,
        status: String, startedAt: Date, pid: Int?
    ) throws {
        let sql = """
            INSERT INTO sessions (id, tool, title, project, project_name, git_branch, status, started_at, pid, updated_at)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
            ON CONFLICT(id) DO UPDATE SET
                tool=?2, title=?3, project=?4, project_name=?5, git_branch=?6,
                status=?7, started_at=?8, pid=?9, updated_at=?10
        """
        let stmt = try db.prepare(sql)
        stmt.bind(index: 1, text: id)
        stmt.bind(index: 2, text: tool)
        stmt.bind(index: 3, text: title)
        stmt.bind(index: 4, text: project)
        stmt.bind(index: 5, text: projectName)
        stmt.bind(index: 6, text: gitBranch)
        stmt.bind(index: 7, text: status)
        stmt.bind(index: 8, int: Int64(startedAt.timeIntervalSince1970))
        if let pid = pid {
            stmt.bind(index: 9, int: Int64(pid))
        }
        stmt.bind(index: 10, int: Int64(Date().timeIntervalSince1970))
        let rc = stmt.step()
        guard rc == SQLITE_DONE else {
            throw DatabaseError.execFailed("upsert failed with code \(rc)")
        }
    }

    func insertTranscript(sessionId: String, role: String, content: String, timestamp: Date) throws {
        let sql = "INSERT INTO transcripts (session_id, role, content, timestamp_str) VALUES (?1, ?2, ?3, ?4)"
        let stmt = try db.prepare(sql)
        stmt.bind(index: 1, text: sessionId)
        stmt.bind(index: 2, text: role)
        stmt.bind(index: 3, text: content)
        stmt.bind(index: 4, text: ISO8601DateFormatter().string(from: timestamp))
        let rc = stmt.step()
        guard rc == SQLITE_DONE else {
            throw DatabaseError.execFailed("insert transcript failed with code \(rc)")
        }
    }

    func search(query: String, includeHistory: Bool) throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try listSessions(includeHistory: includeHistory)
        }

        // Phase 1: metadata match
        let metaLike = "%\(trimmed)%"
        let metaSQL = """
            SELECT id, tool, title, project, project_name, git_branch, status, started_at, pid, NULL as snippet
            FROM sessions
            WHERE (title LIKE ?1 OR project_name LIKE ?1 OR tool LIKE ?1 OR git_branch LIKE ?1)
            \(includeHistory ? "" : "AND status = 'live'")
            ORDER BY CASE status WHEN 'live' THEN 0 ELSE 1 END, started_at DESC
            LIMIT 50
        """
        var results = try db.query(metaSQL) { stmt -> SearchResult in
            sqlite3_bind_text(stmt, 1, (metaLike as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            return self.mapRow(stmt)
        }

        let metaIds = Set(results.map(\.sessionId))

        // Phase 2: FTS5 transcript match
        let ftsQuery = trimmed.split(separator: " ").map { "\"\($0)\"" }.joined(separator: " ")
        let ftsSQL = """
            SELECT t.session_id, s.tool, s.title, s.project, s.project_name, s.git_branch, s.status, s.started_at, s.pid,
                   snippet(transcripts, 2, '>>>', '<<<', '...', 16) as snippet
            FROM transcripts t
            JOIN sessions s ON s.id = t.session_id
            WHERE transcripts MATCH ?1
            \(includeHistory ? "" : "AND s.status = 'live'")
            GROUP BY t.session_id
            ORDER BY rank
            LIMIT 50
        """
        let ftsResults = try db.query(ftsSQL) { stmt -> SearchResult in
            sqlite3_bind_text(stmt, 1, (ftsQuery as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            return self.mapRow(stmt)
        }

        for r in ftsResults where !metaIds.contains(r.sessionId) {
            results.append(r)
        }

        return results
    }

    func liveSessionCount() throws -> Int {
        let rows = try db.query("SELECT COUNT(*) FROM sessions WHERE status = 'live'") { stmt in
            Int(sqlite3_column_int64(stmt, 0))
        }
        return rows.first ?? 0
    }

    func updateStatus(sessionId: String, status: String) throws {
        try db.execute("UPDATE sessions SET status = '\(status)', updated_at = \(Date().timeIntervalSince1970) WHERE id = '\(sessionId)'")
    }

    private func listSessions(includeHistory: Bool) throws -> [SearchResult] {
        let sql = """
            SELECT id, tool, title, project, project_name, git_branch, status, started_at, pid, NULL
            FROM sessions
            \(includeHistory ? "" : "WHERE status = 'live'")
            ORDER BY CASE status WHEN 'live' THEN 0 ELSE 1 END, started_at DESC
            LIMIT 50
        """
        return try db.query(sql) { self.mapRow($0) }
    }

    private func mapRow(_ stmt: OpaquePointer) -> SearchResult {
        SearchResult(
            sessionId: String(cString: sqlite3_column_text(stmt, 0)),
            tool: String(cString: sqlite3_column_text(stmt, 1)),
            title: String(cString: sqlite3_column_text(stmt, 2)),
            project: String(cString: sqlite3_column_text(stmt, 3)),
            projectName: String(cString: sqlite3_column_text(stmt, 4)),
            gitBranch: String(cString: sqlite3_column_text(stmt, 5)),
            status: String(cString: sqlite3_column_text(stmt, 6)),
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 7)),
            pid: sqlite3_column_type(stmt, 8) != SQLITE_NULL ? Int(sqlite3_column_int64(stmt, 8)) : nil,
            snippet: sqlite3_column_type(stmt, 9) != SQLITE_NULL ? String(cString: sqlite3_column_text(stmt, 9)) : nil
        )
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
swift test --filter SessionIndexTests 2>&1
```

Expected: ALL PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: session index with SQLite FTS5 full-text search"
```

---

## Task 4: Claude Code Parser (adapted from Poirot)

**Files:**
- Create: `Sources/VibeLight/Parsers/Models.swift`
- Create: `Sources/VibeLight/Parsers/ClaudeParser.swift`
- Create: `Tests/VibeLightTests/Fixtures/claude_session.jsonl`
- Create: `Tests/VibeLightTests/Fixtures/sessions_index.json`
- Create: `Tests/VibeLightTests/Fixtures/claude_history.jsonl`
- Create: `Tests/VibeLightTests/Fixtures/pid_registry.json`
- Create: `Tests/VibeLightTests/ClaudeParserTests.swift`

- [ ] **Step 1: Create test fixtures from real data**

Copy sanitized excerpts from your actual `~/.claude/` files. Create minimal but realistic fixtures:

```jsonl
// Tests/VibeLightTests/Fixtures/claude_session.jsonl
{"type":"user","message":{"role":"user","content":"fix the auth token expiration bug"},"uuid":"msg-001","timestamp":"2026-03-25T14:02:00.000Z","cwd":"/Users/me/project","sessionId":"session-001","gitBranch":"feat/auth"}
{"type":"assistant","message":{"id":"resp-001","model":"claude-sonnet-4-5-20250514","role":"assistant","content":[{"type":"text","text":"I'll look at the auth token handling code."}],"usage":{"input_tokens":100,"output_tokens":50}},"uuid":"msg-002","timestamp":"2026-03-25T14:02:05.000Z"}
{"type":"assistant","message":{"id":"resp-002","model":"claude-sonnet-4-5-20250514","role":"assistant","content":[{"type":"tool_use","id":"tool-001","name":"Read","input":{"file_path":"/Users/me/project/auth/token.go"}}],"usage":{"input_tokens":200,"output_tokens":30}},"uuid":"msg-003","timestamp":"2026-03-25T14:02:10.000Z"}
{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"tool-001","content":"package auth\n\nfunc RefreshToken() error {\n    return nil\n}"}]},"uuid":"msg-004","timestamp":"2026-03-25T14:02:11.000Z"}
{"type":"assistant","message":{"id":"resp-003","model":"claude-sonnet-4-5-20250514","role":"assistant","content":[{"type":"text","text":"The JWT token expires because refreshToken was never persisted to the database."}],"usage":{"input_tokens":300,"output_tokens":80}},"uuid":"msg-005","timestamp":"2026-03-25T14:03:00.000Z"}
```

```json
// Tests/VibeLightTests/Fixtures/sessions_index.json
{"version":1,"entries":[{"sessionId":"session-001","fullPath":"/fake/session-001.jsonl","firstPrompt":"fix the auth token expiration bug","summary":"Auth Token Bug Fix","messageCount":5,"created":"2026-03-25T14:02:00.000Z","modified":"2026-03-25T14:03:00.000Z","gitBranch":"feat/auth","projectPath":"/Users/me/project","isSidechain":false}]}
```

```jsonl
// Tests/VibeLightTests/Fixtures/claude_history.jsonl
{"display":"fix the auth token expiration bug","pastedContents":{},"timestamp":1774537320000,"project":"/Users/me/project","sessionId":"session-001"}
{"display":"write unit tests for payment module","pastedContents":{},"timestamp":1774537380000,"project":"/Users/me/api","sessionId":"session-002"}
```

```json
// Tests/VibeLightTests/Fixtures/pid_registry.json
{"pid":12345,"sessionId":"session-001","cwd":"/Users/me/project","startedAt":1774537320000}
```

- [ ] **Step 2: Write failing tests**

```swift
// Tests/VibeLightTests/ClaudeParserTests.swift
import Testing
import Foundation
@testable import VibeLight

@Test func testParseSessionJSONL() throws {
    let fixtureURL = Bundle.module.url(forResource: "claude_session", withExtension: "jsonl", subdirectory: "Fixtures")!
    let messages = try ClaudeParser.parseSessionFile(url: fixtureURL)

    #expect(messages.count >= 3) // user, assistant text, assistant tool_use, user tool_result, assistant text
    #expect(messages[0].role == "user")
    #expect(messages[0].content.contains("auth token"))
    #expect(messages.last?.content.contains("refreshToken") == true)
}

@Test func testParseSessionsIndex() throws {
    let fixtureURL = Bundle.module.url(forResource: "sessions_index", withExtension: "json", subdirectory: "Fixtures")!
    let entries = try ClaudeParser.parseSessionsIndex(url: fixtureURL)

    #expect(entries.count == 1)
    #expect(entries[0].sessionId == "session-001")
    #expect(entries[0].title == "Auth Token Bug Fix")
    #expect(entries[0].firstPrompt == "fix the auth token expiration bug")
    #expect(entries[0].gitBranch == "feat/auth")
}

@Test func testParseHistoryJSONL() throws {
    let fixtureURL = Bundle.module.url(forResource: "claude_history", withExtension: "jsonl", subdirectory: "Fixtures")!
    let entries = try ClaudeParser.parseHistory(url: fixtureURL)

    #expect(entries.count == 2)
    #expect(entries[0].sessionId == "session-001")
    #expect(entries[0].prompt == "fix the auth token expiration bug")
    #expect(entries[0].project == "/Users/me/project")
}

@Test func testParsePidRegistry() throws {
    let fixtureURL = Bundle.module.url(forResource: "pid_registry", withExtension: "json", subdirectory: "Fixtures")!
    let entry = try ClaudeParser.parsePidFile(url: fixtureURL)

    #expect(entry.pid == 12345)
    #expect(entry.sessionId == "session-001")
}

@Test func testDecodeProjectPath() {
    let decoded = ClaudeParser.decodeProjectPath("-Users-fuyuming-Desktop-project-terminalrail")
    #expect(decoded.contains("Desktop") || decoded.contains("terminalrail"))
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
swift test --filter ClaudeParserTests 2>&1
```

Expected: FAIL — `ClaudeParser` not found.

- [ ] **Step 4: Implement parser models**

```swift
// Sources/VibeLight/Parsers/Models.swift
import Foundation

struct ParsedMessage {
    let role: String        // "user" or "assistant"
    let content: String     // Flattened text content (all text blocks joined)
    let timestamp: Date
    let toolCalls: [String] // e.g. ["Read: auth/token.go", "Bash: go test ./..."]
    let sessionId: String?
    let gitBranch: String?
    let cwd: String?
}

struct ParsedSessionMeta {
    let sessionId: String
    let title: String
    let firstPrompt: String?
    let projectPath: String
    let gitBranch: String
    let startedAt: Date
    let isSidechain: Bool
}

struct ParsedHistoryEntry {
    let sessionId: String
    let prompt: String
    let project: String
    let timestamp: Date
}

struct ParsedPidEntry {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Date
}
```

- [ ] **Step 5: Implement ClaudeParser**

```swift
// Sources/VibeLight/Parsers/ClaudeParser.swift
import Foundation

// Adapted from Poirot (MIT License, Copyright 2026 Leonardo Cardoso)
// Refactored to produce flat ParsedMessage structs for FTS5 indexing.

enum ClaudeParser {
    private static let dateFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    // MARK: - Session JSONL

    static func parseSessionFile(url: URL) throws -> [ParsedMessage] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return [] }

        var messages: [ParsedMessage] = []
        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
            else { continue }

            guard let type = record["type"] as? String,
                  type == "user" || type == "assistant"
            else { continue }

            // Skip sidechains and synthetic messages
            if record["isSidechain"] as? Bool == true { continue }
            let message = record["message"] as? [String: Any] ?? [:]
            if type == "assistant", message["model"] as? String == "<synthetic>" { continue }

            let timestamp = (record["timestamp"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date.distantPast
            let sessionId = record["sessionId"] as? String
            let gitBranch = record["gitBranch"] as? String
            let cwd = record["cwd"] as? String

            if type == "user" {
                let content = extractTextContent(from: message["content"])
                if !content.isEmpty {
                    messages.append(ParsedMessage(
                        role: "user", content: content, timestamp: timestamp,
                        toolCalls: [], sessionId: sessionId, gitBranch: gitBranch, cwd: cwd
                    ))
                }
            } else if type == "assistant" {
                let (text, tools) = extractAssistantContent(from: message["content"])
                if !text.isEmpty || !tools.isEmpty {
                    messages.append(ParsedMessage(
                        role: "assistant", content: text, timestamp: timestamp,
                        toolCalls: tools, sessionId: sessionId, gitBranch: gitBranch, cwd: cwd
                    ))
                }
            }
        }

        return messages
    }

    // MARK: - sessions-index.json

    static func parseSessionsIndex(url: URL) throws -> [ParsedSessionMeta] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]]
        else { return [] }

        return entries.compactMap { entry -> ParsedSessionMeta? in
            guard let sessionId = entry["sessionId"] as? String,
                  let created = entry["created"] as? String
            else { return nil }

            let startedAt = dateFormatter.date(from: created) ?? Date.distantPast
            let title = entry["summary"] as? String ?? entry["firstPrompt"] as? String ?? "Untitled"
            let firstPrompt = entry["firstPrompt"] as? String
            let projectPath = entry["projectPath"] as? String ?? ""
            let gitBranch = entry["gitBranch"] as? String ?? ""
            let isSidechain = entry["isSidechain"] as? Bool ?? false

            return ParsedSessionMeta(
                sessionId: sessionId, title: title, firstPrompt: firstPrompt,
                projectPath: projectPath, gitBranch: gitBranch,
                startedAt: startedAt, isSidechain: isSidechain
            )
        }
    }

    // MARK: - history.jsonl

    static func parseHistory(url: URL) throws -> [ParsedHistoryEntry] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return [] }

        return text.components(separatedBy: .newlines).compactMap { line -> ParsedHistoryEntry? in
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let display = record["display"] as? String,
                  let project = record["project"] as? String,
                  let ts = record["timestamp"] as? Double
            else { return nil }

            let sessionId = record["sessionId"] as? String ?? ""
            return ParsedHistoryEntry(
                sessionId: sessionId,
                prompt: display,
                project: project,
                timestamp: Date(timeIntervalSince1970: ts / 1000.0)
            )
        }
    }

    // MARK: - PID Registry

    static func parsePidFile(url: URL) throws -> ParsedPidEntry {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pid = json["pid"] as? Int,
              let sessionId = json["sessionId"] as? String,
              let cwd = json["cwd"] as? String,
              let startedAt = json["startedAt"] as? Double
        else {
            throw ClaudeParserError.invalidPidFile
        }
        return ParsedPidEntry(pid: pid, sessionId: sessionId, cwd: cwd, timestamp: Date(timeIntervalSince1970: startedAt / 1000.0))
    }

    // MARK: - Project Path Decoding

    static func decodeProjectPath(_ encoded: String) -> String {
        // Simple decode: replace leading dash, then dashes with /
        // This is a simplified version — Poirot uses filesystem probing for accuracy
        var path = encoded
        if path.hasPrefix("-") { path = String(path.dropFirst()) }
        return "/" + path.replacingOccurrences(of: "-", with: "/")
    }

    // MARK: - Private Helpers

    private static func extractTextContent(from content: Any?) -> String {
        if let str = content as? String { return str }
        guard let array = content as? [[String: Any]] else { return "" }
        return array.compactMap { block -> String? in
            if block["type"] as? String == "text" { return block["text"] as? String }
            if block["type"] as? String == "tool_result" {
                return normalizeToolResultContent(block["content"])
            }
            return nil
        }.joined(separator: "\n")
    }

    private static func extractAssistantContent(from content: Any?) -> (text: String, tools: [String]) {
        guard let array = content as? [[String: Any]] else { return ("", []) }
        var texts: [String] = []
        var tools: [String] = []

        for block in array {
            switch block["type"] as? String {
            case "text":
                if let t = block["text"] as? String, !t.isEmpty { texts.append(t) }
            case "tool_use":
                if let name = block["name"] as? String {
                    let input = block["input"] as? [String: Any] ?? [:]
                    let detail = input["file_path"] as? String
                        ?? input["path"] as? String
                        ?? input["command"] as? String
                        ?? ""
                    tools.append("\(name): \(detail)")
                }
            case "thinking":
                break // Skip thinking blocks for search indexing
            default:
                break
            }
        }

        return (texts.joined(separator: "\n"), tools)
    }

    private static func normalizeToolResultContent(_ content: Any?) -> String {
        if let str = content as? String { return str }
        guard let array = content as? [[String: Any]] else { return "" }
        return array.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined(separator: "\n")
    }
}

enum ClaudeParserError: Error {
    case invalidPidFile
}

// Add missing initializer for ParsedPidEntry
extension ParsedPidEntry {
    init(pid: Int, sessionId: String, cwd: String, timestamp: Date) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.startedAt = timestamp
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

```bash
swift test --filter ClaudeParserTests 2>&1
```

Expected: ALL PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: Claude Code JSONL parser adapted from Poirot"
```

---

## Task 5: Codex CLI Parser

**Files:**
- Create: `Sources/VibeLight/Parsers/CodexParser.swift`
- Create: `Tests/VibeLightTests/Fixtures/codex_session.jsonl`
- Create: `Tests/VibeLightTests/Fixtures/codex_session_index.jsonl`
- Create: `Tests/VibeLightTests/CodexParserTests.swift`

- [ ] **Step 1: Create Codex fixtures**

```jsonl
// Tests/VibeLightTests/Fixtures/codex_session_index.jsonl
{"id":"codex-001","thread_name":"Analyze folder structure","updated_at":"2026-03-22T13:17:39.96871Z"}
{"id":"codex-002","thread_name":"Move OCR files and plan batch run","updated_at":"2026-03-22T13:17:39.970067Z"}
```

```jsonl
// Tests/VibeLightTests/Fixtures/codex_session.jsonl
{"timestamp":"2026-03-22T13:00:00.000Z","type":"session_meta","payload":{"id":"codex-001","timestamp":"2026-03-22T13:00:00.000Z","cwd":"/Users/me/project","originator":"codex_cli","cli_version":"0.78.0"}}
{"timestamp":"2026-03-22T13:00:01.000Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"analyze the folder structure of this project"}]}}
{"timestamp":"2026-03-22T13:00:05.000Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"I'll analyze the project structure. The main directories are src/, tests/, and docs/."}]}}
```

- [ ] **Step 2: Write failing tests**

```swift
// Tests/VibeLightTests/CodexParserTests.swift
import Testing
import Foundation
@testable import VibeLight

@Test func testParseCodexSessionIndex() throws {
    let fixtureURL = Bundle.module.url(forResource: "codex_session_index", withExtension: "jsonl", subdirectory: "Fixtures")!
    let entries = try CodexParser.parseSessionIndex(url: fixtureURL)

    #expect(entries.count == 2)
    #expect(entries[0].sessionId == "codex-001")
    #expect(entries[0].title == "Analyze folder structure")
}

@Test func testParseCodexSession() throws {
    let fixtureURL = Bundle.module.url(forResource: "codex_session", withExtension: "jsonl", subdirectory: "Fixtures")!
    let (meta, messages) = try CodexParser.parseSessionFile(url: fixtureURL)

    #expect(meta?.cwd == "/Users/me/project")
    #expect(messages.count >= 2)
    #expect(messages[0].role == "user")
    #expect(messages[0].content.contains("folder structure"))
    #expect(messages[1].role == "assistant")
}
```

- [ ] **Step 3: Run tests to verify they fail**

```bash
swift test --filter CodexParserTests 2>&1
```

- [ ] **Step 4: Implement CodexParser**

```swift
// Sources/VibeLight/Parsers/CodexParser.swift
import Foundation

struct CodexSessionMeta {
    let id: String
    let cwd: String
    let cliVersion: String
    let source: String
}

enum CodexParser {
    private static let dateFormatter: ISO8601DateFormatter = {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt
    }()

    // MARK: - session_index.jsonl

    static func parseSessionIndex(url: URL) throws -> [ParsedSessionMeta] {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8)
        else { return [] }

        return text.components(separatedBy: .newlines).compactMap { line -> ParsedSessionMeta? in
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let id = record["id"] as? String,
                  let threadName = record["thread_name"] as? String
            else { return nil }

            let updatedAt = (record["updated_at"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date.distantPast

            return ParsedSessionMeta(
                sessionId: id,
                title: threadName,
                firstPrompt: nil,
                projectPath: "",
                gitBranch: "",
                startedAt: updatedAt,
                isSidechain: false
            )
        }
    }

    // MARK: - Session JSONL

    static func parseSessionFile(url: URL) throws -> (meta: CodexSessionMeta?, messages: [ParsedMessage]) {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8), !text.isEmpty
        else { return (nil, []) }

        var meta: CodexSessionMeta?
        var messages: [ParsedMessage] = []

        for line in text.components(separatedBy: .newlines) {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let record = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let type = record["type"] as? String
            else { continue }

            let timestamp = (record["timestamp"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date.distantPast

            if type == "session_meta" {
                if let payload = record["payload"] as? [String: Any] {
                    meta = CodexSessionMeta(
                        id: payload["id"] as? String ?? "",
                        cwd: payload["cwd"] as? String ?? "",
                        cliVersion: payload["cli_version"] as? String ?? "",
                        source: payload["source"] as? String ?? payload["originator"] as? String ?? "cli"
                    )
                }
            } else if type == "response_item" {
                guard let payload = record["payload"] as? [String: Any],
                      let role = payload["role"] as? String,
                      let content = payload["content"] as? [[String: Any]]
                else { continue }

                let textParts = content.compactMap { block -> String? in
                    let blockType = block["type"] as? String
                    if blockType == "input_text" || blockType == "output_text" || blockType == "text" {
                        return block["text"] as? String
                    }
                    return nil
                }

                let text = textParts.joined(separator: "\n")
                if !text.isEmpty {
                    let mappedRole = role == "user" ? "user" : "assistant"
                    messages.append(ParsedMessage(
                        role: mappedRole, content: text, timestamp: timestamp,
                        toolCalls: [], sessionId: meta?.id, gitBranch: nil, cwd: meta?.cwd
                    ))
                }
            }
        }

        return (meta, messages)
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

```bash
swift test --filter CodexParserTests 2>&1
```

Expected: ALL PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: Codex CLI session parser"
```

---

## Task 6: Live Session Registry

**Files:**
- Create: `Sources/VibeLight/Data/LiveSessionRegistry.swift`

- [ ] **Step 1: Implement LiveSessionRegistry**

Reads `~/.claude/sessions/<PID>.json` files and checks if PIDs are alive.

```swift
// Sources/VibeLight/Data/LiveSessionRegistry.swift
import Foundation

struct LiveSession {
    let pid: Int
    let sessionId: String
    let cwd: String
    let isAlive: Bool
}

enum LiveSessionRegistry {
    private static let sessionsPath: String = {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/sessions"
    }()

    static func scan() -> [LiveSession] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsPath) else { return [] }

        return files.compactMap { filename -> LiveSession? in
            guard filename.hasSuffix(".json") else { return nil }
            let path = (sessionsPath as NSString).appendingPathComponent(filename)
            let url = URL(fileURLWithPath: path)
            guard let entry = try? ClaudeParser.parsePidFile(url: url) else { return nil }

            let alive = isProcessAlive(pid: entry.pid)
            return LiveSession(pid: entry.pid, sessionId: entry.sessionId, cwd: entry.cwd, isAlive: alive)
        }
    }

    private static func isProcessAlive(pid: Int) -> Bool {
        // kill(pid, 0) returns 0 if process exists
        kill(Int32(pid), 0) == 0
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: live session PID registry scanner"
```

---

## Task 7: FSEvents File Watcher

**Files:**
- Create: `Sources/VibeLight/Watchers/FileWatcher.swift`

- [ ] **Step 1: Implement FileWatcher**

```swift
// Sources/VibeLight/Watchers/FileWatcher.swift
import Foundation
import CoreServices

@MainActor
final class FileWatcher {
    private var stream: FSEventStreamRef?
    private let paths: [String]
    private let onChange: ([String]) -> Void

    init(paths: [String], onChange: @escaping @Sendable ([String]) -> Void) {
        self.paths = paths
        self.onChange = onChange
    }

    func start() {
        let pathsToWatch = paths as CFArray

        var context = FSEventStreamContext()
        context.info = Unmanaged.passUnretained(self).toOpaque()

        let callback: FSEventStreamCallback = { (stream, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            guard let info = clientCallBackInfo else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as! [String]
            Task { @MainActor in
                watcher.onChange(paths)
            }
        }

        stream = FSEventStreamCreate(
            nil, callback, &context,
            pathsToWatch, FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // 1 second latency
            UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents)
        )

        if let stream = stream {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        if let stream = stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: FSEvents file watcher"
```

---

## Task 8: Indexer (Watcher → Parser → Database)

**Files:**
- Create: `Sources/VibeLight/Watchers/Indexer.swift`

- [ ] **Step 1: Implement Indexer**

Coordinates file watching, parsing, and database indexing.

```swift
// Sources/VibeLight/Watchers/Indexer.swift
import Foundation

@MainActor
final class Indexer {
    let sessionIndex: SessionIndex
    private var fileWatcher: FileWatcher?
    private var processedFiles: Set<String> = []

    init(sessionIndex: SessionIndex) {
        self.sessionIndex = sessionIndex
    }

    func start() {
        // Initial full scan
        Task {
            await performFullScan()
        }

        // Watch for changes
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let watchPaths = [
            home + "/.claude",
            home + "/.codex"
        ]

        fileWatcher = FileWatcher(paths: watchPaths) { [weak self] changedPaths in
            Task { @MainActor in
                self?.handleChanges(changedPaths)
            }
        }
        fileWatcher?.start()

        // Periodic live session refresh (every 3 seconds)
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLiveSessions()
            }
        }
    }

    func stop() {
        fileWatcher?.stop()
    }

    // MARK: - Full Scan

    private func performFullScan() async {
        scanClaudeSessions()
        scanCodexSessions()
        refreshLiveSessions()
    }

    private func scanClaudeSessions() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let projectsPath = home + "/.claude/projects"
        let fm = FileManager.default

        guard let projectDirs = try? fm.contentsOfDirectory(atPath: projectsPath) else { return }

        for dirName in projectDirs {
            let dirPath = (projectsPath as NSString).appendingPathComponent(dirName)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let projectPath = ClaudeParser.decodeProjectPath(dirName)
            let projectName = (projectPath as NSString).lastPathComponent

            // Try sessions-index.json first
            let indexURL = URL(fileURLWithPath: dirPath).appendingPathComponent("sessions-index.json")
            if let metas = try? ClaudeParser.parseSessionsIndex(url: indexURL) {
                for meta in metas where !meta.isSidechain {
                    indexClaudeSession(meta: meta, dirPath: dirPath, projectName: projectName)
                }
            }

            // Also scan raw JSONL files (source of truth)
            if let files = try? fm.contentsOfDirectory(atPath: dirPath) {
                for file in files where file.hasSuffix(".jsonl") {
                    let filePath = (dirPath as NSString).appendingPathComponent(file)
                    let sessionId = (file as NSString).deletingPathExtension
                    guard isUUID(sessionId) else { continue }
                    indexClaudeSessionFile(path: filePath, sessionId: sessionId, projectPath: projectPath, projectName: projectName)
                }
            }
        }
    }

    private func indexClaudeSession(meta: ParsedSessionMeta, dirPath: String, projectName: String) {
        try? sessionIndex.upsertSession(
            id: meta.sessionId, tool: "claude", title: meta.title,
            project: meta.projectPath, projectName: projectName,
            gitBranch: meta.gitBranch, status: "closed",
            startedAt: meta.startedAt, pid: nil
        )
    }

    private func indexClaudeSessionFile(path: String, sessionId: String, projectPath: String, projectName: String) {
        guard !processedFiles.contains(path) else { return }
        processedFiles.insert(path)

        let url = URL(fileURLWithPath: path)
        guard let messages = try? ClaudeParser.parseSessionFile(url: url) else { return }

        let title = messages.first(where: { $0.role == "user" })?.content ?? "Untitled"
        let truncatedTitle = String(title.prefix(200))
        let gitBranch = messages.first?.gitBranch ?? ""
        let startedAt = messages.first?.timestamp ?? Date.distantPast

        try? sessionIndex.upsertSession(
            id: sessionId, tool: "claude", title: truncatedTitle,
            project: projectPath, projectName: projectName,
            gitBranch: gitBranch, status: "closed",
            startedAt: startedAt, pid: nil
        )

        for msg in messages {
            let searchableContent = msg.content + (msg.toolCalls.isEmpty ? "" : "\n" + msg.toolCalls.joined(separator: "\n"))
            try? sessionIndex.insertTranscript(
                sessionId: sessionId, role: msg.role,
                content: searchableContent, timestamp: msg.timestamp
            )
        }
    }

    private func scanCodexSessions() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        // Parse session_index.jsonl for titles
        let indexURL = URL(fileURLWithPath: home + "/.codex/session_index.jsonl")
        let metas = (try? CodexParser.parseSessionIndex(url: indexURL)) ?? []
        var titleMap: [String: String] = [:]
        for meta in metas {
            titleMap[meta.sessionId] = meta.title
            try? sessionIndex.upsertSession(
                id: meta.sessionId, tool: "codex", title: meta.title,
                project: "", projectName: "", gitBranch: "",
                status: "closed", startedAt: meta.startedAt, pid: nil
            )
        }

        // Parse session files for full transcripts
        let sessionsPath = home + "/.codex/sessions"
        let fm = FileManager.default
        guard let years = try? fm.contentsOfDirectory(atPath: sessionsPath) else { return }

        for year in years {
            let yearPath = (sessionsPath as NSString).appendingPathComponent(year)
            guard let months = try? fm.contentsOfDirectory(atPath: yearPath) else { continue }
            for month in months {
                let monthPath = (yearPath as NSString).appendingPathComponent(month)
                guard let days = try? fm.contentsOfDirectory(atPath: monthPath) else { continue }
                for day in days {
                    let dayPath = (monthPath as NSString).appendingPathComponent(day)
                    guard let files = try? fm.contentsOfDirectory(atPath: dayPath) else { continue }
                    for file in files where file.hasSuffix(".jsonl") {
                        let filePath = (dayPath as NSString).appendingPathComponent(file)
                        indexCodexSessionFile(path: filePath, titleMap: titleMap)
                    }
                }
            }
        }
    }

    private func indexCodexSessionFile(path: String, titleMap: [String: String]) {
        guard !processedFiles.contains(path) else { return }
        processedFiles.insert(path)

        let url = URL(fileURLWithPath: path)
        guard let (meta, messages) = try? CodexParser.parseSessionFile(url: url) else { return }
        guard let sessionId = meta?.id ?? messages.first?.sessionId else { return }

        let title = titleMap[sessionId] ?? messages.first(where: { $0.role == "user" })?.content ?? "Untitled"
        let truncatedTitle = String(title.prefix(200))
        let cwd = meta?.cwd ?? ""

        try? sessionIndex.upsertSession(
            id: sessionId, tool: "codex", title: truncatedTitle,
            project: cwd, projectName: (cwd as NSString).lastPathComponent,
            gitBranch: "", status: "closed",
            startedAt: messages.first?.timestamp ?? Date.distantPast, pid: nil
        )

        for msg in messages {
            try? sessionIndex.insertTranscript(
                sessionId: sessionId, role: msg.role,
                content: msg.content, timestamp: msg.timestamp
            )
        }
    }

    // MARK: - Live Sessions

    private func refreshLiveSessions() {
        let liveSessions = LiveSessionRegistry.scan()
        let liveIds = Set(liveSessions.filter(\.isAlive).map(\.sessionId))

        for session in liveSessions where session.isAlive {
            try? sessionIndex.updateStatus(sessionId: session.sessionId, status: "live")
        }

        // Mark dead sessions as closed
        // (simplified — full version would query all "live" sessions and check)
    }

    // MARK: - Change Handling

    private func handleChanges(_ paths: [String]) {
        for path in paths {
            if path.contains("/.claude/sessions/") && path.hasSuffix(".json") {
                refreshLiveSessions()
            } else if path.hasSuffix(".jsonl") {
                if path.contains("/.claude/") {
                    // Re-index this specific file
                    let sessionId = (URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent)
                    if isUUID(sessionId) {
                        processedFiles.remove(path) // Force re-process
                        // Determine project context from path
                        let projectPath = ClaudeParser.decodeProjectPath(
                            URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent
                        )
                        indexClaudeSessionFile(
                            path: path, sessionId: sessionId,
                            projectPath: projectPath,
                            projectName: (projectPath as NSString).lastPathComponent
                        )
                    }
                } else if path.contains("/.codex/") {
                    processedFiles.remove(path)
                    indexCodexSessionFile(path: path, titleMap: [:])
                }
            }
        }
    }

    // MARK: - Helpers

    private static let uuidRegex = try? NSRegularExpression(
        pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
    )

    private func isUUID(_ str: String) -> Bool {
        let range = NSRange(str.startIndex..., in: str)
        return Self.uuidRegex?.firstMatch(in: str, range: range) != nil
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: indexer coordinates file watching, parsing, and database"
```

---

## Task 9: Global Hotkey Manager

**Files:**
- Create: `Sources/VibeLight/HotkeyManager.swift`

- [ ] **Step 1: Implement HotkeyManager**

```swift
// Sources/VibeLight/HotkeyManager.swift
import AppKit
import Carbon

@MainActor
final class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private let onToggle: () -> Void

    init(onToggle: @escaping @Sendable () -> Void) {
        self.onToggle = onToggle
    }

    func register() {
        let eventMask = (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon = refcon else { return Unmanaged.passRetained(event) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()

            if type == .keyDown {
                let flags = event.flags
                let keycode = event.getIntegerValueField(.keyboardEventKeycode)

                // Cmd+Shift+Space: keycode 49 = space
                let hasCmd = flags.contains(.maskCommand)
                let hasShift = flags.contains(.maskShift)
                let isSpace = keycode == 49

                if hasCmd && hasShift && isSpace {
                    Task { @MainActor in
                        manager.onToggle()
                    }
                    return nil // Consume the event
                }
            }

            return Unmanaged.passRetained(event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap = eventTap else {
            print("Failed to create event tap. Accessibility permission required.")
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(nil, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func unregister() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: global hotkey manager (Cmd+Shift+Space)"
```

---

## Task 10: Floating Search Panel UI

**Files:**
- Create: `Sources/VibeLight/UI/SearchPanelController.swift`
- Create: `Sources/VibeLight/UI/SearchField.swift`
- Create: `Sources/VibeLight/UI/ResultsTableView.swift`
- Create: `Sources/VibeLight/UI/ResultRowView.swift`

- [ ] **Step 1: Create SearchPanelController**

```swift
// Sources/VibeLight/UI/SearchPanelController.swift
import AppKit

@MainActor
final class SearchPanelController {
    private let panel: NSPanel
    private let searchField: NSTextField
    private let resultsTableView: NSTableView
    private let scrollView: NSScrollView
    private let modeLabel: NSTextField
    private let visualEffect: NSVisualEffectView

    private var results: [SearchResult] = []
    private var includeHistory = false
    var sessionIndex: SessionIndex?
    var onSelect: ((SearchResult) -> Void)?

    init() {
        // Panel setup
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 80),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.hasShadow = true

        // Visual effect background
        visualEffect = NSVisualEffectView()
        visualEffect.material = .hudWindow
        visualEffect.state = .active
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true

        // Search field
        searchField = NSTextField()
        searchField.placeholderString = "Search sessions..."
        searchField.font = .systemFont(ofSize: 18, weight: .light)
        searchField.isBordered = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.textColor = .white

        // Mode label
        modeLabel = NSTextField(labelWithString: "● Live")
        modeLabel.font = .systemFont(ofSize: 11, weight: .medium)
        modeLabel.textColor = .secondaryLabelColor

        // Results table
        resultsTableView = NSTableView()
        resultsTableView.headerView = nil
        resultsTableView.backgroundColor = .clear
        resultsTableView.rowHeight = 44
        resultsTableView.intercellSpacing = NSSize(width: 0, height: 2)

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("result"))
        column.width = 580
        resultsTableView.addTableColumn(column)

        scrollView = NSScrollView()
        scrollView.documentView = resultsTableView
        scrollView.hasVerticalScroller = false
        scrollView.drawsBackground = false

        // Layout
        panel.contentView = visualEffect

        searchField.translatesAutoresizingMaskIntoConstraints = false
        modeLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        visualEffect.addSubview(searchField)
        visualEffect.addSubview(modeLabel)
        visualEffect.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: visualEffect.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor, constant: 16),
            searchField.trailingAnchor.constraint(equalTo: modeLabel.leadingAnchor, constant: -8),

            modeLabel.centerYAnchor.constraint(equalTo: searchField.centerYAnchor),
            modeLabel.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
        ])

        resultsTableView.delegate = self
        resultsTableView.dataSource = self
        searchField.delegate = self
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible {
            hide()
        } else {
            show()
        }
    }

    func show() {
        // Center on active screen
        guard let screen = NSScreen.main else { return }
        let screenFrame = screen.visibleFrame
        let panelWidth: CGFloat = 600
        let panelHeight: CGFloat = 80
        let x = screenFrame.midX - panelWidth / 2
        let y = screenFrame.midY + 100

        panel.setFrame(NSRect(x: x, y: y, width: panelWidth, height: panelHeight), display: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
        searchField.stringValue = ""
        results = []
        resultsTableView.reloadData()

        // Show all live sessions by default
        performSearch("")
    }

    func hide() {
        panel.orderOut(nil)
    }

    private func performSearch(_ query: String) {
        guard let index = sessionIndex else { return }

        do {
            results = try index.search(query: query, includeHistory: includeHistory)
            resultsTableView.reloadData()
            resizePanel()
        } catch {
            results = []
            resultsTableView.reloadData()
        }
    }

    private func toggleMode() {
        includeHistory.toggle()
        modeLabel.stringValue = includeHistory ? "○ History" : "● Live"
        performSearch(searchField.stringValue)
    }

    private func resizePanel() {
        let baseHeight: CGFloat = 80
        let rowHeight: CGFloat = 46
        let maxRows: CGFloat = 8
        let rows = min(CGFloat(results.count), maxRows)
        let totalHeight = baseHeight + rows * rowHeight

        var frame = panel.frame
        let oldHeight = frame.height
        frame.size.height = totalHeight
        frame.origin.y -= (totalHeight - oldHeight)
        panel.setFrame(frame, display: true, animate: true)
    }

    private func selectResult(at index: Int) {
        guard index >= 0, index < results.count else { return }
        hide()
        onSelect?(results[index])
    }
}

// MARK: - NSTableViewDataSource

extension SearchPanelController: NSTableViewDataSource {
    nonisolated func numberOfRows(in tableView: NSTableView) -> Int {
        MainActor.assumeIsolated { results.count }
    }
}

// MARK: - NSTableViewDelegate

extension SearchPanelController: NSTableViewDelegate {
    nonisolated func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        MainActor.assumeIsolated {
            let result = results[row]

            let cell = NSTableCellView()
            cell.wantsLayer = true

            let toolLabel = NSTextField(labelWithString: "[\(result.tool.capitalized)]")
            toolLabel.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
            toolLabel.textColor = result.tool == "claude" ? .systemOrange : .systemGreen

            let titleLabel = NSTextField(labelWithString: result.title)
            titleLabel.font = .systemFont(ofSize: 14, weight: .regular)
            titleLabel.textColor = .white
            titleLabel.lineBreakMode = .byTruncatingTail

            let detailLabel = NSTextField(labelWithString: "\(result.projectName)  \(result.gitBranch)")
            detailLabel.font = .systemFont(ofSize: 11)
            detailLabel.textColor = .secondaryLabelColor

            let statusDot = NSTextField(labelWithString: result.status == "live" ? "●" : "○")
            statusDot.font = .systemFont(ofSize: 10)
            statusDot.textColor = result.status == "live" ? .systemGreen : .tertiaryLabelColor

            for v in [toolLabel, titleLabel, detailLabel, statusDot] {
                v.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(v)
            }

            NSLayoutConstraint.activate([
                toolLabel.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16),
                toolLabel.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),

                titleLabel.leadingAnchor.constraint(equalTo: toolLabel.trailingAnchor, constant: 8),
                titleLabel.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
                titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: statusDot.leadingAnchor, constant: -8),

                detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
                detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),

                statusDot.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -16),
                statusDot.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])

            // Snippet line if present
            if let snippet = result.snippet {
                let snippetLabel = NSTextField(labelWithString: "↳ \(snippet)")
                snippetLabel.font = .systemFont(ofSize: 11)
                snippetLabel.textColor = .systemYellow
                snippetLabel.lineBreakMode = .byTruncatingTail
                snippetLabel.translatesAutoresizingMaskIntoConstraints = false
                cell.addSubview(snippetLabel)
                NSLayoutConstraint.activate([
                    snippetLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor, constant: 8),
                    snippetLabel.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 2),
                    snippetLabel.trailingAnchor.constraint(equalTo: statusDot.leadingAnchor, constant: -8),
                ])
            }

            return cell
        }
    }

    nonisolated func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        MainActor.assumeIsolated {
            results[row].snippet != nil ? 62 : 44
        }
    }

    nonisolated func tableViewSelectionDidChange(_ notification: Notification) {
        MainActor.assumeIsolated {
            // No-op, selection handled by keyboard
        }
    }
}

// MARK: - NSTextFieldDelegate

extension SearchPanelController: NSTextFieldDelegate {
    nonisolated func controlTextDidChange(_ obj: Notification) {
        MainActor.assumeIsolated {
            performSearch(searchField.stringValue)
        }
    }

    nonisolated func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        MainActor.assumeIsolated {
            switch commandSelector {
            case #selector(NSResponder.cancelOperation(_:)):
                hide()
                return true
            case #selector(NSResponder.insertNewline(_:)):
                selectResult(at: resultsTableView.selectedRow)
                return true
            case #selector(NSResponder.moveDown(_:)):
                let next = min(resultsTableView.selectedRow + 1, results.count - 1)
                resultsTableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                resultsTableView.scrollRowToVisible(next)
                return true
            case #selector(NSResponder.moveUp(_:)):
                let prev = max(resultsTableView.selectedRow - 1, 0)
                resultsTableView.selectRowIndexes(IndexSet(integer: prev), byExtendingSelection: false)
                resultsTableView.scrollRowToVisible(prev)
                return true
            case #selector(NSResponder.insertTab(_:)):
                toggleMode()
                return true
            default:
                return false
            }
        }
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: floating search panel UI with fuzzy search and result rows"
```

---

## Task 11: Window Jumper (AppleScript)

**Files:**
- Create: `Sources/VibeLight/Window/WindowJumper.swift`

- [ ] **Step 1: Implement WindowJumper**

```swift
// Sources/VibeLight/Window/WindowJumper.swift
import AppKit

enum WindowJumper {
    /// Jump to a Terminal.app window running the given PID
    static func jumpToSession(_ result: SearchResult) {
        guard result.status == "live", let pid = result.pid else { return }

        // Try Terminal.app first
        if jumpViaTerminalApp(pid: pid) { return }

        // Fallback: activate the app owning the PID
        activateAppForPid(pid)
    }

    private static func jumpViaTerminalApp(pid: Int) -> Bool {
        let script = """
        tell application "System Events"
            if not (exists process "Terminal") then return false
        end tell

        tell application "Terminal"
            set targetTTY to ""
            -- Find the TTY for this PID via shell
            set ttyResult to do shell script "ps -p \(pid) -o tty= 2>/dev/null || echo ''"
            if ttyResult is "" then return false
            set targetTTY to "/dev/" & ttyResult

            repeat with w from 1 to (count of windows)
                repeat with t from 1 to (count of tabs of window w)
                    if tty of tab t of window w is targetTTY then
                        set selected of tab t of window w to true
                        set index of window w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
        end tell
        return false
        """

        var error: NSDictionary?
        let appleScript = NSAppleScript(source: script)
        let result = appleScript?.executeAndReturnError(&error)

        if let error = error {
            print("AppleScript error: \(error)")
            return false
        }

        return result?.booleanValue ?? false
    }

    private static func activateAppForPid(_ pid: Int) {
        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            app.activate()
        } else {
            // PID might be a child of the terminal app — find the terminal
            let parentPid = getParentPid(pid)
            if let parent = parentPid, let app = NSRunningApplication(processIdentifier: pid_t(parent)) {
                app.activate()
            }
        }
    }

    private static func getParentPid(_ pid: Int) -> Int? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, Int32(pid)]
        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        guard result == 0 else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? Int(ppid) : nil
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "feat: window jumper via AppleScript TTY mapping"
```

---

## Task 12: Wire Everything Together in AppDelegate

**Files:**
- Modify: `Sources/VibeLight/App/AppDelegate.swift`

- [ ] **Step 1: Update AppDelegate to connect all components**

```swift
// Sources/VibeLight/App/AppDelegate.swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var searchPanel: SearchPanelController!
    private var indexer: Indexer!
    private var sessionIndex: SessionIndex!
    private var statusUpdateTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — menu bar app only
        NSApp.setActivationPolicy(.accessory)

        setupDatabase()
        setupMenuBar()
        setupHotkey()
        setupSearchPanel()
        startIndexing()
        startStatusUpdates()
    }

    private func setupDatabase() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let vibeLightDir = appSupport.appendingPathComponent("VibeLight")
        try? FileManager.default.createDirectory(at: vibeLightDir, withIntermediateDirectories: true)
        let dbPath = vibeLightDir.appendingPathComponent("index.sqlite3").path

        do {
            sessionIndex = try SessionIndex(dbPath: dbPath)
        } catch {
            print("Failed to open database: \(error)")
            NSApp.terminate(nil)
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "VL: 0"
            button.action = #selector(togglePanel)
            button.target = self
        }
    }

    private func setupHotkey() {
        hotkeyManager = HotkeyManager { [weak self] in
            self?.togglePanel()
        }
        hotkeyManager.register()
    }

    private func setupSearchPanel() {
        searchPanel = SearchPanelController()
        searchPanel.sessionIndex = sessionIndex
        searchPanel.onSelect = { result in
            WindowJumper.jumpToSession(result)
        }
    }

    private func startIndexing() {
        indexer = Indexer(sessionIndex: sessionIndex)
        indexer.start()
    }

    private func startStatusUpdates() {
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarCount()
            }
        }
        updateMenuBarCount()
    }

    private func updateMenuBarCount() {
        let count = (try? sessionIndex.liveSessionCount()) ?? 0
        statusItem.button?.title = "VL: \(count)"
    }

    @objc private func togglePanel() {
        searchPanel.toggle()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyManager?.unregister()
        indexer?.stop()
        statusUpdateTimer?.invalidate()
    }
}
```

- [ ] **Step 2: Build the complete app**

```bash
cd ~/Desktop/project/vibelight
swift build 2>&1
```

Expected: Build succeeds.

- [ ] **Step 3: Run the app to test manually**

```bash
swift run VibeLight &
```

Expected: Menu bar shows "VL: N" where N is your live session count. Cmd+Shift+Space shows the floating panel. Typing searches sessions. Enter jumps to the session window.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "feat: wire up complete VibeLight app — search, index, jump"
```

---

## Task 13: Run All Tests + Final Verification

- [ ] **Step 1: Run all tests**

```bash
cd ~/Desktop/project/vibelight
swift test 2>&1
```

Expected: All tests pass.

- [ ] **Step 2: Run the app and verify end-to-end**

```bash
swift run VibeLight
```

Manual checklist:
1. Menu bar shows "VL: N" with correct live session count
2. Cmd+Shift+Space opens floating panel
3. Panel is centered, dark translucent, rounded corners
4. Typing filters sessions in real-time
5. Tab toggles between Live and History modes
6. Arrow keys navigate results
7. Enter jumps to the selected terminal window
8. Esc dismisses the panel
9. Searching for text from an AI response (e.g., a specific error message) finds the right session with a snippet

- [ ] **Step 3: Final commit**

```bash
git add -A
git commit -m "chore: all tests passing, V1 complete"
```

---

## Summary

| Task | Component | Estimated Steps |
|------|-----------|----------------|
| 1 | Project scaffold | 5 |
| 2 | SQLite Database wrapper | 5 |
| 3 | Session Index + FTS5 | 5 |
| 4 | Claude Code parser | 7 |
| 5 | Codex CLI parser | 6 |
| 6 | Live session registry | 2 |
| 7 | FSEvents file watcher | 2 |
| 8 | Indexer (coordinator) | 2 |
| 9 | Global hotkey manager | 2 |
| 10 | Floating search panel UI | 2 |
| 11 | Window jumper (AppleScript) | 2 |
| 12 | AppDelegate wiring | 4 |
| 13 | Final testing + verification | 3 |
| **Total** | | **47 steps** |
