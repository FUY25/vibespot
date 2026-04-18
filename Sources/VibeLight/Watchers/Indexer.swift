import Foundation

final class Indexer: @unchecked Sendable {
    struct CodexMetadataRefreshPlan: Sendable, Equatable {
        var refreshTitles = false
        var refreshGitBranches = false
        var forceFullTranscriptReindex = false
    }

    static let changeHandlingQueueLabel = "ai.vibelight.indexer.change-handling"

    let sessionIndex: SessionIndex
    private let sourceResolution: SessionSourceResolution
    private let sessionFileLocator: SessionFileLocator
    private let changeHandlingQueue: DispatchQueue
    private let changeHandlingQueueSpecificKey = DispatchSpecificKey<Void>()
    private let generationLock = NSLock()
    private var fileWatcher: FileWatcher?
    private var refreshTimer: Timer?
    private var startupScanTask: Task<Void, Never>?
    private var activeGeneration: UInt64 = 0
    private var processedFiles: Set<String> = []
    private var codexTitleMap: [String: String] = [:]
    private var lastTailReadMtimeBySessionId: [String: Date] = [:]

#if DEBUG
    var onPerformFullScanForTesting: (@Sendable () -> Void)?
#endif

    init(
        sessionIndex: SessionIndex,
        sourceResolution: SessionSourceResolution = SessionSourceLocator().resolve(for: AppSettings.default),
        sessionFileLocator: SessionFileLocator = SessionFileLocator(),
        changeHandlingQueue: DispatchQueue = DispatchQueue(label: Indexer.changeHandlingQueueLabel, qos: .utility)
    ) {
        self.sessionIndex = sessionIndex
        self.sourceResolution = sourceResolution
        self.sessionFileLocator = sessionFileLocator
        self.changeHandlingQueue = changeHandlingQueue
        self.changeHandlingQueue.setSpecific(key: changeHandlingQueueSpecificKey, value: ())
    }

    convenience init(
        sessionIndex: SessionIndex,
        homeDirectoryPath: String
    ) {
        let sessionSourceResolution = SessionSourceLocator(homeDirectoryPath: homeDirectoryPath).resolve(for: AppSettings.default)
        self.init(sessionIndex: sessionIndex, sourceResolution: sessionSourceResolution)
    }

    static func shouldRefreshLiveSessions(
        forChangedPaths paths: [String],
        sourceResolution: SessionSourceResolution? = nil
    ) -> Bool {
        guard let resolvedSource = sourceResolution else {
            return paths.contains { path in
                if path.hasSuffix(".json") && (path.contains("/.claude/sessions/") || path.hasSuffix("/.claude/sessions")) {
                    return true
                }
                if path.hasSuffix(".jsonl"), path.contains("/.claude/projects/") {
                    return true
                }
                if path.hasSuffix(".jsonl"), path.contains("/.codex/sessions/") {
                    return true
                }
                return false
            }
        }

        return paths.contains { path in
            if path.hasSuffix(".json"), isUnderClaudeSessionsPath(path, for: resolvedSource) {
                return true
            }
            if path.hasSuffix(".jsonl"), isUnderClaudeProjectsPath(path, for: resolvedSource) {
                return true
            }
            if path.hasSuffix(".jsonl"), isUnderCodexSessionsPath(path, for: resolvedSource) {
                return true
            }
            return false
        }
    }

    static func codexMetadataRefreshPlan(
        forChangedPaths paths: [String],
        sourceResolution: SessionSourceResolution? = nil
    ) -> CodexMetadataRefreshPlan {
        var plan = CodexMetadataRefreshPlan()

        for path in paths {
            let isUnderCodexRoot: Bool
            if let sourceResolution {
                isUnderCodexRoot = isUnderCodexRootPath(path, for: sourceResolution)
            } else {
                isUnderCodexRoot = path.contains("/.codex/")
            }

            guard isUnderCodexRoot else {
                continue
            }

            if path.hasSuffix("/session_index.jsonl") {
                plan.refreshTitles = true
            }

            if isCodexStateMetadataPath(path) {
                plan.refreshGitBranches = true
            }
        }

        return plan
    }

    private static func isCodexStateMetadataPath(_ path: String) -> Bool {
        return path.hasSuffix("/state_5.sqlite")
            || path.hasSuffix("/state_5.sqlite-wal")
            || path.hasSuffix("/state_5.sqlite-shm")
            || path.hasSuffix("/state_5.sqlite-journal")
    }

    private func performOnChangeHandlingQueueSync<T>(_ operation: () -> T) -> T {
        if DispatchQueue.getSpecific(key: changeHandlingQueueSpecificKey) != nil {
            return operation()
        }

        return changeHandlingQueue.sync(execute: operation)
    }

