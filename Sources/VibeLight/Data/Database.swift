import Foundation
import SQLite3

final class Database: @unchecked Sendable {
    private let db: OpaquePointer

    init(path: String) throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)

        guard rc == SQLITE_OK, let db = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            if let handle {
                sqlite3_close(handle)
            }
            throw DatabaseError.openFailed(message)
        }

        self.db = db
        sqlite3_busy_timeout(db, 5_000)
        try execute("PRAGMA journal_mode=WAL")
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw DatabaseError.execFailed(message)
        }
    }

    func query<T>(_ sql: String, map: (OpaquePointer) -> T) throws -> [T] {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &statement, nil)

        guard rc == SQLITE_OK, let statement else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        defer {
            sqlite3_finalize(statement)
        }

        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(map(statement))
        }

        return results
    }

    func prepare(_ sql: String) throws -> Statement {
        var statement: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &statement, nil)

        guard rc == SQLITE_OK, let statement else {
            throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }

        return Statement(stmt: statement)
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
            sqlite3_bind_text(
                stmt,
                index,
                (text as NSString).utf8String,
                -1,
                unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            )
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
        case .openFailed(let message):
            "Failed to open database: \(message)"
        case .execFailed(let message):
            "SQL execution failed: \(message)"
        case .prepareFailed(let message):
            "Failed to prepare statement: \(message)"
        }
    }
}
