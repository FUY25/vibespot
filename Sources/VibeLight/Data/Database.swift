import Foundation
import SQLite3

// Equivalent to SQLITE_TRANSIENT for sqlite3_bind_text.
let sqliteTransientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

final class Database: @unchecked Sendable {
    // One lock protects the handle and every statement lifecycle transition.
    private let lock = NSRecursiveLock()
    private var db: OpaquePointer?

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
        lock.lock()
        defer { lock.unlock() }

        guard let db else { return }

        let rc = sqlite3_close_v2(db)
        if rc != SQLITE_OK {
            assertionFailure(DatabaseError.closeFailed(String(cString: sqlite3_errmsg(db))).localizedDescription)
        }
    }

    func execute(_ sql: String) throws {
        try withLock {
            let db = try requireOpenDatabase()
            try executeLocked(sql, on: db)
        }
    }

    func transaction<T>(_ operation: () throws -> T) throws -> T {
        try withLock {
            let db = try requireOpenDatabase()
            try executeLocked("BEGIN IMMEDIATE TRANSACTION", on: db)

            do {
                let result = try operation()
                try executeLocked("COMMIT TRANSACTION", on: db)
                return result
            } catch {
                try? executeLocked("ROLLBACK TRANSACTION", on: db)
                throw error
            }
        }
    }

    func query<T>(_ sql: String, map: (OpaquePointer) -> T) throws -> [T] {
        try query(sql, bind: { _ in }, map: map)
    }

    func query<T>(
        _ sql: String,
        bind: (Statement) throws -> Void,
        map: (OpaquePointer) -> T
    ) throws -> [T] {
        let statement = try prepare(sql)

        try bind(statement)

        var results: [T] = []
        while true {
            let stepResult = statement.step()

            switch stepResult {
            case SQLITE_ROW:
                results.append(statement.withRawStatement(map))
            case SQLITE_DONE:
                return results
            default:
                throw DatabaseError.stepFailed(statement.connectionErrorMessage())
            }
        }
    }

    func close() throws {
        try withLock {
            guard let db else { return }

            let rc = sqlite3_close(db)

            guard rc == SQLITE_OK else {
                throw DatabaseError.closeFailed(String(cString: sqlite3_errmsg(db)))
            }

            self.db = nil
        }
    }

    func prepare(_ sql: String) throws -> Statement {
        let statement = try prepareStatement(sql)
        return Statement(owner: self, stmt: statement)
    }

    private func prepareStatement(_ sql: String) throws -> OpaquePointer {
        try withLock {
            let db = try requireOpenDatabase()
            var statement: OpaquePointer?
            let rc = sqlite3_prepare_v2(db, sql, -1, &statement, nil)

            guard rc == SQLITE_OK, let statement else {
                throw DatabaseError.prepareFailed(String(cString: sqlite3_errmsg(db)))
            }

            return statement
        }
    }

    private func executeLocked(_ sql: String, on db: OpaquePointer) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if rc != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(errorMessage)
            throw DatabaseError.execFailed(message)
        }
    }

    final class Statement {
        private let owner: Database
        let stmt: OpaquePointer

        init(owner: Database, stmt: OpaquePointer) {
            self.owner = owner
            self.stmt = stmt
        }

        deinit {
            owner.lock.lock()
            defer { owner.lock.unlock() }
            sqlite3_finalize(stmt)
        }

        func bind(index: Int32, text: String) throws {
            let rc = owner.withLock {
                sqlite3_bind_text(
                    stmt,
                    index,
                    (text as NSString).utf8String,
                    -1,
                    sqliteTransientDestructor
                )
            }

            guard rc == SQLITE_OK else {
                throw DatabaseError.bindFailed(connectionErrorMessage())
            }
        }

        func bind(index: Int32, int: Int64) throws {
            let rc = owner.withLock {
                sqlite3_bind_int64(stmt, index, int)
            }

            guard rc == SQLITE_OK else {
                throw DatabaseError.bindFailed(connectionErrorMessage())
            }
        }

        func bind(index: Int32, double: Double) throws {
            let rc = owner.withLock {
                sqlite3_bind_double(stmt, index, double)
            }

            guard rc == SQLITE_OK else {
                throw DatabaseError.bindFailed(connectionErrorMessage())
            }
        }

        func bindNull(index: Int32) throws {
            let rc = owner.withLock {
                sqlite3_bind_null(stmt, index)
            }

            guard rc == SQLITE_OK else {
                throw DatabaseError.bindFailed(connectionErrorMessage())
            }
        }

        func step() -> Int32 {
            owner.withLock {
                sqlite3_step(stmt)
            }
        }

        func reset() {
            owner.withLock {
                sqlite3_reset(stmt)
                sqlite3_clear_bindings(stmt)
            }
        }

        func withRawStatement<T>(_ operation: (OpaquePointer) -> T) -> T {
            owner.withLock {
                operation(stmt)
            }
        }

        func connectionErrorMessage() -> String {
            owner.withLock {
                guard let db = sqlite3_db_handle(stmt) else {
                    return "unknown"
                }

                return String(cString: sqlite3_errmsg(db))
            }
        }
    }

    private func requireOpenDatabase() throws -> OpaquePointer {
        guard let db else {
            throw DatabaseError.closeFailed("Database is already closed.")
        }

        return db
    }

    private func withLock<T>(_ operation: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try operation()
    }
}

enum DatabaseError: Error, LocalizedError {
    case openFailed(String)
    case execFailed(String)
    case prepareFailed(String)
    case bindFailed(String)
    case stepFailed(String)
    case closeFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let message):
            "Failed to open database: \(message)"
        case .execFailed(let message):
            "SQL execution failed: \(message)"
        case .prepareFailed(let message):
            "Failed to prepare statement: \(message)"
        case .bindFailed(let message):
            "Failed to bind statement parameter: \(message)"
        case .stepFailed(let message):
            "Failed to step statement: \(message)"
        case .closeFailed(let message):
            "Failed to close database: \(message)"
        }
    }
}