    private func nextGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        activeGeneration += 1
        return activeGeneration
    }

    private func isCurrentGeneration(_ generation: UInt64) -> Bool {
        generationLock.lock()
        defer { generationLock.unlock() }
        return activeGeneration == generation
    }

    private func currentGeneration() -> UInt64 {
        generationLock.lock()
        defer { generationLock.unlock() }
        return activeGeneration
    }

    private func enqueueChangeHandling(
        generation: UInt64,
        operation: @escaping @Sendable (Indexer) -> Void
    ) {
        changeHandlingQueue.async { [weak self] in
            guard let self, self.isCurrentGeneration(generation) else {
                return
            }

            operation(self)
        }
    }

#if DEBUG
    func enqueueChangeHandlingForTesting(_ operation: @escaping @Sendable (Indexer) -> Void) {
        enqueueChangeHandling(generation: currentGeneration(), operation: operation)
    }

    func waitForChangeHandlingQueueForTesting() {
        performOnChangeHandlingQueueSync {}
    }
#endif

    func start() {
        stop()
        let generation = nextGeneration()

        let sessionIndex = sessionIndex
        let sourceResolution = sourceResolution
        startupScanTask = Task.detached(priority: .utility) { [weak self] in
            var scanner = IndexScanner(
                sessionIndex: sessionIndex,
                sourceResolution: sourceResolution
            )
            scanner.performFullScan()

            guard !Task.isCancelled else {
                return
            }

            self?.enqueueChangeHandling(generation: generation) { indexer in
                indexer.refreshLiveSessions()
            }
        }

        let watchPaths = [
            sourceResolution.claudeRootPath,
            sourceResolution.codexRootPath,
        ].filter { FileManager.default.fileExists(atPath: $0) }

        if !watchPaths.isEmpty {
            fileWatcher = FileWatcher(paths: watchPaths) { [weak self] changedPaths in
                self?.enqueueChangeHandling(generation: generation) { indexer in
                    indexer.handleChanges(changedPaths)
                }
            }
            fileWatcher?.start()
        }

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.enqueueChangeHandling(generation: generation) { indexer in
                indexer.refreshLiveSessions()
            }
        }
    }

    func stop() {
        _ = nextGeneration()
        startupScanTask?.cancel()
        startupScanTask = nil

        fileWatcher?.stop()
        fileWatcher = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        performOnChangeHandlingQueueSync {}
    }

    // MARK: - Full scan

    func performFullScan() {
        performOnChangeHandlingQueueSync {
#if DEBUG
            onPerformFullScanForTesting?()
#endif
            var scanner = IndexScanner(
                sessionIndex: sessionIndex,
                sourceResolution: sourceResolution
            )
            scanner.performFullScan()
            refreshLiveSessions()
        }
    }

    private func scanClaudeSessions() {
        let projectsPath = sourceResolution.claudeProjectsPath
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
        sessionFileLocator.record(sessionID: sessionId, fileURL: url)
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
        codexTitleMap = IndexingHelpers.loadCodexTitleMap(codexRootPath: sourceResolution.codexRootPath)
        let codexGitBranchMap = CodexStateDB(path: sourceResolution.codexStatePath).gitBranchMap()

        let sessionsPath = sourceResolution.codexSessionsPath
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
        sessionFileLocator.record(sessionID: sessionId, fileURL: url)
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
    static func sessionIDsToCloseByPID(
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

    static func dedupTuplesFromAliveSessions(
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
        let liveSessions = LiveSessionRegistry.scan(
            claudeSessionsPath: sourceResolution.claudeSessionsPath,
            codexStatePath: sourceResolution.codexStatePath
        )
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
        sessionFileLocator.prune(keeping: eligibleIDs)
        lastTailReadMtimeBySessionId = lastTailReadMtimeBySessionId.filter { eligibleIDs.contains($0.key) }

        var toolBySessionId: [String: String] = [:]
        toolBySessionId.reserveCapacity(eligibleResults.count)
        for r in eligibleResults {
            toolBySessionId[r.sessionId] = r.tool
        }

        sessionFileLocator.prime(
            sessionIDs: eligibleIDs,
            toolBySessionId: toolBySessionId,
            sourceResolution: sourceResolution,
            now: now
        )

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
        var needsLiveRefresh = shouldRefreshLiveSessions(forChangedPaths: paths)
        let codexMetadataRefreshPlan = Self.codexMetadataRefreshPlan(
            forChangedPaths: paths,
            sourceResolution: sourceResolution
        )
        var claudeSessionsIndexPaths: [String] = []
        var claudeSessionPaths: [String] = []
        var codexSessionPaths: [String] = []

        for path in paths {
            if isUnderClaudeSessionsPath(path), path.hasSuffix(".json") {
                needsLiveRefresh = true
                continue
            }

            if path.hasSuffix("/sessions-index.json"), isUnderClaudeProjectsPath(path) {
                claudeSessionsIndexPaths.append(path)
                continue
            }

            if isUnderCodexRootPath(path), (path.hasSuffix("/session_index.jsonl") || Self.isCodexStateMetadataPath(path)) {
                continue
            }

            if !path.hasSuffix(".jsonl") {
                continue
            }

            if isUnderClaudeProjectsPath(path) {
                claudeSessionPaths.append(path)
            } else if isUnderCodexSessionsPath(path) {
                codexSessionPaths.append(path)
            }
        }

        if needsLiveRefresh {
            refreshLiveSessions()
        }

        for path in claudeSessionsIndexPaths {
            reindexClaudeSessionsIndex(at: path)
        }

        if codexMetadataRefreshPlan.refreshTitles {
            refreshCodexTitles()
        }

        if codexMetadataRefreshPlan.refreshGitBranches {
            refreshCodexGitBranches()
        }

        for path in claudeSessionPaths {
            reindexClaudeSessionFile(at: path)
        }

        if !codexSessionPaths.isEmpty {
            let codexGitBranchMap = CodexStateDB(path: sourceResolution.codexStatePath).gitBranchMap()
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

    private func shouldRefreshLiveSessions(forChangedPaths paths: [String]) -> Bool {
        return Self.shouldRefreshLiveSessions(
            forChangedPaths: paths,
            sourceResolution: sourceResolution
        )
    }

    private static func isUnderClaudeSessionsPath(_ path: String, for sourceResolution: SessionSourceResolution) -> Bool {
        return path == sourceResolution.claudeSessionsPath || path.hasPrefix(sourceResolution.claudeSessionsPath + "/")
    }

    private static func isUnderClaudeProjectsPath(_ path: String, for sourceResolution: SessionSourceResolution) -> Bool {
        return path == sourceResolution.claudeProjectsPath || path.hasPrefix(sourceResolution.claudeProjectsPath + "/")
    }

    private static func isUnderCodexSessionsPath(_ path: String, for sourceResolution: SessionSourceResolution) -> Bool {
        return path == sourceResolution.codexSessionsPath || path.hasPrefix(sourceResolution.codexSessionsPath + "/")
    }

    private static func isUnderCodexRootPath(_ path: String, for sourceResolution: SessionSourceResolution) -> Bool {
        return path == sourceResolution.codexRootPath || path.hasPrefix(sourceResolution.codexRootPath + "/")
    }

    private func isUnderClaudeSessionsPath(_ path: String) -> Bool {
        return path == sourceResolution.claudeSessionsPath || path.hasPrefix(sourceResolution.claudeSessionsPath + "/")
    }

    private func isUnderClaudeProjectsPath(_ path: String) -> Bool {
        return path == sourceResolution.claudeProjectsPath || path.hasPrefix(sourceResolution.claudeProjectsPath + "/")
    }

    private func isUnderCodexRootPath(_ path: String) -> Bool {
        return path == sourceResolution.codexRootPath || path.hasPrefix(sourceResolution.codexRootPath + "/")
    }

    private func isUnderCodexSessionsPath(_ path: String) -> Bool {
        return path == sourceResolution.codexSessionsPath || path.hasPrefix(sourceResolution.codexSessionsPath + "/")
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

    private func refreshCodexTitles() {
        let refreshedTitleMap = IndexingHelpers.loadCodexTitleMap(codexRootPath: sourceResolution.codexRootPath)
        codexTitleMap = refreshedTitleMap

        guard let codexSessionIDs = try? sessionIndex.sessionIDs(forTool: "codex") else {
            return
        }

        for sessionID in codexSessionIDs {
            guard let refreshedTitle = refreshedTitleMap[sessionID] else {
                continue
            }

            try? sessionIndex.updateTitle(sessionId: sessionID, title: refreshedTitle)
        }
    }

    private func refreshCodexGitBranches() {
        let gitBranchMap = CodexStateDB(path: sourceResolution.codexStatePath).gitBranchMap()

        guard let codexSessionIDs = try? sessionIndex.sessionIDs(forTool: "codex") else {
            return
        }

        for sessionID in codexSessionIDs {
            try? sessionIndex.updateGitBranch(sessionId: sessionID, gitBranch: gitBranchMap[sessionID] ?? "")
        }
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
    static func detectLastEntryType(fileURL: URL) -> String? {
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

    private func findSessionFile(sessionId: String) -> URL? {
        sessionFileLocator.fileURL(sessionID: sessionId, sourceResolution: sourceResolution)
    }

}
