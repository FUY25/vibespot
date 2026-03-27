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
        id: String,
        tool: String,
        title: String,
        project: String,
        projectName: String,
        gitBranch: String,
        status: String,
        startedAt: Date,
        pid: Int?
    ) throws {
        let sql = """
            INSERT INTO sessions (
                id, tool, title, project, project_name, git_branch, status, started_at, pid, updated_at
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10
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
                updated_at = excluded.updated_at
        """

        try runStatement(sql) { statement in
            try statement.bind(index: 1, text: id)
            try statement.bind(index: 2, text: tool)
            try statement.bind(index: 3, text: title)
            try statement.bind(index: 4, text: project)
            try statement.bind(index: 5, text: projectName)
            try statement.bind(index: 6, text: gitBranch)
            try statement.bind(index: 7, text: status)
            try statement.bind(index: 8, double: startedAt.timeIntervalSince1970)
            if let pid {
                try statement.bind(index: 9, int: Int64(pid))
            }
            try statement.bind(index: 10, double: Date().timeIntervalSince1970)
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
            SELECT id, tool, title, project, project_name, git_branch, status, started_at, pid, NULL AS snippet
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
                snippet(transcripts, 2, '>>>', '<<<', '...', 16) AS snippet
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
                NULL AS snippet
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

    private func listSessions(liveOnly: Bool) throws -> [SearchResult] {
        let sql = """
            SELECT id, tool, title, project, project_name, git_branch, status, started_at, pid, NULL AS snippet
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
        SearchResult(
            sessionId: textColumn(statement, index: 0),
            tool: textColumn(statement, index: 1),
            title: textColumn(statement, index: 2),
            project: textColumn(statement, index: 3),
            projectName: textColumn(statement, index: 4),
            gitBranch: textColumn(statement, index: 5),
            status: textColumn(statement, index: 6),
            startedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
            pid: sqlite3_column_type(statement, 8) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, 8)),
            snippet: optionalTextColumn(statement, index: 9)
        )
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
}
