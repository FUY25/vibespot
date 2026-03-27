import Foundation
import SQLite3

final class CodexStateDB {
    let path: String
    private var lastFailureTime: Date?
    private var lastLogTime: Date?
    private static let cooldownInterval: TimeInterval = 30
    private static let logThrottleInterval: TimeInterval = 60

    init(path: String) {
        self.path = path
    }

    init() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex")
            .appendingPathComponent("state_5.sqlite")
            .path
        self.init(path: path)
    }

    func sessionIdByCwd(_ cwd: String) -> String? {
        guard shouldAttemptOpen() else { return nil }

        return withReadOnlyDatabase { db in
            let sql = """
            SELECT id
            FROM threads
            WHERE cwd = ?1
            ORDER BY updated_at DESC
            LIMIT 1
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                logSQLiteError(db, context: "prepare sessionIdByCwd")
                return nil
            }
            defer { sqlite3_finalize(statement) }

            guard sqlite3_bind_text(statement, 1, (cwd as NSString).utf8String, -1, Self.transientDestructor) == SQLITE_OK else {
                logSQLiteError(db, context: "bind sessionIdByCwd")
                return nil
            }

            let rc = sqlite3_step(statement)
            guard rc == SQLITE_ROW else {
                if rc != SQLITE_DONE {
                    logSQLiteError(db, context: "step sessionIdByCwd", code: rc)
                }
                return nil
            }
            guard let id = sqlite3_column_text(statement, 0) else {
                return nil
            }

            return String(cString: id)
        }
    }

    func gitBranchMap() -> [String: String] {
        guard shouldAttemptOpen() else { return [:] }

        return withReadOnlyDatabase { db in
            let sql = """
            SELECT id, git_branch
            FROM threads
            WHERE git_branch IS NOT NULL
              AND TRIM(git_branch) <> ''
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                logSQLiteError(db, context: "prepare gitBranchMap")
                return [:]
            }
            defer { sqlite3_finalize(statement) }

            var branches: [String: String] = [:]

            while true {
                let rc = sqlite3_step(statement)
                if rc == SQLITE_DONE {
                    break
                }
                if rc != SQLITE_ROW {
                    logSQLiteError(db, context: "step gitBranchMap", code: rc)
                    break
                }

                guard let idText = sqlite3_column_text(statement, 0),
                      let branchText = sqlite3_column_text(statement, 1)
                else {
                    continue
                }

                branches[String(cString: idText)] = String(cString: branchText)
            }

            return branches
        } ?? [:]
    }

    private func shouldAttemptOpen() -> Bool {
        if let lastFailure = lastFailureTime {
            let elapsed = Date().timeIntervalSince(lastFailure)
            if elapsed < Self.cooldownInterval {
                return false
            }
        }
        return true
    }

    private func withReadOnlyDatabase<T>(_ operation: (OpaquePointer) -> T?) -> T? {
        guard FileManager.default.fileExists(atPath: path) else {
            lastFailureTime = Date()
            return nil
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)

        guard rc == SQLITE_OK, let db = handle else {
            lastFailureTime = Date()
            if let handle {
                logSQLiteError(handle, context: "open read-only database", code: rc)
                sqlite3_close_v2(handle)
            }
            return nil
        }

        // Reset failure tracking on successful open
        lastFailureTime = nil

        if sqlite3_busy_timeout(db, 300) != SQLITE_OK {
            logSQLiteError(db, context: "configure busy timeout")
        }

        defer {
            let closeRC = sqlite3_close_v2(db)
            if closeRC != SQLITE_OK {
                logSQLiteError(db, context: "close read-only database", code: closeRC)
            }
        }
        return operation(db)
    }

    private func logSQLiteError(_ db: OpaquePointer?, context: String, code: Int32? = nil) {
        let now = Date()
        if let lastLog = lastLogTime, now.timeIntervalSince(lastLog) < Self.logThrottleInterval {
            return
        }
        lastLogTime = now

        let rc = code ?? sqlite3_errcode(db)
        let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        print("CodexStateDB: \(context) failed (\(rc)): \(message)")
    }

    // Equivalent to SQLITE_TRANSIENT for sqlite3_bind_text.
    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
