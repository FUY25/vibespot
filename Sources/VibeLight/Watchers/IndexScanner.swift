import Foundation

struct IndexScanner {
    let sessionIndex: SessionIndex
    let homeDirectoryPath: String

    private var processedFiles: Set<String> = []
    private var codexTitleMap: [String: String] = [:]

    init(sessionIndex: SessionIndex, homeDirectoryPath: String) {
        self.sessionIndex = sessionIndex
        self.homeDirectoryPath = homeDirectoryPath
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
        let projectsPath = homeDirectoryPath + "/.claude/projects"
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
            let metadataBySessionId = claudeSessionMetadataBySessionId(in: projectDirectoryURL)

            for meta in metadataBySessionId.values {
                if Task.isCancelled {
                    return
                }
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
                if Task.isCancelled {
                    return
                }
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

    mutating func scanCodexSessions() {
        guard !Task.isCancelled else {
            return
        }
        codexTitleMap = loadCodexTitleMap()
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
        let title = normalizedDisplayTitle(from: meta.title) ?? "Untitled"

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
        preferredTitle: String? = nil
    ) {
        guard !Task.isCancelled else {
            return
        }
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
        if fileMtimeDidChange(at: path, expected: mtime) {
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
        if let sessionIdFromPath = codexSessionIDFromPath(path),
           shouldSkipFile(path: path, sessionId: sessionIdFromPath) {
            return
        }
        let parseStartMtime = fileMtime(at: path)

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
        if fileMtimeDidChange(at: path, expected: parseStartMtime) {
            return
        }
        let mtime = parseStartMtime ?? fileMtime(at: path)

        let title = titleMap[sessionId]
            ?? SessionTitleNormalizer.firstMeaningfulDisplayTitle(in: messages)
            ?? "Untitled"
        let cwd = (meta?.cwd ?? messages.compactMap(\.cwd).first ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let metrics = sessionMetrics(from: messages, filePath: path)

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

    private func fileMtime(at path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }

    private func shouldSkipFile(path: String, sessionId: String) -> Bool {
        guard let currentMtime = fileMtime(at: path) else { return false }
        guard let storedMtime = try? sessionIndex.lastIndexedMtime(sessionId: sessionId) else { return false }
        return currentMtime == storedMtime
    }

    private func fileMtimeDidChange(at path: String, expected: Date?) -> Bool {
        guard let expected else {
            return false
        }
        guard let currentMtime = fileMtime(at: path) else {
            return true
        }
        return currentMtime != expected
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
