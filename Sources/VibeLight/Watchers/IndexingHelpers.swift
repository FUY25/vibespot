import Foundation

enum IndexingHelpers {
    static func searchableContent(from message: ParsedMessage) -> String {
        let combined = [message.content] + message.toolCalls
        return combined
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    static func sessionMetrics(
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

        if lastMessage.role == "user" {
            return (tokenCount, lastActivityAt, lastFileModification, "user", nil)
        }

        let trimmedContent = lastMessage.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if lastMessage.role == "assistant",
           !trimmedContent.isEmpty,
           assistantMessageNeedsUserInput(trimmedContent) {
            return (
                tokenCount,
                lastActivityAt,
                lastFileModification,
                "assistant",
                ActivityPreview(
                    text: condensedPreviewText(from: trimmedContent),
                    kind: .assistant
                )
            )
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

    static func approximateTokenCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return 0
        }

        return max(1, Int(ceil(Double(trimmed.count) / 4.0)))
    }

    static func previewForToolCall(_ toolCall: String) -> ActivityPreview {
        let normalized = condensedPreviewText(from: toolCall)
        if isFileEditToolCall(normalized) {
            return ActivityPreview(text: "✎ Editing \(normalized)", kind: .fileEdit)
        }

        return ActivityPreview(text: "▶ Running \(normalized)", kind: .tool)
    }

    private static let fileEditToolNames: Set<String> = [
        "apply_patch",
        "edit",
        "multiedit",
        "replace",
        "str_replace_editor",
        "write",
    ]

    private static func isFileEditToolCall(_ toolCall: String) -> Bool {
        let lower = toolCall.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }

        for name in fileEditToolNames {
            if lower.hasPrefix("\(name):")
                || lower.hasPrefix("\(name) ")
                || lower.hasPrefix("\(name)(")
                || lower.contains("\"name\":\"\(name)\"")
                || lower.contains("\"name\": \"\(name)\"")
            {
                return true
            }
        }

        return false
    }

    static func condensedPreviewText(from text: String, limit: Int = 80) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        if normalized.count <= limit {
            return normalized
        }

        return String(normalized.prefix(limit - 1)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    static func assistantMessageNeedsUserInput(_ text: String) -> Bool {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !normalized.isEmpty else { return false }

        let lower = normalized.lowercased()
        let directSignals = [
            "waiting for user",
            "need your input",
            "need your confirmation",
            "please confirm",
            "need your approval",
            "requires your approval",
            "please approve",
            "can you approve",
            "could you approve",
            "would you approve",
            "do you approve",
            "please allow write",
            "can you allow write",
            "could you allow write",
            "would you allow write",
            "need permission to",
            "requires your permission",
            "grant permission",
            "please grant access",
            "can you grant access",
        ]
        if directSignals.contains(where: { lower.contains($0) }) {
            return true
        }

        let questionSignals = [
            "which",
            "what",
            "do you",
            "should i",
            "can you",
            "could you",
            "would you",
            "prefer",
            "want",
            "choose",
            "pick",
            "confirm",
            "approve",
            "allow",
        ]

        var cursor = normalized.startIndex
        while let questionMark = normalized[cursor...].firstIndex(of: "?") {
            let sentenceStart = normalized[..<questionMark]
                .lastIndex(where: { ".!?\n".contains($0) })
                .map { normalized.index(after: $0) } ?? normalized.startIndex
            let question = normalized[sentenceStart...questionMark]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            if questionSignals.contains(where: { question.contains($0) }) {
                return true
            }
            if isYesNoApprovalQuestion(question) {
                return true
            }
            cursor = normalized.index(after: questionMark)
        }

        return false
    }

    private static let yesNoQuestionPrefixes = [
        "is ",
        "are ",
        "was ",
        "were ",
        "did ",
        "does ",
        "do ",
        "can ",
        "could ",
        "would ",
        "will ",
        "should ",
        "has ",
        "have ",
        "had ",
    ]

    private static let approvalQuestionCues = [
        " ok",
        " okay",
        " good",
        " right",
        " correct",
        " fix",
        " fixed",
        " work",
        " working",
        " layout",
        " looks",
        " look",
        " approve",
    ]

    private static func isYesNoApprovalQuestion(_ question: String) -> Bool {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard yesNoQuestionPrefixes.contains(where: { trimmed.hasPrefix($0) }) else { return false }

        let padded = " \(trimmed)"
        return approvalQuestionCues.contains(where: { padded.contains($0) })
    }

    static func normalizedDisplayTitle(from rawTitle: String) -> String? {
        if let displayTitle = SessionTitleNormalizer.displayTitleCandidate(from: rawTitle) {
            return displayTitle
        }

        if let parserTitle = SessionTitleNormalizer.titleCandidate(from: rawTitle) {
            return parserTitle
        }

        let trimmedTitle = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedTitle.isEmpty ? nil : trimmedTitle
    }

    static func fileMtime(at path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date
    }

    static func shouldSkipFile(path: String, sessionId: String, sessionIndex: SessionIndex) -> Bool {
        guard let currentMtime = fileMtime(at: path) else { return false }
        guard let storedMtime = try? sessionIndex.lastIndexedMtime(sessionId: sessionId) else { return false }
        return currentMtime == storedMtime
    }

    static func claudeSessionMetadataBySessionId(in projectDirectoryURL: URL) -> [String: ParsedSessionMeta] {
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

    static func claudeRawSessionFileExists(sessionId: String, in projectDirectoryURL: URL) -> Bool {
        guard !sessionId.isEmpty else {
            return false
        }

        let rawSessionURL = projectDirectoryURL.appendingPathComponent(sessionId).appendingPathExtension("jsonl")
        return FileManager.default.fileExists(atPath: rawSessionURL.path)
    }

    private static let uuidRegex = try? NSRegularExpression(
        pattern: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
        options: [.caseInsensitive]
    )

    static func isUUID(_ value: String) -> Bool {
        let range = NSRange(value.startIndex..., in: value)
        return uuidRegex?.firstMatch(in: value, range: range) != nil
    }

    private static let uuidSearchRegex = try? NSRegularExpression(
        pattern: "[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        options: [.caseInsensitive]
    )

    static func codexSessionIDFromPath(_ path: String) -> String? {
        let fileName = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
        let range = NSRange(fileName.startIndex..., in: fileName)
        guard
            let match = uuidSearchRegex?.firstMatch(in: fileName, range: range),
            let matchRange = Range(match.range, in: fileName)
        else {
            return nil
        }
        return String(fileName[matchRange])
    }

    static func loadCodexTitleMap(homeDirectoryPath: String) -> [String: String] {
        let indexURL = URL(fileURLWithPath: homeDirectoryPath + "/.codex/session_index.jsonl")
        let metas = (try? CodexParser.parseSessionIndex(url: indexURL)) ?? []

        var titleMap: [String: String] = [:]
        for meta in metas {
            let title = normalizedDisplayTitle(from: meta.title) ?? "Untitled"
            titleMap[meta.sessionId] = title
        }
        return titleMap
    }
}
