import Foundation

@MainActor
final class Indexer {
    let sessionIndex: SessionIndex

    private let homeDirectoryPath: String
    private var fileWatcher: FileWatcher?
    private var refreshTimer: Timer?
    private var titleSweepTimer: Timer?
    private var startupScanTask: Task<Void, Never>?
    private var processedFiles: Set<String> = []
    private var codexTitleMap: [String: String] = [:]
    private var sessionFileURLCache: [String: URL] = [:]
    private var sessionFileLookupMissAt: [String: Date] = [:]
    private var lastTailReadMtimeBySessionId: [String: Date] = [:]

    init(
        sessionIndex: SessionIndex,
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.sessionIndex = sessionIndex
        self.homeDirectoryPath = homeDirectoryPath
    }

    func start() {
        stop()

        let sessionIndex = sessionIndex
        let homeDirectoryPath = homeDirectoryPath
        startupScanTask = Task.detached(priority: .utility) { [weak self] in
            var scanner = IndexScanner(
                sessionIndex: sessionIndex,
                homeDirectoryPath: homeDirectoryPath
            )
            scanner.performFullScan()

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                self?.refreshLiveSessions()
            }
        }

        let watchPaths = [
            homeDirectoryPath + "/.claude",
            homeDirectoryPath + "/.codex",
        ].filter { FileManager.default.fileExists(atPath: $0) }

