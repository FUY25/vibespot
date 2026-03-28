import Foundation
import SQLite3

struct SearchResult: Sendable {
    let sessionId: String
    let tool: String
    let title: String
    let project: String
    let projectName: String
    let gitBranch: String
    let status: String
    let startedAt: Date
    let pid: Int?
    let tokenCount: Int
    let lastActivityAt: Date
    let activityPreview: ActivityPreview?
    let activityStatus: SessionActivityStatus
    let snippet: String?
    let healthStatus: String
    let healthDetail: String

    init(
        sessionId: String,
        tool: String,
        title: String,
        project: String,
        projectName: String,
        gitBranch: String,
        status: String,
        startedAt: Date,
        pid: Int?,
        tokenCount: Int,
        lastActivityAt: Date,
        activityPreview: ActivityPreview?,
        activityStatus: SessionActivityStatus,
        snippet: String? = nil,
        healthStatus: String = "ok",
        healthDetail: String = ""
    ) {
        self.sessionId = sessionId
        self.tool = tool
        self.title = title
        self.project = project
        self.projectName = projectName
        self.gitBranch = gitBranch
        self.status = status
        self.startedAt = startedAt
        self.pid = pid
        self.tokenCount = tokenCount
        self.lastActivityAt = lastActivityAt
        self.activityPreview = activityPreview
        self.activityStatus = activityStatus
        self.snippet = snippet
        self.healthStatus = healthStatus
        self.healthDetail = healthDetail
    }
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
                token_count INTEGER NOT NULL DEFAULT 0,
                last_activity_at REAL,
                last_file_mod REAL,
                last_entry_type TEXT,
                activity_preview TEXT,
                activity_preview_kind TEXT,
                updated_at REAL NOT NULL DEFAULT 0
            )
        """)

        try ensureSessionColumnExists(name: "token_count", definition: "INTEGER NOT NULL DEFAULT 0")
        try ensureSessionColumnExists(name: "last_activity_at", definition: "REAL")
        try ensureSessionColumnExists(name: "last_file_mod", definition: "REAL")
        try ensureSessionColumnExists(name: "last_entry_type", definition: "TEXT")
        try ensureSessionColumnExists(name: "activity_preview", definition: "TEXT")
        try ensureSessionColumnExists(name: "activity_preview_kind", definition: "TEXT")
        try ensureSessionColumnExists(name: "last_indexed_mtime", definition: "REAL")
        try ensureSessionColumnExists(name: "health_status", definition: "TEXT NOT NULL DEFAULT 'ok'")
        try ensureSessionColumnExists(name: "health_detail", definition: "TEXT NOT NULL DEFAULT ''")

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
        id: String,
        tool: String,
        title: String,
        project: String,
        projectName: String,
        gitBranch: String,
        status: String,
        startedAt: Date,
        pid: Int?,
        tokenCount: Int = 0,
        lastActivityAt: Date? = nil,
        lastFileModification: Date? = nil,
        lastEntryType: String? = nil,
        activityPreview: ActivityPreview? = nil,
        lastIndexedMtime: Date? = nil
    ) throws {
        // Storage invariant: session titles in SQLite are always ANSI-free and reasonably sized.
        // Call sites may pre-clean, but `upsertSession` is the source of truth.
        let cleanedTitle = Self.cleanTitle(title)
        let sql = """
            INSERT INTO sessions (
                id, tool, title, project, project_name, git_branch, status, started_at, pid,
                token_count, last_activity_at, last_file_mod, last_entry_type, activity_preview,
                activity_preview_kind, updated_at, last_indexed_mtime
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17
            )
            ON CONFLICT(id) DO UPDATE SET
                tool = excluded.tool,
                title = excluded.title,
                project = excluded.project,
                project_name = excluded.project_name,
                git_branch = excluded.git_branch,
                status = excluded.status,
                started_at = excluded.started_at,
                pid = excluded.pid,
                token_count = excluded.token_count,
                last_activity_at = excluded.last_activity_at,
                last_file_mod = excluded.last_file_mod,
                last_entry_type = excluded.last_entry_type,
                activity_preview = excluded.activity_preview,
                activity_preview_kind = excluded.activity_preview_kind,
                updated_at = excluded.updated_at,
                last_indexed_mtime = COALESCE(excluded.last_indexed_mtime, sessions.last_indexed_mtime)
        """

        try runStatement(sql) { statement in
            try statement.bind(index: 1, text: id)
            try statement.bind(index: 2, text: tool)
            try statement.bind(index: 3, text: cleanedTitle)
            try statement.bind(index: 4, text: project)
            try statement.bind(index: 5, text: projectName)
            try statement.bind(index: 6, text: gitBranch)
            try statement.bind(index: 7, text: status)
            try statement.bind(index: 8, double: startedAt.timeIntervalSince1970)
            if let pid {
                try statement.bind(index: 9, int: Int64(pid))
            } else {
                try statement.bindNull(index: 9)
            }
            try statement.bind(index: 10, int: Int64(tokenCount))
            if let lastActivityAt {
                try statement.bind(index: 11, double: lastActivityAt.timeIntervalSince1970)
            } else {
                try statement.bindNull(index: 11)
            }
            if let lastFileModification {
                try statement.bind(index: 12, double: lastFileModification.timeIntervalSince1970)
            } else {
                try statement.bindNull(index: 12)
            }
            if let lastEntryType {
                try statement.bind(index: 13, text: lastEntryType)
            } else {
                try statement.bindNull(index: 13)
            }
            if let activityPreview {
                try statement.bind(index: 14, text: activityPreview.text)
                try statement.bind(index: 15, text: activityPreview.kind.rawValue)
            } else {
                try statement.bindNull(index: 14)
                try statement.bindNull(index: 15)
            }
            try statement.bind(index: 16, double: Date().timeIntervalSince1970)
            if let lastIndexedMtime {
                try statement.bind(index: 17, double: lastIndexedMtime.timeIntervalSince1970)
            } else {
                try statement.bindNull(index: 17)
            }
        }
    }

    func insertTranscript(sessionId: String, role: String, content: String, timestamp: Date) throws {
        try runStatement(
            "INSERT INTO transcripts (session_id, role, content, timestamp_str) VALUES (?1, ?2, ?3, ?4)"
        ) { statement in
            try statement.bind(index: 1, text: sessionId)
            try statement.bind(index: 2, text: role)
            try statement.bind(index: 3, text: content)
            try statement.bind(index: 4, text: makeTimestampString(from: timestamp))
        }
    }

    func replaceTranscripts(
        sessionId: String,
        entries: [(role: String, content: String, timestamp: Date)]
    ) throws {
        try db.transaction {
            try runStatement("DELETE FROM transcripts WHERE session_id = ?1") { statement in
                try statement.bind(index: 1, text: sessionId)
            }

            for entry in entries {
                try insertTranscript(
                    sessionId: sessionId,
                    role: entry.role,
                    content: entry.content,
                    timestamp: entry.timestamp
                )
            }
        }
    }

    func search(query: String, liveOnly: Bool = false) throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return try listSessions(liveOnly: liveOnly)
        }

        let statusClause = liveOnly ? "AND status = 'live'" : ""
        let metadataSQL = """
            SELECT
                id, tool, title, project, project_name, git_branch, status, started_at, pid,
                token_count, last_activity_at, last_file_mod, last_entry_type, activity_preview,
                activity_preview_kind, NULL AS snippet, health_status, health_detail
            FROM sessions
            WHERE (
                title LIKE ?1 ESCAPE '\\' OR
                project LIKE ?1 ESCAPE '\\' OR
                project_name LIKE ?1 ESCAPE '\\' OR
                tool LIKE ?1 ESCAPE '\\' OR
                git_branch LIKE ?1 ESCAPE '\\'
            )
            \(statusClause)
            ORDER BY CASE status WHEN 'live' THEN 0 ELSE 1 END, started_at DESC
            LIMIT 50
        """

        let transcriptSQL = """
            WITH ranked_matches AS (
                SELECT
                    transcripts.rowid AS transcript_rowid,
                    transcripts.session_id,
                    CASE s.status WHEN 'live' THEN 0 ELSE 1 END AS status_priority,
                    s.started_at AS session_started_at,
                    transcripts.timestamp_str AS transcript_timestamp,
                    rank AS match_rank
                FROM transcripts
                JOIN sessions s ON s.id = transcripts.session_id
                WHERE transcripts MATCH ?1
                \(liveOnly ? "AND s.status = 'live'" : "")
            ),
            session_matches AS (
                SELECT
                    transcript_rowid,
                    session_id,
                    status_priority,
                    session_started_at,
                    transcript_timestamp,
                    match_rank,
                    ROW_NUMBER() OVER (
                        PARTITION BY session_id
                        ORDER BY match_rank, transcript_timestamp DESC, transcript_rowid DESC
                    ) AS match_row_number
                FROM ranked_matches
            ),
            deduplicated_matches AS (
                SELECT
                    transcript_rowid,
                    session_id,
                    status_priority,
                    session_started_at,
                    transcript_timestamp,
                    match_rank
                FROM session_matches
                WHERE match_row_number = 1
                ORDER BY
                    status_priority,
                    match_rank,
                    session_started_at DESC,
                    transcript_timestamp DESC,
                    transcript_rowid DESC
                LIMIT 50
            )
            SELECT
                deduplicated_matches.session_id,
                s.tool,
                s.title,
                s.project,
                s.project_name,
                s.git_branch,
                s.status,
                s.started_at,
                s.pid,
                s.token_count,
                s.last_activity_at,
                s.last_file_mod,
                s.last_entry_type,
                s.activity_preview,
                s.activity_preview_kind,
                snippet(transcripts, 2, '>>>', '<<<', '...', 16) AS snippet,
                s.health_status,
                s.health_detail
            FROM deduplicated_matches
            JOIN transcripts ON transcripts.rowid = deduplicated_matches.transcript_rowid
            JOIN sessions s ON s.id = deduplicated_matches.session_id
            WHERE transcripts MATCH ?1
            ORDER BY
                deduplicated_matches.status_priority,
                deduplicated_matches.match_rank,
                deduplicated_matches.session_started_at DESC,
                deduplicated_matches.transcript_timestamp DESC,
                deduplicated_matches.transcript_rowid DESC
        """

        let literalTranscriptSQL = """
            WITH session_matches AS (
                SELECT
                    s.id AS session_id,
                    s.tool,
                    s.title,
                    s.project,
                    s.project_name,
                    s.git_branch,
                    s.status,
                    s.started_at,
                    s.pid,
                    s.token_count,
                    s.last_activity_at,
                    s.last_file_mod,
                    s.last_entry_type,
                    s.activity_preview,
                    s.activity_preview_kind,
                    s.health_status,
                    s.health_detail,
                    ROW_NUMBER() OVER (
                        PARTITION BY s.id
                        ORDER BY transcripts.timestamp_str DESC, transcripts.rowid DESC
                    ) AS match_row_number
                FROM transcripts
                JOIN sessions s ON s.id = transcripts.session_id
                WHERE transcripts.content LIKE ?1 ESCAPE '\\'
                \(liveOnly ? "AND s.status = 'live'" : "")
            )
            SELECT
                session_id,
                tool,
                title,
                project,
                project_name,
                git_branch,
                status,
                started_at,
                pid,
                token_count,
                last_activity_at,
                last_file_mod,
                last_entry_type,
                activity_preview,
                activity_preview_kind,
                NULL AS snippet,
                health_status,
                health_detail
            FROM session_matches
            WHERE match_row_number = 1
            ORDER BY CASE status WHEN 'live' THEN 0 ELSE 1 END, started_at DESC
            LIMIT 50
        """

        let transcriptMatches: [SearchResult]
        if let ftsQuery = makeFTSQuery(from: trimmed) {
            transcriptMatches = try db.query(
                transcriptSQL,
                bind: { statement in
                    try statement.bind(index: 1, text: ftsQuery)
                },
                map: mapRow
            )
        } else if shouldUseLiteralTranscriptFallback(for: trimmed) {
            transcriptMatches = try db.query(
                literalTranscriptSQL,
                bind: { statement in
                    try statement.bind(index: 1, text: makeMetadataPattern(from: trimmed))
                },
                map: mapRow
            )
        } else {
            transcriptMatches = []
        }

        var results = transcriptMatches
        var seenIDs = Set(transcriptMatches.map(\.sessionId))
        let metadataMatches = try db.query(
            metadataSQL,
            bind: { statement in
                try statement.bind(index: 1, text: makeMetadataPattern(from: trimmed))
            },
            map: mapRow
        )

        for result in metadataMatches where !seenIDs.contains(result.sessionId) {
            results.append(result)
            seenIDs.insert(result.sessionId)

            if results.count == 50 {
                break
            }
        }

        return Array(results.prefix(50))
    }

    func search(query: String, includeHistory: Bool) throws -> [SearchResult] {
        try search(query: query, liveOnly: !includeHistory)
    }

    func liveSessionCount() throws -> Int {
        let counts = try db.query("SELECT COUNT(*) FROM sessions WHERE status = 'live'") { statement in
            Int(sqlite3_column_int64(statement, 0))
        }
        return counts.first ?? 0
    }

    func liveSessionIDs() throws -> Set<String> {
        let ids = try db.query("SELECT id FROM sessions WHERE status = 'live'") { statement in
            textColumn(statement, index: 0)
        }
        return Set(ids)
    }

    func startedAtBySessionID(_ sessionIDs: Set<String>) throws -> [String: Date] {
        guard !sessionIDs.isEmpty else {
            return [:]
        }

        let orderedIDs = Array(sessionIDs).sorted()
        let placeholders = (1...orderedIDs.count).map { "?\($0)" }.joined(separator: ", ")
        let sql = "SELECT id, started_at FROM sessions WHERE id IN (\(placeholders))"

        let rows = try db.query(
            sql,
            bind: { statement in
                for (offset, sessionID) in orderedIDs.enumerated() {
                    try statement.bind(index: Int32(offset + 1), text: sessionID)
                }
            },
            map: { statement in
                (
                    id: textColumn(statement, index: 0),
                    startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
                )
            }
        )

        var startedAtBySessionID: [String: Date] = [:]
        startedAtBySessionID.reserveCapacity(rows.count)
        for row in rows {
            startedAtBySessionID[row.id] = row.startedAt
        }
        return startedAtBySessionID
    }

    func mostRecentProject() throws -> (project: String, projectName: String)? {
        let rows = try db.query(
            """
            SELECT project, project_name
            FROM sessions
            WHERE TRIM(project) <> ''
            ORDER BY COALESCE(last_activity_at, started_at, updated_at) DESC,
                     started_at DESC,
                     updated_at DESC,
                     id DESC
            LIMIT 1
            """
        ) { statement in
            (project: textColumn(statement, index: 0), projectName: textColumn(statement, index: 1))
        }
        return rows.first
    }

    func lastIndexedMtime(sessionId: String) throws -> Date? {
        let results = try db.query(
            "SELECT last_indexed_mtime FROM sessions WHERE id = ?1",
            bind: { statement in
                try statement.bind(index: 1, text: sessionId)
            },
            map: { statement -> Date? in
                guard sqlite3_column_type(statement, 0) != SQLITE_NULL else { return nil }
                return Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
            }
        )
        return results.first ?? nil
    }

    func updateStatus(sessionId: String, status: String) throws {
        try updateRuntimeState(sessionId: sessionId, status: status, pid: nil)
    }

    func updateRuntimeState(sessionId: String, status: String, pid: Int?) throws {
        try runStatement(
            "UPDATE sessions SET status = ?1, pid = ?2, updated_at = ?3 WHERE id = ?4"
        ) { statement in
            try statement.bind(index: 1, text: status)
            if let pid {
                try statement.bind(index: 2, int: Int64(pid))
            }
            try statement.bind(index: 3, int: Int64(Date().timeIntervalSince1970))
            try statement.bind(index: 4, text: sessionId)
        }
    }

    func updateHealthStatus(sessionId: String, healthStatus: String, healthDetail: String) throws {
        try runStatement(
            "UPDATE sessions SET health_status = ?1, health_detail = ?2, updated_at = ?3 WHERE id = ?4"
        ) { statement in
            try statement.bind(index: 1, text: healthStatus)
            try statement.bind(index: 2, text: healthDetail)
            try statement.bind(index: 3, double: Date().timeIntervalSince1970)
            try statement.bind(index: 4, text: sessionId)
        }
    }

    private func listSessions(liveOnly: Bool) throws -> [SearchResult] {
        let sql = """
            SELECT
                id, tool, title, project, project_name, git_branch, status, started_at, pid,
                token_count, last_activity_at, last_file_mod, last_entry_type, activity_preview,
                activity_preview_kind, NULL AS snippet, health_status, health_detail
            FROM sessions
            \(liveOnly ? "WHERE status = 'live'" : "")
            ORDER BY CASE status WHEN 'live' THEN 0 ELSE 1 END, started_at DESC
            LIMIT 50
        """

        return try db.query(sql, map: mapRow)
    }

    private func runStatement(
        _ sql: String,
        bind: (Database.Statement) throws -> Void
    ) throws {
        let statement = try db.prepare(sql)
        try bind(statement)
        let result = statement.step()

        guard result == SQLITE_DONE else {
            throw DatabaseError.stepFailed(statement.connectionErrorMessage())
        }
    }

    private func makeMetadataPattern(from query: String) -> String {
        "%\(escapeLikeLiteral(query))%"
    }

    private func escapeLikeLiteral(_ text: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(text.count)

        for character in text {
            if character == "\\" || character == "%" || character == "_" {
                escaped.append("\\")
            }
            escaped.append(character)
        }

        return escaped
    }

    private func makeFTSQuery(from query: String) -> String? {
        let safeTerms = query
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }

        guard !safeTerms.isEmpty else {
            return nil
        }

        guard normalizeForFTSComparison(query) == safeTerms.joined(separator: " ") else {
            return nil
        }

        let contentTerms = safeTerms
            .map { token in
                "\"\(token.replacing("\"", with: "\"\""))\""
            }
            .joined(separator: " ")

        return "content : (\(contentTerms))"
    }

    private func normalizeForFTSComparison(_ query: String) -> String {
        query
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func shouldUseLiteralTranscriptFallback(for query: String) -> Bool {
        var containsPunctuation = false

        for scalar in query.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }

            if !CharacterSet.alphanumerics.contains(scalar) {
                containsPunctuation = true
            }
        }

        return containsPunctuation
    }

    private func makeTimestampString(from timestamp: Date) -> String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: timestamp)
    }

    private func mapRow(_ statement: OpaquePointer) -> SearchResult {
        let startedAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
        let lastActivityAt = sqlite3_column_type(statement, 10) == SQLITE_NULL
            ? startedAt
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 10))
        let lastFileModification = sqlite3_column_type(statement, 11) == SQLITE_NULL
            ? lastActivityAt
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 11))
        let activityPreview = previewColumn(statement, textIndex: 13, kindIndex: 14)
        let status = textColumn(statement, index: 6)
        let snippet = optionalTextColumn(statement, index: 15)
        let healthStatus = optionalTextColumn(statement, index: 16) ?? "ok"
        let healthDetail = optionalTextColumn(statement, index: 17) ?? ""
        return SearchResult(
            sessionId: textColumn(statement, index: 0),
            tool: textColumn(statement, index: 1),
            title: textColumn(statement, index: 2),
            project: textColumn(statement, index: 3),
            projectName: textColumn(statement, index: 4),
            gitBranch: textColumn(statement, index: 5),
            status: status,
            startedAt: startedAt,
            pid: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 8)),
            tokenCount: Int(sqlite3_column_int64(statement, 9)),
            lastActivityAt: lastActivityAt,
            activityPreview: activityPreview,
            activityStatus: SessionActivityStatus.determine(
                sessionStatus: status,
                lastFileModification: lastFileModification,
                lastJSONLEntryType: optionalTextColumn(statement, index: 12)
            ),
            snippet: snippet,
            healthStatus: healthStatus,
            healthDetail: healthDetail
        )
    }

    private func ensureSessionColumnExists(name: String, definition: String) throws {
        let existingColumns = try db.query("PRAGMA table_info(sessions)") { statement in
            textColumn(statement, index: 1)
        }

        guard !existingColumns.contains(name) else {
            return
        }

        try db.execute("ALTER TABLE sessions ADD COLUMN \(name) \(definition)")
    }

    private func textColumn(_ statement: OpaquePointer, index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else {
            return ""
        }
        return String(cString: value)
    }

    private func optionalTextColumn(_ statement: OpaquePointer, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
            return nil
        }
        return textColumn(statement, index: index)
    }

    private func previewColumn(_ statement: OpaquePointer, textIndex: Int32, kindIndex: Int32) -> ActivityPreview? {
        guard
            let text = optionalTextColumn(statement, index: textIndex),
            let rawKind = optionalTextColumn(statement, index: kindIndex),
            let kind = ActivityPreview.Kind(rawValue: rawKind)
        else {
            return nil
        }

        return ActivityPreview(text: text, kind: kind)
    }

    // MARK: - Title cleaning

    static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(
            of: "\u{001b}\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
    }

    static func smartTruncate(_ text: String, maxLength: Int = 60) -> String {
        let stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.count > maxLength else { return stripped }
        if stripped.last == "?" {
            // Preserve a trailing question mark, while still preferring a word boundary.
            // We reserve 1 character of the budget to add "…?" (2 chars) while keeping
            // the default output length <= maxLength + 1 (60 -> 61).
            let questionPrefix = String(stripped.prefix(maxLength - 1))
            if let lastSpace = questionPrefix.lastIndex(of: " ") {
                let cut = questionPrefix[..<lastSpace]
                if !cut.isEmpty {
                    return String(cut) + "…?"
                }
            }
            return questionPrefix + "…?"
        }
        let truncated = String(stripped.prefix(maxLength))
        if let lastSpace = truncated.lastIndex(of: " ") {
            return String(truncated[..<lastSpace]) + "…"
        }
        return truncated + "…"
    }

    static func cleanTitle(_ rawTitle: String) -> String {
        smartTruncate(stripANSI(rawTitle))
    }
}
