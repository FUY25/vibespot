import Foundation

struct IndexScanner {
    let sessionIndex: SessionIndex
    let sourceResolution: SessionSourceResolution

    private var processedFiles: Set<String> = []
    private var codexTitleMap: [String: String] = [:]

    init(sessionIndex: SessionIndex, sourceResolution: SessionSourceResolution) {
        self.sessionIndex = sessionIndex
        self.sourceResolution = sourceResolution
    }

    mutating func performFullScan() {
        guard !Task.isCancelled else {
            return
        }
        scanClaudeSessions()
        guard !Task.isCancelled else {
            return
        }
        scanCodexSessions()
    }

    mutating func scanClaudeSessions() {
        guard !Task.isCancelled else {
            return
        }
        let projectsPath = sourceResolution.claudeProjectsPath
        let fileManager = FileManager.default

        guard let projectDirectories = try? fileManager.contentsOfDirectory(atPath: projectsPath) else {
            return
        }

        for encodedProjectPath in projectDirectories {
            if Task.isCancelled {
                return
            }
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
                if Task.isCancelled {
                    return
                }
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
                if Task.isCancelled {
                    return
                }
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

    mutating func scanCodexSessions() {
        guard !Task.isCancelled else {
            return
        }
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
            if Task.isCancelled {
                return
            }
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

    private func indexClaudeSession(
        meta: ParsedSessionMeta,
        fallbackProjectPath: String,
        fallbackProjectName: String
    ) {
        guard !Task.isCancelled else {
            return
        }
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

    private mutating func indexClaudeSessionFile(
        path: String,
        sessionId: String,
        projectPath: String,
        projectName: String,
        preferredTitle: String? = nil,
        preferredFirstPrompt: String? = nil
    ) {
        guard !Task.isCancelled else {
            return
        }
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
        if fileMtimeDidChange(at: path, expected: mtime) {
            return
        }

        if messages.isEmpty {
            if let telemetry {
                try? sessionIndex.updateTelemetry(sessionId: sessionId, telemetry: telemetry, lastIndexedMtime: mtime)
            }
            persistIndexedFileState(sessionId: sessionId, path: path, lastMtime: mtime)
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
        persistIndexedFileState(sessionId: sessionId, path: path, lastMtime: mtime)
    }

    private mutating func indexCodexSessionFile(
        path: String,
        titleMap: [String: String],
        gitBranchMap: [String: String]
    ) {
        guard !Task.isCancelled else {
            return
        }
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
        let parseStartMtime = IndexingHelpers.fileMtime(at: path)

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
        if fileMtimeDidChange(at: path, expected: parseStartMtime) {
            return
        }
        let mtime = parseStartMtime ?? IndexingHelpers.fileMtime(at: path)

        if messages.isEmpty {
            if let telemetry {
                try? sessionIndex.updateTelemetry(sessionId: sessionId, telemetry: telemetry, lastIndexedMtime: mtime)
            }
            persistIndexedFileState(sessionId: sessionId, path: path, lastMtime: mtime)
            return
        }

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
        persistIndexedFileState(sessionId: sessionId, path: path, lastMtime: mtime)
    }

    private func persistIndexedFileState(sessionId: String, path: String, lastMtime: Date?) {
        try? sessionIndex.upsertIndexedFileState(
            IndexedFileState(
                sessionId: sessionId,
                filePath: path,
                lastOffset: fileSize(at: path) ?? 0,
                lastSize: fileSize(at: path) ?? 0,
                lastMtime: lastMtime
            )
        )
    }

    private func fileSize(at path: String) -> UInt64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attributes[.size] as? NSNumber
        else {
            return nil
        }

        return size.uint64Value
    }

    private func fileMtimeDidChange(at path: String, expected: Date?) -> Bool {
        guard let expected else {
            return false
        }
        guard let currentMtime = IndexingHelpers.fileMtime(at: path) else {
            return true
        }
        return currentMtime != expected
    }
}

extension IndexScanner {
    static func buildFullScan(sessionIndex: SessionIndex, sourceResolution: SessionSourceResolution) throws {
        var scanner = IndexScanner(sessionIndex: sessionIndex, sourceResolution: sourceResolution)
        scanner.performFullScan()
    }
}
