import Foundation
import SQLite3

struct CodexStateDB {
    let path: String

    init(path: String) {
        self.path = path
    }

    init() {
        self.init(path: FileManager.default.homeDirectoryForCurrentUser.path + "/.codex/state_5.sqlite")
    }

    func sessionIdByCwd(_ cwd: String) -> String? {
        withReadOnlyDatabase { db in
            let sql = """
            SELECT id
            FROM threads
            WHERE cwd = ?1
            ORDER BY updated_at DESC
            LIMIT 1
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                return nil
            }
            defer { sqlite3_finalize(statement) }

            guard sqlite3_bind_text(statement, 1, (cwd as NSString).utf8String, -1, Self.transientDestructor) == SQLITE_OK else {
                return nil
            }

            guard sqlite3_step(statement) == SQLITE_ROW,
                  let id = sqlite3_column_text(statement, 0)
            else {
                return nil
            }

            return String(cString: id)
        }
    }

    func gitBranchMap() -> [String: String] {
        withReadOnlyDatabase { db in
            let sql = """
            SELECT id, git_branch
            FROM threads
            WHERE git_branch IS NOT NULL
              AND TRIM(git_branch) <> ''
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                return [:]
            }
            defer { sqlite3_finalize(statement) }

            var branches: [String: String] = [:]

            while sqlite3_step(statement) == SQLITE_ROW {
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

    private func withReadOnlyDatabase<T>(_ operation: (OpaquePointer) -> T?) -> T? {
        guard FileManager.default.fileExists(atPath: path) else {
            return nil
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX
        let rc = sqlite3_open_v2(path, &handle, flags, nil)

        guard rc == SQLITE_OK, let db = handle else {
            if let handle {
                sqlite3_close(handle)
            }
            return nil
        }

        defer { sqlite3_close(db) }
        return operation(db)
    }

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