        if !watchPaths.isEmpty {
            fileWatcher = FileWatcher(paths: watchPaths) { [weak self] changedPaths in
                Task { @MainActor [weak self] in
                    self?.handleChanges(changedPaths)
                }
            }
            fileWatcher?.start()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshLiveSessions()
            }
        }

        // Periodic title improvement sweep every 60s
        titleSweepTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.runTitleSweep()
            }
        }
    }

    func stop() {
        startupScanTask?.cancel()
        startupScanTask = nil

        fileWatcher?.stop()
        fileWatcher = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        titleSweepTimer?.invalidate()
        titleSweepTimer = nil
    }

    // MARK: - Full scan

    func performFullScan() {
        var scanner = IndexScanner(
            sessionIndex: sessionIndex,
            homeDirectoryPath: homeDirectoryPath
        )
        scanner.performFullScan()
        refreshLiveSessions()
    }

    private func scanClaudeSessions() {
        let projectsPath = homeDirectoryPath + "/.claude/projects"
        let fileManager = FileManager.default

        guard let projectDirectories = try? fileManager.contentsOfDirectory(atPath: projectsPath) else {
            return
        }

        for encodedProjectPath in projectDirectories {
            let directoryPath = (projectsPath as NSString).appendingPathComponent(encodedProjectPath)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: directoryPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }

            let decodedProjectPath = ClaudeParser.decodeProjectPath(encodedProjectPath)
            let projectName = (decodedProjectPath as NSString).lastPathComponent
            let projectDirectoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
            let metadataBySessionId = IndexingHelpers.claudeSessionMetadataBySessionId(in: projectDirectoryURL)

            for meta in metadataBySessionId.values {
                guard IndexingHelpers.claudeRawSessionFileExists(sessionId: meta.sessionId, in: projectDirectoryURL) else {
                    continue
                }

                indexClaudeSession(
                    meta: meta,
                    fallbackProjectPath: decodedProjectPath,
                    fallbackProjectName: projectName
                )
            }

            guard let files = try? fileManager.contentsOfDirectory(atPath: directoryPath) else {
                continue
            }

            for file in files where file.hasSuffix(".jsonl") {
                let filePath = (directoryPath as NSString).appendingPathComponent(file)
                let sessionId = (file as NSString).deletingPathExtension
                guard IndexingHelpers.isUUID(sessionId) else {
                    continue
                }

                indexClaudeSessionFile(
                    path: filePath,
                    sessionId: sessionId,
                    projectPath: decodedProjectPath,
                    projectName: projectName,
                    preferredTitle: metadataBySessionId[sessionId]?.title,
                    preferredFirstPrompt: metadataBySessionId[sessionId]?.firstPrompt
                )
            }
        }
    }

    private func indexClaudeSession(
        meta: ParsedSessionMeta,
        fallbackProjectPath: String,
        fallbackProjectName: String
    ) {
        let projectPath = meta.projectPath.isEmpty ? fallbackProjectPath : meta.projectPath
        let projectName = projectPath.isEmpty ? fallbackProjectName : (projectPath as NSString).lastPathComponent
        let title = IndexingHelpers.normalizedDisplayTitle(from: meta.title) ?? "Untitled"

        try? sessionIndex.upsertSession(
            id: meta.sessionId,
            tool: "claude",
            title: SessionIndex.cleanTitle(title),
            project: projectPath,
            projectName: projectName,
            gitBranch: meta.gitBranch,
            status: "closed",
            startedAt: meta.startedAt,
            pid: nil,
            lastActivityAt: meta.startedAt
        )
    }

    private func indexClaudeSessionFile(
        path: String,
        sessionId: String,
        projectPath: String,
        projectName: String,
        preferredTitle: String? = nil,
        preferredFirstPrompt: String? = nil
    ) {
        guard !processedFiles.contains(path) else {
            return
        }
        processedFiles.insert(path)
        if IndexingHelpers.shouldSkipFile(path: path, sessionId: sessionId, sessionIndex: sessionIndex) {
            return
        }
        let mtime = IndexingHelpers.fileMtime(at: path)

        let url = URL(fileURLWithPath: path)
        guard let (messages, telemetry) = try? ClaudeParser.parseSessionFile(url: url) else {
            return
        }

        if messages.isEmpty {
            if let telemetry {
                try? sessionIndex.updateTelemetry(sessionId: sessionId, telemetry: telemetry, lastIndexedMtime: mtime)
            }
            return
        }

        let cwd = messages.lazy.compactMap(\.cwd).first(where: { !$0.isEmpty }) ?? projectPath
        let resolvedProjectName = cwd.isEmpty ? projectName : (cwd as NSString).lastPathComponent
        let gitBranch = messages.lazy.compactMap(\.gitBranch).first(where: { !$0.isEmpty }) ?? ""
        let title = IndexingHelpers.bestSessionTitle(
            externalTitle: preferredTitle,
            firstPromptHint: preferredFirstPrompt,
            messages: messages
        )
        let startedAt = messages.first?.timestamp ?? .distantPast
        let metrics = IndexingHelpers.sessionMetrics(from: messages, filePath: path)

        try? sessionIndex.upsertSession(
            id: sessionId,
            tool: "claude",
            title: SessionIndex.cleanTitle(title),
            project: cwd,
            projectName: resolvedProjectName,
            gitBranch: gitBranch,
            status: "closed",
            startedAt: startedAt,
            pid: nil,
            tokenCount: metrics.tokenCount,
            lastActivityAt: metrics.lastActivityAt,
            lastFileModification: metrics.lastFileModification,
            lastEntryType: metrics.lastEntryType,
            activityPreview: metrics.activityPreview,
            lastIndexedMtime: mtime,
            telemetry: telemetry
        )

        let transcriptEntries = messages.map { message in
            (
                role: message.role,
                content: IndexingHelpers.searchableContent(from: message),
                timestamp: message.timestamp
            )
        }
        try? sessionIndex.replaceTranscripts(sessionId: sessionId, entries: transcriptEntries)
    }

    private func scanCodexSessions() {
        codexTitleMap = IndexingHelpers.loadCodexTitleMap(homeDirectoryPath: homeDirectoryPath)
        let codexGitBranchMap = CodexStateDB().gitBranchMap()

        let sessionsPath = homeDirectoryPath + "/.codex/sessions"
        let fileManager = FileManager.default

        guard
            let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: sessionsPath),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        for case let fileURL as URL in enumerator {
            guard fileURL.pathExtension == "jsonl" else {
                continue
            }

            indexCodexSessionFile(
                path: fileURL.path,
                titleMap: codexTitleMap,
                gitBranchMap: codexGitBranchMap
            )
        }
    }

    private func indexCodexSessionFile(
        path: String,
        titleMap: [String: String],
        gitBranchMap: [String: String]
    ) {
        guard !processedFiles.contains(path) else {
            return
        }
        processedFiles.insert(path)

        // Codex filenames include the session UUID (for example, rollout-...-<uuid>.jsonl).
        // If we can infer it from the path, we can skip unchanged files before full JSONL parsing.
        if let sessionIdFromPath = IndexingHelpers.codexSessionIDFromPath(path),
           IndexingHelpers.shouldSkipFile(path: path, sessionId: sessionIdFromPath, sessionIndex: sessionIndex) {
            return
        }

        let url = URL(fileURLWithPath: path)
        guard let (meta, messages, telemetry) = try? CodexParser.parseSessionFile(url: url) else {
            return
        }
        if meta?.isSubagent == true {
            return
        }

        let metaID = meta?.id.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let sessionId = metaID.isEmpty ? messages.compactMap(\.sessionId).first : metaID
        guard let sessionId, !sessionId.isEmpty else {
            return
        }
        if IndexingHelpers.shouldSkipFile(path: path, sessionId: sessionId, sessionIndex: sessionIndex) {
            return
        }
        let mtime = IndexingHelpers.fileMtime(at: path)

        let title = IndexingHelpers.bestSessionTitle(
            externalTitle: titleMap[sessionId],
            messages: messages
        )
        let cwd = (meta?.cwd ?? messages.compactMap(\.cwd).first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let metrics = IndexingHelpers.sessionMetrics(from: messages, filePath: path)

        try? sessionIndex.upsertSession(
            id: sessionId,
            tool: "codex",
            title: SessionIndex.cleanTitle(title),
            project: cwd,
            projectName: cwd.isEmpty ? "" : (cwd as NSString).lastPathComponent,
            gitBranch: gitBranchMap[sessionId] ?? "",
            status: "closed",
            startedAt: messages.first?.timestamp ?? .distantPast,
            pid: nil,
            tokenCount: metrics.tokenCount,
            lastActivityAt: metrics.lastActivityAt,
            lastFileModification: metrics.lastFileModification,
            lastEntryType: metrics.lastEntryType,
            activityPreview: metrics.activityPreview,
            lastIndexedMtime: mtime,
            telemetry: telemetry
        )

        let transcriptEntries = messages.map { message in
            (
                role: message.role,
                content: IndexingHelpers.searchableContent(from: message),
                timestamp: message.timestamp
            )
        }
        try? sessionIndex.replaceTranscripts(sessionId: sessionId, entries: transcriptEntries)
    }

    // MARK: - Live sessions

    /// Given a list of (sessionId, pid, startedAt) tuples, returns session IDs
    /// that should be marked "closed" because a newer session shares their PID.
    nonisolated static func sessionIDsToCloseByPID(
        sessions: [(sessionId: String, pid: Int, startedAt: Date)]
    ) -> [String] {
        var byPID: [Int: [(sessionId: String, startedAt: Date)]] = [:]
        for s in sessions {
            byPID[s.pid, default: []].append((s.sessionId, s.startedAt))
        }

        var staleIDs: [String] = []
        for (_, group) in byPID where group.count > 1 {
            let sorted = group.sorted { $0.startedAt > $1.startedAt }
            for stale in sorted.dropFirst() {
                staleIDs.append(stale.sessionId)
            }
        }
        return staleIDs
    }

    nonisolated static func dedupTuplesFromAliveSessions(
        aliveSessionsByID: [String: LiveSession],
        startedAtBySessionID: [String: Date]
    ) -> [(sessionId: String, pid: Int, startedAt: Date)] {
        var tuples: [(sessionId: String, pid: Int, startedAt: Date)] = []
        tuples.reserveCapacity(aliveSessionsByID.count)

        for (sessionId, liveSession) in aliveSessionsByID {
            guard let startedAt = startedAtBySessionID[sessionId] else {
                continue
            }
            tuples.append((sessionId, liveSession.pid, startedAt))
        }

        return tuples
    }

    private func refreshLiveSessions() {
        let now = Date()
        let liveSessions = LiveSessionRegistry.scan()
        let aliveSessionsByID = Dictionary(
            liveSessions
                .filter(\.isAlive)
                .map { ($0.sessionId, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let aliveSessionIDs = Set(aliveSessionsByID.keys)

        for sessionId in aliveSessionIDs {
            if let liveSession = aliveSessionsByID[sessionId] {
                try? sessionIndex.ensureSessionExists(
                    id: sessionId,
                    tool: liveSession.tool,
                    project: liveSession.cwd,
                    projectName: (liveSession.cwd as NSString).lastPathComponent,
                    startedAt: now
                )
            }
            try? sessionIndex.updateRuntimeState(
                sessionId: sessionId,
                status: "live",
                pid: aliveSessionsByID[sessionId]?.pid
            )
        }

        let indexedLiveSessionIDs = (try? sessionIndex.liveSessionIDs()) ?? []
        for sessionId in indexedLiveSessionIDs.subtracting(aliveSessionIDs) {
            try? sessionIndex.updateRuntimeState(sessionId: sessionId, status: "closed", pid: nil)
        }

        // Dedup: when multiple live sessions share a PID, close all but the newest
        let staleByPID = deduplicateSharedPIDSessions(aliveSessionsByID: aliveSessionsByID)
        let aliveAfterDedup = aliveSessionIDs.subtracting(staleByPID)

        // Health detection rides the existing refresh and is intentionally bounded to
        // the existing live-session query surface (capped at 50).
        let liveResults = (try? sessionIndex.search(query: "", liveOnly: true)) ?? []
        let eligibleResults = liveResults.filter { aliveAfterDedup.contains($0.sessionId) }
        let eligibleIDs = Set(eligibleResults.map(\.sessionId))
        sessionFileURLCache = sessionFileURLCache.filter { eligibleIDs.contains($0.key) }
        sessionFileLookupMissAt = sessionFileLookupMissAt.filter { eligibleIDs.contains($0.key) }
        lastTailReadMtimeBySessionId = lastTailReadMtimeBySessionId.filter { eligibleIDs.contains($0.key) }

        var toolBySessionId: [String: String] = [:]
        toolBySessionId.reserveCapacity(eligibleResults.count)
        for r in eligibleResults {
            toolBySessionId[r.sessionId] = r.tool
        }

        primeSessionFileCache(sessionIDs: eligibleIDs, toolBySessionId: toolBySessionId)

        // Update titles for live sessions from smart sources
        for result in eligibleResults {
            updateLiveSessionTitle(result: result)
        }

        for result in eligibleResults {
            let staleHealth = HealthDetector.detectStale(
                activityStatus: result.activityStatus,
                lastActivityAt: result.lastActivityAt,
                now: now
            )
            let currentHealth = HealthDetector.Result(
                status: result.healthStatus,
                detail: result.healthDetail
            )
            var tailHealth: HealthDetector.Result?

            if let fileURL = findSessionFile(sessionId: result.sessionId),
               let currentMtime = IndexingHelpers.fileMtime(at: fileURL.path) {
                // Update file modification time so activityStatus is fresh
                let lastEntryType = Self.detectLastEntryType(fileURL: fileURL)
                try? sessionIndex.updateActivityFields(
                    sessionId: result.sessionId,
                    lastFileModification: currentMtime,
                    lastEntryType: lastEntryType
                )

                // Only tail-read when the session file has new content.
                if lastTailReadMtimeBySessionId[result.sessionId] != currentMtime {
                    lastTailReadMtimeBySessionId[result.sessionId] = currentMtime
                    tailHealth = HealthDetector.detectFromTail(fileURL: fileURL)
                }
            }

            let health = HealthDetector.resolveHealth(
                current: currentHealth,
                stale: staleHealth,
                tail: tailHealth
            )

            if health.status != result.healthStatus || health.detail != result.healthDetail {
                try? sessionIndex.updateHealthStatus(
                    sessionId: result.sessionId,
                    healthStatus: health.status,
                    healthDetail: health.detail
                )
            }
        }
    }

    private func deduplicateSharedPIDSessions(aliveSessionsByID: [String: LiveSession]) -> Set<String> {
        let aliveSessionIDs = Set(aliveSessionsByID.keys)
        let startedAtBySessionID = (try? sessionIndex.startedAtBySessionID(aliveSessionIDs)) ?? [:]
        let tuples = Self.dedupTuplesFromAliveSessions(
            aliveSessionsByID: aliveSessionsByID,
            startedAtBySessionID: startedAtBySessionID
        )

        let staleIDs = Self.sessionIDsToCloseByPID(sessions: tuples)
        for sessionId in staleIDs {
            try? sessionIndex.updateRuntimeState(sessionId: sessionId, status: "closed", pid: nil)
        }
        return Set(staleIDs)
    }

    // MARK: - Change handling

    private func handleChanges(_ paths: [String]) {
        var needsLiveRefresh = Self.shouldRefreshLiveSessions(forChangedPaths: paths)
        var needsCodexReindex = false
        var claudeSessionsIndexPaths: [String] = []
        var claudeSessionPaths: [String] = []
        var codexSessionPaths: [String] = []

        for path in paths {
            if path.contains("/.claude/sessions/"), path.hasSuffix(".json") {
                needsLiveRefresh = true
                continue
            }

            if path.hasSuffix("/sessions-index.json"), path.contains("/.claude/projects/") {
                claudeSessionsIndexPaths.append(path)
                continue
            }

            if path.contains("/.codex/"), (path.hasSuffix("/session_index.jsonl") || path.hasSuffix("/state_5.sqlite")) {
                needsCodexReindex = true
                continue
            }

            if !path.hasSuffix(".jsonl") {
                continue
            }

            if path.contains("/.claude/projects/") {
                claudeSessionPaths.append(path)
            } else if path.contains("/.codex/sessions/") {
                codexSessionPaths.append(path)
            }
        }

        if needsLiveRefresh {
            refreshLiveSessions()
        }

        for path in claudeSessionsIndexPaths {
            reindexClaudeSessionsIndex(at: path)
        }

        if needsCodexReindex {
            codexTitleMap = IndexingHelpers.loadCodexTitleMap(homeDirectoryPath: homeDirectoryPath)
            reindexAllCodexSessionFiles()
        }

        for path in claudeSessionPaths {
            reindexClaudeSessionFile(at: path)
        }

        if !codexSessionPaths.isEmpty {
            let codexGitBranchMap = CodexStateDB().gitBranchMap()
            for path in codexSessionPaths {
                processedFiles.remove(path)
                indexCodexSessionFile(
                    path: path,
                    titleMap: codexTitleMap,
                    gitBranchMap: codexGitBranchMap
                )
            }
        }
    }

    nonisolated static func shouldRefreshLiveSessions(forChangedPaths paths: [String]) -> Bool {
        for path in paths {
            if path.contains("/.claude/sessions/"), path.hasSuffix(".json") {
                return true
            }
            if path.contains("/.claude/projects/"), path.hasSuffix(".jsonl") {
                return true
            }
            if path.contains("/.codex/sessions/"), path.hasSuffix(".jsonl") {
                return true
            }
        }
        return false
    }

    private func reindexClaudeSessionsIndex(at path: String) {
        let indexURL = URL(fileURLWithPath: path)
        let projectDirectoryURL = indexURL.deletingLastPathComponent()
        let encodedProjectPath = projectDirectoryURL.lastPathComponent
        let decodedProjectPath = ClaudeParser.decodeProjectPath(encodedProjectPath)
        let projectName = (decodedProjectPath as NSString).lastPathComponent
        let metadataBySessionId = IndexingHelpers.claudeSessionMetadataBySessionId(in: projectDirectoryURL)

        for meta in metadataBySessionId.values {
            guard IndexingHelpers.claudeRawSessionFileExists(sessionId: meta.sessionId, in: projectDirectoryURL) else {
                continue
            }

            let rawSessionPath = projectDirectoryURL
                .appendingPathComponent(meta.sessionId)
                .appendingPathExtension("jsonl")
                .path
            processedFiles.remove(rawSessionPath)
            indexClaudeSessionFile(
                path: rawSessionPath,
                sessionId: meta.sessionId,
                projectPath: decodedProjectPath,
                projectName: projectName,
                preferredTitle: meta.title,
                preferredFirstPrompt: meta.firstPrompt
            )
        }
    }

    private func reindexAllCodexSessionFiles() {
        let sessionsPath = homeDirectoryPath + "/.codex/sessions"
        let fileManager = FileManager.default
        let codexGitBranchMap = CodexStateDB().gitBranchMap()

        guard
            let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: sessionsPath),
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            return
        }

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            processedFiles.remove(fileURL.path)
            indexCodexSessionFile(
                path: fileURL.path,
                titleMap: codexTitleMap,
                gitBranchMap: codexGitBranchMap
            )
        }
    }

    private func reindexClaudeSessionFile(at path: String) {
        let fileURL = URL(fileURLWithPath: path)
        let sessionId = fileURL.deletingPathExtension().lastPathComponent
        guard IndexingHelpers.isUUID(sessionId) else {
            return
        }

        processedFiles.remove(path)

        let projectDirectoryURL = fileURL.deletingLastPathComponent()
        let encodedProjectPath = projectDirectoryURL.lastPathComponent
        let decodedProjectPath = ClaudeParser.decodeProjectPath(encodedProjectPath)
        let projectName = (decodedProjectPath as NSString).lastPathComponent
        let metadataBySessionId = IndexingHelpers.claudeSessionMetadataBySessionId(in: projectDirectoryURL)
        indexClaudeSessionFile(
            path: path,
            sessionId: sessionId,
            projectPath: decodedProjectPath,
            projectName: projectName,
            preferredTitle: metadataBySessionId[sessionId]?.title,
            preferredFirstPrompt: metadataBySessionId[sessionId]?.firstPrompt
        )
    }

    // MARK: - Title Sweep

    /// Periodically re-checks sessions with weak titles (project name, "Untitled", empty)
    /// and attempts to find better titles from JSONL tails and external title sources.
    private func runTitleSweep() {
        // Refresh the Codex title map from session_index.jsonl (may have new entries)
        let freshCodexTitleMap = IndexingHelpers.loadCodexTitleMap(homeDirectoryPath: homeDirectoryPath)
        if !freshCodexTitleMap.isEmpty {
            codexTitleMap.merge(freshCodexTitleMap) { _, new in new }
        }

        // Load Claude summaries from all sessions-index.json files
        let claudeSummaries = loadClaudeSummaries()

        guard let weakSessions = try? sessionIndex.sessionsWithWeakTitles() else { return }
        guard !weakSessions.isEmpty else { return }

        let sessionIndex = sessionIndex
        let codexTitleMap = codexTitleMap

        Task.detached(priority: .utility) {
            for session in weakSessions {
                var betterTitle: String?

                // Source 1: Codex thread_name from session_index.jsonl
                if session.tool == "codex" {
                    betterTitle = codexTitleMap[session.sessionId]
                }

                // Source 2: Claude summary from sessions-index.json
                if betterTitle == nil && session.tool == "claude" {
                    betterTitle = claudeSummaries[session.sessionId]
                }

                // Source 3: Last user prompt from JSONL tail
                if betterTitle == nil {
                    let fileURL = Self.findSessionFileStatic(
                        sessionId: session.sessionId,
                        homeDirectoryPath: FileManager.default.homeDirectoryForCurrentUser.path
                    )
                    if let fileURL {
                        betterTitle = TranscriptTailReader.extractLastUserPrompt(fileURL: fileURL)
                    }
                }

                if let betterTitle, !betterTitle.isEmpty, betterTitle != session.projectName {
                    try? sessionIndex.updateTitle(sessionId: session.sessionId, title: betterTitle)
                }
            }
        }
    }

    /// Loads Claude session summaries from all sessions-index.json files,
    /// filtering out "New Conversation" and firstPrompt fallbacks.
    private func loadClaudeSummaries() -> [String: String] {
        let projectsPath = homeDirectoryPath + "/.claude/projects"
        let fm = FileManager.default
        guard let dirs = try? fm.contentsOfDirectory(atPath: projectsPath) else { return [:] }

        var summaries: [String: String] = [:]
        for dir in dirs {
            let indexPath = (projectsPath as NSString).appendingPathComponent(dir)
            let indexURL = URL(fileURLWithPath: indexPath).appendingPathComponent("sessions-index.json")
            guard let metas = try? ClaudeParser.parseSessionsIndex(url: indexURL) else { continue }
            for meta in metas {
                let title = meta.title
                // Only use if it differs from firstPrompt — means it's an AI summary
                let isSmartTitle = meta.firstPrompt.map { title != $0 } ?? true
                if isSmartTitle,
                   !title.isEmpty,
                   title != "Untitled" {
                    summaries[meta.sessionId] = title
                }
            }
        }
        return summaries
    }

    // MARK: - Helpers

    private func updateLiveSessionTitle(result: SearchResult) {
        let currentTitle = result.title
        let projectName = result.projectName

        var betterTitle: String?
        var lastUserPrompt: String?
        if let fileURL = findSessionFile(sessionId: result.sessionId) {
            lastUserPrompt = TranscriptTailReader.extractLastUserPrompt(fileURL: fileURL)
        }

        if let lastUserPrompt, !lastUserPrompt.isEmpty {
            try? sessionIndex.updateLastUserPrompt(sessionId: result.sessionId, prompt: lastUserPrompt)
        }

        let isWeakTitle = IndexingHelpers.hasWeakLiveTitle(
            currentTitle: currentTitle,
            projectName: projectName,
            storedLastUserPrompt: result.lastUserPrompt,
            latestLastUserPrompt: lastUserPrompt
        )
        guard isWeakTitle else { return }

        // For Codex: prefer thread_name from titleMap
        if result.tool == "codex" {
            betterTitle = codexTitleMap[result.sessionId]
        }

        if betterTitle == nil {
            betterTitle = lastUserPrompt
        }

        if let betterTitle, !betterTitle.isEmpty, betterTitle != currentTitle {
            try? sessionIndex.updateTitle(sessionId: result.sessionId, title: betterTitle)
        }
    }

    /// Reads the tail of a session file and returns the type of the last JSONL entry.
    nonisolated static func detectLastEntryType(fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let readSize = min(fileSize, UInt64(2048))
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readData(ofLength: Int(readSize))

        guard let text = String(data: data, encoding: .utf8) else { return nil }

        let lines = text.split(whereSeparator: \.isNewline).reversed()
        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let record = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any],
                  let type = record["type"] as? String
            else { continue }

            switch type {
            case "user": return "user"
            case "assistant":
                // Check if the assistant message contains tool_use blocks
                if let message = record["message"] as? [String: Any],
                   let content = message["content"] as? [[String: Any]] {
                    let hasToolUse = content.contains { $0["type"] as? String == "tool_use" }
                    return hasToolUse ? "tool_use" : "assistant"
                }
                return "assistant"
            case "tool_result": return "tool_result"
            default: continue
            }
        }

        return nil
    }

    private func primeSessionFileCache(
        sessionIDs: Set<String>,
        toolBySessionId: [String: String],
        now: Date = Date()
    ) {
        let lookupCooldown: TimeInterval = 30
        let fileManager = FileManager.default

        let missingClaudeIDs = sessionIDs.filter {
            toolBySessionId[$0] == "claude"
                && sessionFileURLCache[$0] == nil
                && now.timeIntervalSince(sessionFileLookupMissAt[$0] ?? .distantPast) >= lookupCooldown
        }
        if !missingClaudeIDs.isEmpty {
            let projectsPath = homeDirectoryPath + "/.claude/projects"
            if let projectDirectories = try? fileManager.contentsOfDirectory(atPath: projectsPath) {
                for encodedProjectPath in projectDirectories {
                    let directoryPath = (projectsPath as NSString).appendingPathComponent(encodedProjectPath)
                    for sessionID in missingClaudeIDs where sessionFileURLCache[sessionID] == nil {
                        let candidatePath = (directoryPath as NSString)
                            .appendingPathComponent(sessionID)
                            .appending(".jsonl")
                        if fileManager.fileExists(atPath: candidatePath) {
                            sessionFileURLCache[sessionID] = URL(fileURLWithPath: candidatePath)
                            sessionFileLookupMissAt.removeValue(forKey: sessionID)
                        }
                    }
                }
            }
            for sessionID in missingClaudeIDs where sessionFileURLCache[sessionID] == nil {
                sessionFileLookupMissAt[sessionID] = now
            }
        }

        let missingCodexIDs = sessionIDs.filter {
            toolBySessionId[$0] == "codex"
                && sessionFileURLCache[$0] == nil
                && now.timeIntervalSince(sessionFileLookupMissAt[$0] ?? .distantPast) >= lookupCooldown
        }
        if !missingCodexIDs.isEmpty {
            let missingSet = Set(missingCodexIDs)
            let codexRoot = URL(fileURLWithPath: homeDirectoryPath + "/.codex/sessions", isDirectory: true)
            if let enumerator = fileManager.enumerator(
                at: codexRoot,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) {
                for case let fileURL as URL in enumerator {
                    guard fileURL.pathExtension == "jsonl" else { continue }
                    let fileNameID = fileURL.deletingPathExtension().lastPathComponent
                    let candidateIDs = [fileNameID, IndexingHelpers.codexSessionIDFromPath(fileURL.path)].compactMap { $0 }
                    for sessionID in candidateIDs where missingSet.contains(sessionID) {
                        sessionFileURLCache[sessionID] = fileURL
                        sessionFileLookupMissAt.removeValue(forKey: sessionID)
                    }
                }
            }
            for sessionID in missingCodexIDs where sessionFileURLCache[sessionID] == nil {
                sessionFileLookupMissAt[sessionID] = now
            }
        }
    }

    private func findSessionFile(sessionId: String) -> URL? {
        if let cached = sessionFileURLCache[sessionId] {
            return cached
        }

        let now = Date()
        let lookupCooldown: TimeInterval = 30
        if now.timeIntervalSince(sessionFileLookupMissAt[sessionId] ?? .distantPast) < lookupCooldown {
            return nil
        }

        let fileManager = FileManager.default
        let projectsPath = homeDirectoryPath + "/.claude/projects"
        if let projectDirectories = try? fileManager.contentsOfDirectory(atPath: projectsPath) {
            for encodedProjectPath in projectDirectories {
                let directoryPath = (projectsPath as NSString).appendingPathComponent(encodedProjectPath)
                let candidatePath = (directoryPath as NSString)
                    .appendingPathComponent(sessionId)
                    .appending(".jsonl")
                if fileManager.fileExists(atPath: candidatePath) {
                    let url = URL(fileURLWithPath: candidatePath)
                    sessionFileURLCache[sessionId] = url
                    sessionFileLookupMissAt.removeValue(forKey: sessionId)
                    return url
                }
            }
        }

        let codexRoot = URL(fileURLWithPath: homeDirectoryPath + "/.codex/sessions", isDirectory: true)
        if let enumerator = fileManager.enumerator(
            at: codexRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }
                let fileNameID = fileURL.deletingPathExtension().lastPathComponent
                let candidateIDs = [fileNameID, IndexingHelpers.codexSessionIDFromPath(fileURL.path)].compactMap { $0 }
                if candidateIDs.contains(sessionId) {
                    sessionFileURLCache[sessionId] = fileURL
                    sessionFileLookupMissAt.removeValue(forKey: sessionId)
                    return fileURL
                }
            }
        }

        sessionFileLookupMissAt[sessionId] = now
        return nil
    }

    /// Thread-safe, uncached file lookup for background title sweeps.
    nonisolated static func findSessionFileStatic(sessionId: String, homeDirectoryPath: String) -> URL? {
        let fm = FileManager.default

        let claudeProjectsPath = homeDirectoryPath + "/.claude/projects"
        if let projectDirs = try? fm.contentsOfDirectory(atPath: claudeProjectsPath) {
            for projectDir in projectDirs {
                let path = "\(claudeProjectsPath)/\(projectDir)/\(sessionId).jsonl"
                if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
            }
        }

        let codexRoot = URL(fileURLWithPath: homeDirectoryPath + "/.codex/sessions", isDirectory: true)
        if let enumerator = fm.enumerator(
            at: codexRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
                let fileNameID = fileURL.deletingPathExtension().lastPathComponent
                let candidateIDs = [fileNameID, IndexingHelpers.codexSessionIDFromPath(fileURL.path)].compactMap { $0 }
                if candidateIDs.contains(sessionId) {
                    return fileURL
                }
            }
        }

        return nil
    }
}
