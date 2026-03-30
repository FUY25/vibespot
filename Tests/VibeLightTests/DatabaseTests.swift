import Foundation
import SQLite3
import Testing
@testable import Flare

private enum TransactionTestError: Error {
    case rollbackSentinel
}

private func makeTemporaryDatabase() throws -> (Database, String) {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    return (try Database(path: dbPath), dbPath)
}

private final class WeakDatabaseRef {
    weak var value: Database?

    init(_ value: Database?) {
        self.value = value
    }
}

@Test
func testDatabaseOpenClose() throws {
    let (db, dbPath) = try makeTemporaryDatabase()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)")
    try db.execute("INSERT INTO test (name) VALUES ('hello')")

    let rows = try db.query("SELECT name FROM test") { stmt in
        String(cString: sqlite3_column_text(stmt, 0))
    }

    #expect(rows == ["hello"])
}

@Test
func testDatabaseFTS5() throws {
    let (db, dbPath) = try makeTemporaryDatabase()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

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

@Test
func testPreparedStatementRetainsDatabaseDuringBindResetAndReuse() throws {
    let tmpDir = FileManager.default.temporaryDirectory
    let dbPath = tmpDir.appendingPathComponent("test_\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    var db: Database? = try Database(path: dbPath)
    let weakDatabase = WeakDatabaseRef(db)
    try db?.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT NOT NULL, count INTEGER NOT NULL)")

    let insert = try db!.prepare("INSERT INTO test (name, count) VALUES (?, ?)")
    db = nil

    guard let retainedDatabase = weakDatabase.value else {
        Issue.record("Prepared statements should retain their owning database while still in use.")
        return
    }

    try insert.bind(index: 1, text: "alpha")
    try insert.bind(index: 2, int: 1)
    #expect(insert.step() == SQLITE_DONE)

    insert.reset()
    try insert.bind(index: 1, text: "beta")
    try insert.bind(index: 2, int: 2)
    #expect(insert.step() == SQLITE_DONE)

    let rows = try retainedDatabase.query("SELECT name, count FROM test ORDER BY id") { stmt in
        (
            String(cString: sqlite3_column_text(stmt, 0)),
            sqlite3_column_int64(stmt, 1)
        )
    }

    #expect(rows.count == 2)
    #expect(rows[0].0 == "alpha")
    #expect(rows[0].1 == 1)
    #expect(rows[1].0 == "beta")
    #expect(rows[1].1 == 2)
}

@Test
func testParameterizedReadQueryBindsBeforeStepping() throws {
    let (db, dbPath) = try makeTemporaryDatabase()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try db.execute("CREATE TABLE test (name TEXT NOT NULL)")
    try db.execute("INSERT INTO test (name) VALUES ('alpha')")
    try db.execute("INSERT INTO test (name) VALUES ('alphabet')")
    try db.execute("INSERT INTO test (name) VALUES ('beta')")

    let rows = try db.query(
        "SELECT name FROM test WHERE name LIKE ?1 ORDER BY name",
        bind: { statement in
            try statement.bind(index: 1, text: "alpha%")
        },
        map: { stmt in
            String(cString: sqlite3_column_text(stmt, 0))
        }
    )

    #expect(rows == ["alpha", "alphabet"])
}

@Test
func testPreparedStatementBindThrowsWhenParameterIndexIsOutOfRange() throws {
    let (db, dbPath) = try makeTemporaryDatabase()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let statement = try db.prepare("SELECT ?1")
    let bindText: (Int32, String) throws -> Void = statement.bind(index:text:)

    do {
        try bindText(2, "alpha")
        Issue.record("Expected binding an out-of-range parameter index to fail.")
    } catch let error as DatabaseError {
        switch error {
        case .bindFailed(let message):
            #expect(!message.isEmpty)
        default:
            Issue.record("Expected a bindFailed error, got \(error).")
        }
    }
}

@Test
func testCloseThrowsWhenStatementIsStillOpen() throws {
    let (db, dbPath) = try makeTemporaryDatabase()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY)")

    var statement: Database.Statement? = try db.prepare("INSERT INTO test (id) VALUES (?)")
    #expect(statement != nil)

    do {
        try db.close()
        Issue.record("Expected closing the database to fail while a prepared statement is still open.")
    } catch let error as DatabaseError {
        switch error {
        case .closeFailed:
            break
        default:
            Issue.record("Expected a closeFailed error, got \(error).")
        }
    }

    statement = nil
    try db.close()
}

@Test
func testTransactionRollsBackWhenOperationThrows() throws {
    let (db, dbPath) = try makeTemporaryDatabase()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    try db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT NOT NULL)")
    try db.execute("INSERT INTO test (name) VALUES ('before')")

    do {
        try db.transaction {
            try db.execute("DELETE FROM test")
            try db.execute("INSERT INTO test (name) VALUES ('during')")
            throw TransactionTestError.rollbackSentinel
        }
        Issue.record("Expected the transaction body to throw.")
    } catch TransactionTestError.rollbackSentinel {
    }

    let rows = try db.query("SELECT name FROM test ORDER BY id") { stmt in
        String(cString: sqlite3_column_text(stmt, 0))
    }

    #expect(rows == ["before"])
}
