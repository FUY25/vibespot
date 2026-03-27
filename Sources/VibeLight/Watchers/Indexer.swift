import Foundation

@MainActor
final class Indexer {
    let sessionIndex: SessionIndex

    private let homeDirectoryPath: String
    private var fileWatcher: FileWatcher?
    private var refreshTimer: Timer?
    private var processedFiles: Set<String> = []
    private var codexTitleMap: [String: String] = [:]

    init(
        sessionIndex: SessionIndex,
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.sessionIndex = sessionIndex
        self.homeDirectoryPath = homeDirectoryPath
    }

    func start() {
        stop()

        Task { @MainActor [weak self] in
            self?.performFullScan()
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
    }

    func stop() {
        fileWatcher?.stop()
        fileWatcher = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    // MARK: - Full scan

    func performFullScan() {
        scanClaudeSessions()
        scanCodexSessions()
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
            let metadataBySessionId = claudeSessionMetadataBySessionId(in: projectDirectoryURL)

            for meta in metadataBySessionId.values {
                guard claudeRawSessionFileExists(sessionId: meta.sessionId, in: projectDirectoryURL) else {
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
                guard isUUID(sessionId) else {
                    continue
                }

                indexClaudeSessionFile(
                    path: filePath,
                    sessionId: sessionId,
                    projectPath: decodedProjectPath,
                    projectName: projectName,
                    preferredTitle: metadataBySessionId[sessionId]?.title
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
        let title = normalizedDisplayTitle(from: meta.title) ?? "Untitled"

        try? sessionIndex.upsertSession(
            id: meta.sessionId,
            tool: "claude",
            title: title,
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
        preferredTitle: String? = nil
    ) {
        guard !processedFiles.contains(path) else {
            return
        }
        processedFiles.insert(path)
        if shouldSkipFile(path: path, sessionId: sessionId) {
            return
        }
        let mtime = fileMtime(at: path)

        let url = URL(fileURLWithPath: path)
        guard let messages = try? ClaudeParser.parseSessionFile(url: url) else {
            return
        }

        let cwd = messages.lazy.compactMap(\.cwd).first(where: { !$0.isEmpty }) ?? projectPath
        let resolvedProjectName = cwd.isEmpty ? projectName : (cwd as NSString).lastPathComponent
        let gitBranch = messages.lazy.compactMap(\.gitBranch).first(where: { !$0.isEmpty }) ?? ""
        let cleanedPreferredTitle = preferredTitle.flatMap(normalizedDisplayTitle(from:))
        let title = (cleanedPreferredTitle?.isEmpty == false ? cleanedPreferredTitle : nil)
            ?? SessionTitleNormalizer.firstMeaningfulDisplayTitle(in: messages)
            ?? "Untitled"
        let startedAt = messages.first?.timestamp ?? .distantPast
        let metrics = sessionMetrics(from: messages, filePath: path)

        try? sessionIndex.upsertSession(
            id: sessionId,
            tool: "claude",
            title: String(title.prefix(200)),
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
            lastIndexedMtime: mtime
        )

        let transcriptEntries = messages.map { message in
            (
                role: message.role,
                content: searchableContent(from: message),
                timestamp: message.timestamp
            )
        }
        try? sessionIndex.replaceTranscripts(sessionId: sessionId, entries: transcriptEntries)
    }

    private func scanCodexSessions() {
        codexTitleMap = loadCodexTitleMap()

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

            indexCodexSessionFile(path: fileURL.path, titleMap: codexTitleMap)
        }
    }

    private func loadCodexTitleMap() -> [String: String] {
        let indexURL = URL(fileURLWithPath: homeDirectoryPath + "/.codex/session_index.jsonl")
        let metas = (try? CodexParser.parseSessionIndex(url: indexURL)) ?? []

        var titleMap: [String: String] = [:]
        for meta in metas {
            let title = normalizedDisplayTitle(from: meta.title) ?? "Untitled"
            titleMap[meta.sessionId] = title
        }
        return titleMap
    }

    private func indexCodexSessionFile(path: String, titleMap: [String: String]) {
        guard !processedFiles.contains(path) else {
            return
        }
        processedFiles.insert(path)

        // Codex filenames include the session UUID (for example, rollout-...-<uuid>.jsonl).
        // If we can infer it from the path, we can skip unchanged files before full JSONL parsing.
        if let sessionIdFromPath = codexSessionIDFromPath(path),
           shouldSkipFile(path: path, sessionId: sessionIdFromPath) {
            return
        }

        let url = URL(fileURLWithPath: path)
        guard let (meta, messages) = try? CodexParser.parseSessionFile(url: url) else {
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
        if shouldSkipFile(path: path, sessionId: sessionId) {
            return
        }
        let mtime = fileMtime(at: path)

        let title = titleMap[sessionId]
            ?? SessionTitleNormalizer.firstMeaningfulDisplayTitle(in: messages)
            ?? "Untitled"
        let cwd = (meta?.cwd ?? messages.compactMap(\.cwd).first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let metrics = sessionMetrics(from: messages, filePath: path)

        try? sessionIndex.upsertSession(
            id: sessionId,
            tool: "codex",
            title: String(title.prefix(200)),
            project: cwd,
            projectName: cwd.isEmpty ? "" : (cwd as NSString).lastPathComponent,
            gitBranch: "",
            status: "closed",
            startedAt: messages.first?.timestamp ?? .distantPast,
            pid: nil,
            tokenCount: metrics.tokenCount,
            lastActivityAt: metrics.lastActivityAt,
            lastFileModification: metrics.lastFileModification,
            lastEntryType: metrics.lastEntryType,
            activityPreview: metrics.activityPreview,
            lastIndexedMtime: mtime
        )

        let transcriptEntries = messages.map { message in
            (
                role: message.role,
                content: searchableContent(from: message),
                timestamp: message.timestamp
            )
        }
        try? sessionIndex.replaceTranscripts(sessionId: sessionId, entries: transcriptEntries)
    }

    // MARK: - Live sessions

    private func refreshLiveSessions() {
        let liveSessions = LiveSessionRegistry.scan()
        let aliveSessionsByID = Dictionary(
            uniqueKeysWithValues: liveSessions
                .filter(\.isAlive)
                .map { ($0.sessionId, $0) }
        )
        let aliveSessionIDs = Set(
            liveSessions
                .filter(\.isAlive)
                .map(\.sessionId)
        )

        for sessionId in aliveSessionIDs {
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
    }

    // MARK: - Change handling

    private func handleChanges(_ paths: [String]) {
        for path in paths {
            if path.contains("/.claude/sessions/"), path.hasSuffix(".json") {
                refreshLiveSessions()
                continue
            }

            if path.hasSuffix("/sessions-index.json"), path.contains("/.claude/projects/") {
                reindexClaudeSessionsIndex(at: path)
                continue
            }

            if path.hasSuffix("/session_index.jsonl"), path.contains("/.codex/") {
                codexTitleMap = loadCodexTitleMap()
                reindexAllCodexSessionFiles()
                continue
            }

            if !path.hasSuffix(".jsonl") {
                continue
            }

            if path.contains("/.claude/projects/") {
                reindexClaudeSessionFile(at: path)
            } else if path.contains("/.codex/sessions/") {
                processedFiles.remove(path)
                indexCodexSessionFile(path: path, titleMap: codexTitleMap)
            }
        }
    }

    private func reindexClaudeSessionsIndex(at path: String) {
        let indexURL = URL(fileURLWithPath: path)
        let projectDirectoryURL = indexURL.deletingLastPathComponent()
        let encodedProjectPath = projectDirectoryURL.lastPathComponent
        let decodedProjectPath = ClaudeParser.decodeProjectPath(encodedProjectPath)
        let projectName = (decodedProjectPath as NSString).lastPathComponent
        let metadataBySessionId = claudeSessionMetadataBySessionId(in: projectDirectoryURL)

        for meta in metadataBySessionId.values {
            guard claudeRawSessionFileExists(sessionId: meta.sessionId, in: projectDirectoryURL) else {
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
                preferredTitle: meta.title
            )
        }
    }

    private func reindexAllCodexSessionFiles() {
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

        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            processedFiles.remove(fileURL.path)
            indexCodexSessionFile(path: fileURL.path, titleMap: codexTitleMap)
        }
    }

    private func reindexClaudeSessionFile(at path: String) {
        let fileURL = URL(fileURLWithPath: path)
        let sessionId = fileURL.deletingPathExtension().lastPathComponent
        guard isUUID(sessionId) else {
            return
        }

        processedFiles.remove(path)

        let projectDirectoryURL = fileURL.deletingLastPathComponent()
        let encodedProjectPath = projectDirectoryURL.lastPathComponent
        let decodedProjectPath = ClaudeParser.decodeProjectPath(encodedProjectPath)
        let projectName = (decodedProjectPath as NSString).lastPathComponent
        let metadataBySessionId = claudeSessionMetadataBySessionId(in: projectDirectoryURL)
        indexClaudeSessionFile(
            path: path,
            sessionId: sessionId,
            projectPath: decodedProjectPath,
            projectName: projectName,
            preferredTitle: metadataBySessionId[sessionId]?.title
        )
    }

    // MARK: - Helpers

    private func fileMtime(at path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }

    private func shouldSkipFile(path: String, sessionId: String) -> Bool {
        guard let currentMtime = fileMtime(at: path) else { return false }
        guard let storedMtime = try? sessionIndex.lastIndexedMtime(sessionId: sessionId) else { return false }
        return currentMtime == storedMtime
    }

    private func claudeSessionMetadataBySessionId(in projectDirectoryURL: URL) -> [String: ParsedSessionMeta] {
        let sessionsIndexURL = projectDirectoryURL.appendingPathComponent("sessions-index.json")
        guard let metas = try? ClaudeParser.parseSessionsIndex(url: sessionsIndexURL) else {
            return [:]
        }

        var metadataBySessionId: [String: ParsedSessionMeta] = [:]
        for meta in metas where !meta.isSidechain {
            metadataBySessionId[meta.sessionId] = meta
        }
        return metadataBySessionId
    }

    private func claudeRawSessionFileExists(sessionId: String, in projectDirectoryURL: URL) -> Bool {
        guard !sessionId.isEmpty else {
            return false
        }

        let rawSessionURL = projectDirectoryURL.appendingPathComponent(sessionId).appendingPathExtension("jsonl")
        return FileManager.default.fileExists(atPath: rawSessionURL.path)
    }

    private func searchableContent(from message: ParsedMessage) -> String {
        let combined = [message.content] + message.toolCalls
        return combined
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func sessionMetrics(
        from messages: [ParsedMessage],
        filePath: String
    ) -> (
        tokenCount: Int,
        lastActivityAt: Date,
        lastFileModification: Date?,
        lastEntryType: String?,
        activityPreview: ActivityPreview?
    ) {
        let lastActivityAt = messages.last?.timestamp ?? .distantPast
        let lastFileModification = (try? FileManager.default.attributesOfItem(atPath: filePath)[.modificationDate]) as? Date

        let tokenCount = max(
            0,
            messages.reduce(into: 0) { partial, message in
                partial += approximateTokenCount(for: message.content)
                for toolCall in message.toolCalls {
                    partial += approximateTokenCount(for: toolCall)
                }
            }
        )

        guard let lastMessage = messages.last else {
            return (tokenCount, lastActivityAt, lastFileModification, nil, nil)
        }

        if let toolCall = lastMessage.toolCalls.last {
            return (
                tokenCount,
                lastActivityAt,
                lastFileModification,
                "tool_use",
                previewForToolCall(toolCall)
            )
        }

        if lastMessage.role == "user" {
            return (tokenCount, lastActivityAt, lastFileModification, "user", nil)
        }

        let trimmedContent = lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            return (tokenCount, lastActivityAt, lastFileModification, lastMessage.role, nil)
        }

        return (
            tokenCount,
            lastActivityAt,
            lastFileModification,
            lastMessage.role,
            ActivityPreview(
                text: condensedPreviewText(from: trimmedContent),
                kind: .assistant
            )
        )
    }

    private func approximateTokenCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return 0
        }

        return max(1, Int(ceil(Double(trimmed.count) / 4.0)))
    }

    private func previewForToolCall(_ toolCall: String) -> ActivityPreview {
        let normalized = condensedPreviewText(from: toolCall)
        let lowercased = normalized.lowercased()

        if lowercased.contains("edit") || lowercased.contains("write") || lowercased.contains("apply_patch") {
            return ActivityPreview(text: "✎ Editing \(normalized)", kind: .fileEdit)
        }

        return ActivityPreview(text: "▶ Running \(normalized)", kind: .tool)
    }

    private func condensedPreviewText(from text: String, limit: Int = 80) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if normalized.count <= limit {
            return normalized
        }

        return String(normalized.prefix(limit - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    private func normalizedDisplayTitle(from rawTitle: String) -> String? {
        if let displayTitle = SessionTitleNormalizer.displayTitleCandidate(from: rawTitle) {
            return displayTitle
        }

        if let parserTitle = SessionTitleNormalizer.titleCandidate(from: rawTitle) {
            return parserTitle
        }

        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? nil : trimmedTitle
    }

    private static let uuidRegex = try? NSRegularExpression(
        pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
        options: [.caseInsensitive]
    )

    private func isUUID(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return Self.uuidRegex?.firstMatch(in: value, range: range) != nil
    }

    private static let uuidSearchRegex = try? NSRegularExpression(
        pattern: "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        options: [.caseInsensitive]
    )

    private func codexSessionIDFromPath(_ path: String) -> String? {
        let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let range = NSRange(fileName.startIndex..., in: fileName)
        guard
            let match = Self.uuidSearchRegex?.firstMatch(in: fileName, range: range),
            let matchRange = Range(match.range, in: fileName)
        else {
            return nil
        }
        return String(fileName[matchRange])
    }
}
