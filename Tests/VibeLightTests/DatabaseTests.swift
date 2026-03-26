import Foundation
import SQLite3
import Testing
@testable import VibeLight

@Test
func testDatabaseOpenClose() throws {
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

@Test
func testDatabaseFTS5() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let db = try Database(path: dbPath)
    try db.execute("CREATE VIRTUAL TABLE docs USING fts5(title, body)")
    try db.execute("INSERT INTO docs (title, body) VALUES ('Auth Bug', 'JWT token expires because refreshToken was never persisted')")
    try db.execute("INSERT INTO docs (title, body) VALUES ('API Tests', 'wrote unit tests for payment endpoint')")

    let results = try db.query("SELECT title, snippet(docs, 1, '>>>', '<<<', '...', 10) FROM docs WHERE docs MATCH 'token'") { stmt in
        (
            String(cString: sqlite3_column_text(stmt, 0)),
            String(cString: sqlite3_column_text(stmt, 1))
        )
    }

    #expect(results.count == 1)
    #expect(results[0].0 == "Auth Bug")
    #expect(results[0].1.contains("token"))
}
