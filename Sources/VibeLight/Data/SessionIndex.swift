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
    let effectiveModel: String?
    let contextWindowTokens: Int?
    let contextUsedEstimate: Int?
    let contextPercentEstimate: Int?
    let contextConfidence: ContextConfidence
    let contextSource: String?
    let lastContextSampleAt: Date?

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
        healthDetail: String = "",
        effectiveModel: String? = nil,
        contextWindowTokens: Int? = nil,
        contextUsedEstimate: Int? = nil,
        contextPercentEstimate: Int? = nil,
        contextConfidence: ContextConfidence = .unknown,
        contextSource: String? = nil,
        lastContextSampleAt: Date? = nil
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
        self.effectiveModel = effectiveModel
        self.contextWindowTokens = contextWindowTokens
        self.contextUsedEstimate = contextUsedEstimate
        self.contextPercentEstimate = contextPercentEstimate
        self.contextConfidence = contextConfidence
        self.contextSource = contextSource
        self.lastContextSampleAt = lastContextSampleAt
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
                effective_model TEXT,
                context_window_tokens INTEGER,
                context_used_estimate INTEGER,
                context_percent_estimate INTEGER,
                context_confidence TEXT NOT NULL DEFAULT 'unknown',
                context_source TEXT,
                last_context_sample_at REAL,
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
        try ensureSessionColumnExists(name: "effective_model", definition: "TEXT")
        try ensureSessionColumnExists(name: "context_window_tokens", definition: "INTEGER")
        try ensureSessionColumnExists(name: "context_used_estimate", definition: "INTEGER")
        try ensureSessionColumnExists(name: "context_percent_estimate", definition: "INTEGER")
        try ensureSessionColumnExists(name: "context_confidence", definition: "TEXT NOT NULL DEFAULT 'unknown'")
        try ensureSessionColumnExists(name: "context_source", definition: "TEXT")
        try ensureSessionColumnExists(name: "last_context_sample_at", definition: "REAL")

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
        lastIndexedMtime: Date? = nil,
        telemetry: SessionContextTelemetry?
    ) throws {
        // Storage invariant: session titles in SQLite are always ANSI-free and reasonably sized.
        // Call sites may pre-clean, but `upsertSession` is the source of truth.
        let cleanedTitle = Self.cleanTitle(title)
        let telemetryWasProvided = telemetry != nil
        let sql = """
            INSERT INTO sessions (
                id, tool, title, project, project_name, git_branch, status, started_at, pid,
                token_count, last_activity_at, last_file_mod, last_entry_type, activity_preview,
                activity_preview_kind, updated_at, last_indexed_mtime, effective_model,
                context_window_tokens, context_used_estimate, context_percent_estimate,
                context_confidence, context_source, last_context_sample_at
            ) VALUES (
                ?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17,
                ?18, ?19, ?20, ?21, COALESCE(?22, 'unknown'), ?23, ?24
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
                last_indexed_mtime = COALESCE(excluded.last_indexed_mtime, sessions.last_indexed_mtime),
                effective_model = CASE WHEN ?25 = 1 THEN excluded.effective_model ELSE sessions.effective_model END,
                context_window_tokens = CASE WHEN ?25 = 1 THEN excluded.context_window_tokens ELSE sessions.context_window_tokens END,
                context_used_estimate = CASE WHEN ?25 = 1 THEN excluded.context_used_estimate ELSE sessions.context_used_estimate END,
                context_percent_estimate = CASE WHEN ?25 = 1 THEN excluded.context_percent_estimate ELSE sessions.context_percent_estimate END,
                context_confidence = CASE WHEN ?25 = 1 THEN excluded.context_confidence ELSE sessions.context_confidence END,
                context_source = CASE WHEN ?25 = 1 THEN excluded.context_source ELSE sessions.context_source END,
                last_context_sample_at = CASE WHEN ?25 = 1 THEN excluded.last_context_sample_at ELSE sessions.last_context_sample_at END
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
            if let effectiveModel = telemetry?.effectiveModel {
                try statement.bind(index: 18, text: effectiveModel)
            } else {
                try statement.bindNull(index: 18)
            }
            if let contextWindowTokens = telemetry?.contextWindowTokens {
                try statement.bind(index: 19, int: Int64(contextWindowTokens))
            } else {
                try statement.bindNull(index: 19)
            }
            if let contextUsedEstimate = telemetry?.contextUsedEstimate {
                try statement.bind(index: 20, int: Int64(contextUsedEstimate))
            } else {
                try statement.bindNull(index: 20)
            }
            if let contextPercentEstimate = telemetry?.contextPercentEstimate {
                try statement.bind(index: 21, int: Int64(contextPercentEstimate))
            } else {
                try statement.bindNull(index: 21)
            }
            if let contextConfidence = telemetry?.contextConfidence {
                try statement.bind(index: 22, text: contextConfidence.rawValue)
            } else {
                try statement.bindNull(index: 22)
            }
            if let contextSource = telemetry?.contextSource {
                try statement.bind(index: 23, text: contextSource)
            } else {
                try statement.bindNull(index: 23)
            }
            if let lastContextSampleAt = telemetry?.lastContextSampleAt {
                try statement.bind(index: 24, double: lastContextSampleAt.timeIntervalSince1970)
            } else {
                try statement.bindNull(index: 24)
            }
            try statement.bind(index: 25, int: telemetryWasProvided ? 1 : 0)
        }
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
        lastIndexedMtime: Date? = nil,
        effectiveModel: String? = nil,
        contextWindowTokens: Int? = nil,
        contextUsedEstimate: Int? = nil,
        contextPercentEstimate: Int? = nil,
        contextConfidence: ContextConfidence? = nil,
        contextSource: String? = nil,
        lastContextSampleAt: Date? = nil
    ) throws {
        let telemetryWasProvided =
            effectiveModel != nil ||
            contextWindowTokens != nil ||
            contextUsedEstimate != nil ||
            contextPercentEstimate != nil ||
            contextConfidence != nil ||
            contextSource != nil ||
            lastContextSampleAt != nil

        let telemetry = telemetryWasProvided
            ? SessionContextTelemetry(
                effectiveModel: effectiveModel,
                contextWindowTokens: contextWindowTokens,
                contextUsedEstimate: contextUsedEstimate,
                contextPercentEstimate: contextPercentEstimate,
                contextConfidence: contextConfidence ?? .unknown,
                contextSource: contextSource,
                lastContextSampleAt: lastContextSampleAt
            )
            : nil

        try upsertSession(
            id: id,
            tool: tool,
            title: title,
            project: project,
            projectName: projectName,
            gitBranch: gitBranch,
            status: status,
            startedAt: startedAt,
            pid: pid,
            tokenCount: tokenCount,
            lastActivityAt: lastActivityAt,
            lastFileModification: lastFileModification,
            lastEntryType: lastEntryType,
            activityPreview: activityPreview,
            lastIndexedMtime: lastIndexedMtime,
            telemetry: telemetry
        )
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
                activity_preview_kind, NULL AS snippet, health_status, health_detail,
                effective_model, context_window_tokens, context_used_estimate, context_percent_estimate,
                context_confidence, context_source, last_context_sample_at
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
                s.health_detail,
                s.effective_model,
                s.context_window_tokens,
                s.context_used_estimate,
                s.context_percent_estimate,
                s.context_confidence,
                s.context_source,
                s.last_context_sample_at
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
                    s.effective_model,
                    s.context_window_tokens,
                    s.context_used_estimate,
                    s.context_percent_estimate,
                    s.context_confidence,
                    s.context_source,
                    s.last_context_sample_at,
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
                health_detail,
                effective_model,
                context_window_tokens,
                context_used_estimate,
                context_percent_estimate,
                context_confidence,
                context_source,
                last_context_sample_at
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

    func ensureSessionExists(
        id: String,
        tool: String,
        project: String,
        projectName: String,
        startedAt: Date
    ) throws {
        let sql = """
            INSERT OR IGNORE INTO sessions (
                id, tool, title, project, project_name, git_branch, status, started_at, updated_at
            ) VALUES (?1, ?2, ?3, ?4, ?5, '', 'live', ?6, ?7)
        """
        try runStatement(sql) { statement in
            try statement.bind(index: 1, text: id)
            try statement.bind(index: 2, text: tool)
            try statement.bind(index: 3, text: projectName.isEmpty ? "Untitled" : projectName)
            try statement.bind(index: 4, text: project)
            try statement.bind(index: 5, text: projectName)
            try statement.bind(index: 6, double: startedAt.timeIntervalSince1970)
            try statement.bind(index: 7, double: Date().timeIntervalSince1970)
        }
    }

    func updateActivityFields(sessionId: String, lastFileModification: Date, lastEntryType: String?) throws {
        if let lastEntryType {
            try runStatement(
                "UPDATE sessions SET last_file_mod = ?1, last_entry_type = ?2, updated_at = ?3 WHERE id = ?4"
            ) { statement in
                try statement.bind(index: 1, double: lastFileModification.timeIntervalSince1970)
                try statement.bind(index: 2, text: lastEntryType)
                try statement.bind(index: 3, double: Date().timeIntervalSince1970)
                try statement.bind(index: 4, text: sessionId)
            }
        } else {
            try runStatement(
                "UPDATE sessions SET last_file_mod = ?1, updated_at = ?2 WHERE id = ?3"
            ) { statement in
                try statement.bind(index: 1, double: lastFileModification.timeIntervalSince1970)
                try statement.bind(index: 2, double: Date().timeIntervalSince1970)
                try statement.bind(index: 3, text: sessionId)
            }
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

    func updateTelemetry(sessionId: String, telemetry: SessionContextTelemetry, lastIndexedMtime: Date?) throws {
        let sql = """
            UPDATE sessions
            SET effective_model = ?1,
                context_window_tokens = ?2,
                context_used_estimate = ?3,
                context_percent_estimate = ?4,
                context_confidence = ?5,
                context_source = ?6,
                last_context_sample_at = ?7,
                last_indexed_mtime = COALESCE(?8, last_indexed_mtime),
                updated_at = ?9
            WHERE id = ?10
        """

        try runStatement(sql) { statement in
            if let effectiveModel = telemetry.effectiveModel {
                try statement.bind(index: 1, text: effectiveModel)
            } else {
                try statement.bindNull(index: 1)
            }
            if let contextWindowTokens = telemetry.contextWindowTokens {
                try statement.bind(index: 2, int: Int64(contextWindowTokens))
            } else {
                try statement.bindNull(index: 2)
            }
            if let contextUsedEstimate = telemetry.contextUsedEstimate {
                try statement.bind(index: 3, int: Int64(contextUsedEstimate))
            } else {
                try statement.bindNull(index: 3)
            }
            if let contextPercentEstimate = telemetry.contextPercentEstimate {
                try statement.bind(index: 4, int: Int64(contextPercentEstimate))
            } else {
                try statement.bindNull(index: 4)
            }
            try statement.bind(index: 5, text: telemetry.contextConfidence.rawValue)
            if let contextSource = telemetry.contextSource {
                try statement.bind(index: 6, text: contextSource)
            } else {
                try statement.bindNull(index: 6)
            }
            if let lastContextSampleAt = telemetry.lastContextSampleAt {
                try statement.bind(index: 7, double: lastContextSampleAt.timeIntervalSince1970)
            } else {
                try statement.bindNull(index: 7)
            }
            if let lastIndexedMtime {
                try statement.bind(index: 8, double: lastIndexedMtime.timeIntervalSince1970)
            } else {
                try statement.bindNull(index: 8)
            }
            try statement.bind(index: 9, double: Date().timeIntervalSince1970)
            try statement.bind(index: 10, text: sessionId)
        }
    }

    func updateTitle(sessionId: String, title: String) throws {
        let cleaned = Self.cleanTitle(title)
        try runStatement(
            "UPDATE sessions SET title = ?1, updated_at = ?2 WHERE id = ?3"
        ) { statement in
            try statement.bind(index: 1, text: cleaned)
            try statement.bind(index: 2, double: Date().timeIntervalSince1970)
            try statement.bind(index: 3, text: sessionId)
        }
    }

    func currentTitle(sessionId: String) throws -> String? {
        let rows = try db.query(
            "SELECT title FROM sessions WHERE id = ?1",
            bind: { statement in
                try statement.bind(index: 1, text: sessionId)
            },
            map: { statement in
                textColumn(statement, index: 0)
            }
        )
        return rows.first
    }

    /// Returns sessions whose title matches their project_name, is "Untitled", or is empty.
    func sessionsWithWeakTitles(limit: Int = 50) throws -> [(sessionId: String, tool: String, projectName: String)] {
        let sql = """
            SELECT id, tool, project_name
            FROM sessions
            WHERE title = project_name
               OR title = 'Untitled'
               OR title = ''
            ORDER BY started_at DESC
            LIMIT ?1
        """
        return try db.query(
            sql,
            bind: { statement in
                try statement.bind(index: 1, int: Int64(limit))
            },
            map: { statement in
                (
                    sessionId: textColumn(statement, index: 0),
                    tool: textColumn(statement, index: 1),
                    projectName: textColumn(statement, index: 2)
                )
            }
        )
    }

    private func listSessions(liveOnly: Bool) throws -> [SearchResult] {
        let sql = """
            SELECT
                id, tool, title, project, project_name, git_branch, status, started_at, pid,
                token_count, last_activity_at, last_file_mod, last_entry_type, activity_preview,
                activity_preview_kind, NULL AS snippet, health_status, health_detail,
                effective_model, context_window_tokens, context_used_estimate, context_percent_estimate,
                context_confidence, context_source, last_context_sample_at
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

    private static let cjkRanges: [ClosedRange<UInt32>] = [
        0x4E00...0x9FFF,    // CJK Unified Ideographs
        0x3400...0x4DBF,    // CJK Extension A
        0x20000...0x2A6DF,  // CJK Extension B
        0x2A700...0x2B73F,  // CJK Extension C
        0x2B740...0x2B81F,  // CJK Extension D
        0x3000...0x303F,    // CJK Symbols and Punctuation
        0x3040...0x309F,    // Hiragana
        0x30A0...0x30FF,    // Katakana
        0xAC00...0xD7AF,    // Hangul Syllables
    ]

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        let value = scalar.value
        return cjkRanges.contains { $0.contains(value) }
    }

    private func shouldUseLiteralTranscriptFallback(for query: String) -> Bool {
        for scalar in query.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }
            if Self.isCJK(scalar) {
                return true
            }
            if !CharacterSet.alphanumerics.contains(scalar) {
                return true
            }
        }

        return false
    }

    private static nonisolated(unsafe) let iso8601Formatter = ISO8601DateFormatter()

    private func makeTimestampString(from timestamp: Date) -> String {
        Self.iso8601Formatter.string(from: timestamp)
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
        let contextConfidence = ContextConfidence(
            rawValue: optionalTextColumn(statement, index: 22) ?? ContextConfidence.unknown.rawValue
        ) ?? .unknown
        let lastContextSampleAt = sqlite3_column_type(statement, 24) == SQLITE_NULL
            ? nil
            : Date(timeIntervalSince1970: sqlite3_column_double(statement, 24))
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
            healthDetail: healthDetail,
            effectiveModel: optionalTextColumn(statement, index: 18),
            contextWindowTokens: sqlite3_column_type(statement, 19) == SQLITE_NULL
                ? nil
                : Int(sqlite3_column_int64(statement, 19)),
            contextUsedEstimate: sqlite3_column_type(statement, 20) == SQLITE_NULL
                ? nil
                : Int(sqlite3_column_int64(statement, 20)),
            contextPercentEstimate: sqlite3_column_type(statement, 21) == SQLITE_NULL
                ? nil
                : Int(sqlite3_column_int64(statement, 21)),
            contextConfidence: contextConfidence,
            contextSource: optionalTextColumn(statement, index: 23),
            lastContextSampleAt: lastContextSampleAt
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
