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

    static func approximateTokenCount(for text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return 0
        }

        return max(1, Int(ceil(Double(trimmed.count) / 4.0)))
    }

    static func previewForToolCall(_ toolCall: String) -> ActivityPreview {
        let normalized = condensedPreviewText(from: toolCall)
        let lowercased = normalized.lowercased()

        if lowercased.contains("edit") || lowercased.contains("write") || lowercased.contains("apply_patch") {
            return ActivityPreview(text: "✎ Editing \(normalized)", kind: .fileEdit)
        }

        return ActivityPreview(text: "▶ Running \(normalized)", kind: .tool)
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
