import Foundation

// Adapted from Poirot (MIT License, Copyright 2026 Leonardo Cardoso)
// Flattened for transcript indexing instead of in-memory UI rendering.
enum ClaudeParser {
    static func parseSessionFile(url: URL) throws -> [ParsedMessage] {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard !text.isEmpty else {
            return []
        }

        var messages: [ParsedMessage] = []
        for line in text.split(whereSeparator: \.isNewline) {
            guard let record = jsonObject(from: String(line)) else {
                continue
            }

            guard let type = record["type"] as? String, type == "user" || type == "assistant" else {
                continue
            }

            if boolValue(record["isSidechain"]) == true {
                continue
            }

            if type == "user", boolValue(record["isMeta"]) == true {
                continue
            }

            let message = record["message"] as? [String: Any] ?? [:]
            if type == "assistant", message["model"] as? String == "<synthetic>" {
                continue
            }

            let timestamp = parseDate(record["timestamp"]) ?? .distantPast
            let sessionId = record["sessionId"] as? String
            let gitBranch = record["gitBranch"] as? String
            let cwd = record["cwd"] as? String

            switch type {
            case "user":
                let content = flattenUserContent(message["content"])
                guard !content.isEmpty else {
                    continue
                }
                messages.append(
                    ParsedMessage(
                        role: "user",
                        content: content,
                        timestamp: timestamp,
                        toolCalls: [],
                        sessionId: sessionId,
                        gitBranch: gitBranch,
                        cwd: cwd
                    )
                )
            case "assistant":
                let parsedContent = flattenAssistantContent(message["content"])
                guard !parsedContent.text.isEmpty || !parsedContent.toolCalls.isEmpty else {
                    continue
                }
                messages.append(
                    ParsedMessage(
                        role: "assistant",
                        content: parsedContent.text,
                        timestamp: timestamp,
                        toolCalls: parsedContent.toolCalls,
                        sessionId: sessionId,
                        gitBranch: gitBranch,
                        cwd: cwd
                    )
                )
            default:
                continue
            }
        }

        return messages
    }

    static func parseSessionsIndex(url: URL) throws -> [ParsedSessionMeta] {
        let data = try Data(contentsOf: url)
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = json["entries"] as? [[String: Any]]
        else {
            return []
        }

        return entries.compactMap { entry in
            guard let sessionId = entry["sessionId"] as? String else {
                return nil
            }

            let title = (entry["summary"] as? String)?.nonEmpty
                ?? (entry["firstPrompt"] as? String)?.nonEmpty
                ?? "Untitled"

            return ParsedSessionMeta(
                sessionId: sessionId,
                title: title,
                firstPrompt: entry["firstPrompt"] as? String,
                projectPath: entry["projectPath"] as? String ?? "",
                gitBranch: entry["gitBranch"] as? String ?? "",
                startedAt: parseDate(entry["created"]) ?? .distantPast,
                isSidechain: boolValue(entry["isSidechain"]) ?? false
            )
        }
    }

    static func parseHistory(url: URL) throws -> [ParsedHistoryEntry] {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard !text.isEmpty else {
            return []
        }

        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let record = jsonObject(from: String(line)) else {
                return nil
            }

            guard
                let prompt = (record["display"] as? String)?.nonEmpty,
                let project = record["project"] as? String,
                let timestamp = parseMillisecondsDate(record["timestamp"])
            else {
                return nil
            }

            return ParsedHistoryEntry(
                sessionId: record["sessionId"] as? String ?? "",
                prompt: prompt,
                project: project,
                timestamp: timestamp
            )
        }
    }

    static func parsePidFile(url: URL) throws -> ParsedPidEntry {
        let data = try Data(contentsOf: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeParserError.invalidPidFile
        }

        guard
            let pid = intValue(json["pid"]),
            let sessionId = json["sessionId"] as? String,
            let cwd = json["cwd"] as? String,
            let startedAt = parseMillisecondsDate(json["startedAt"])
        else {
            throw ClaudeParserError.invalidPidFile
        }

        return ParsedPidEntry(pid: pid, sessionId: sessionId, cwd: cwd, startedAt: startedAt)
    }

    static func decodeProjectPath(_ encoded: String) -> String {
        decodeProjectPath(
            encoded,
            projectsRoot: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude/projects", isDirectory: true)
        )
    }

    static func decodeProjectPath(_ encoded: String, projectsRoot: URL) -> String {
        if let projectPath = projectPathFromEncodedDirectory(encoded, projectsRoot: projectsRoot) {
            return projectPath
        }

        return fallbackDecodeProjectPath(encoded)
    }

    private static func projectPathFromEncodedDirectory(_ encoded: String, projectsRoot: URL) -> String? {
        guard !encoded.isEmpty else {
            return nil
        }

        let fileManager = FileManager.default
        let encodedDirectory = projectsRoot.appendingPathComponent(encoded, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: encodedDirectory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return nil
        }

        let sessionsIndexURL = encodedDirectory.appendingPathComponent("sessions-index.json")
        if let projectPath = projectPathFromSessionsIndex(url: sessionsIndexURL) {
            return projectPath
        }

        return projectPathFromSessionJSONL(directory: encodedDirectory)
    }

    private static func projectPathFromSessionsIndex(url: URL) -> String? {
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let entries = json["entries"] as? [[String: Any]]
        else {
            return nil
        }

        for entry in entries {
            if let projectPath = (entry["projectPath"] as? String)?.nonEmpty {
                return projectPath
            }
        }

        return nil
    }

    private static func projectPathFromSessionJSONL(directory: URL) -> String? {
        let fileManager = FileManager.default
        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        let sortedJSONLFiles = fileURLs
            .filter { $0.pathExtension == "jsonl" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for fileURL in sortedJSONLFiles {
            guard let text = try? String(contentsOf: fileURL, encoding: .utf8) else {
                continue
            }

            for line in text.split(whereSeparator: \.isNewline) {
                guard
                    let record = jsonObject(from: String(line)),
                    let cwd = (record["cwd"] as? String)?.nonEmpty
                else {
                    continue
                }

                return cwd
            }
        }

        return nil
    }

    private static func fallbackDecodeProjectPath(_ encoded: String) -> String {
        guard !encoded.isEmpty else {
            return "/"
        }

        let trimmed = encoded.hasPrefix("-") ? String(encoded.dropFirst()) : encoded
        if trimmed.isEmpty {
            return "/"
        }

        return "/" + trimmed.replacingOccurrences(of: "-", with: "/")
    }

    private static func jsonObject(from line: String) -> [String: Any]? {
        ParserUtilities.jsonObject(from: line)
    }

    private static func flattenUserContent(_ rawContent: Any?) -> String {
        if let content = rawContent as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard let blocks = rawContent as? [[String: Any]] else {
            return ""
        }

        let parts = blocks.compactMap { block -> String? in
            switch block["type"] as? String {
            case "text":
                return (block["text"] as? String)?.nonEmpty
            case "tool_result":
                return flattenToolResult(block["content"])
            default:
                return nil
            }
        }

        return joinNonEmpty(parts)
    }

    private static func flattenAssistantContent(_ rawContent: Any?) -> (text: String, toolCalls: [String]) {
        if let content = rawContent as? String {
            return (content.trimmingCharacters(in: .whitespacesAndNewlines), [])
        }

        guard let blocks = rawContent as? [[String: Any]] else {
            return ("", [])
        }

        var textParts: [String] = []
        var toolCalls: [String] = []

        for block in blocks {
            switch block["type"] as? String {
            case "text":
                if let text = (block["text"] as? String)?.nonEmpty {
                    textParts.append(text)
                }
            case "tool_use":
                if let toolCall = flattenToolCall(block), !toolCall.isEmpty {
                    toolCalls.append(toolCall)
                }
            case "thinking":
                continue
            default:
                continue
            }
        }

        return (joinNonEmpty(textParts), toolCalls)
    }

    private static func flattenToolCall(_ block: [String: Any]) -> String? {
        guard let name = block["name"] as? String else {
            return nil
        }

        let input = block["input"] as? [String: Any] ?? [:]
        let detail = firstString(
            input["file_path"],
            input["path"],
            input["command"],
            input["prompt"],
            input["description"]
        )

        if let detail, !detail.isEmpty {
            return "\(name): \(detail)"
        }

        return name
    }

    private static func flattenToolResult(_ rawContent: Any?) -> String {
        if let content = rawContent as? String {
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let dict = rawContent as? [String: Any] {
            if let text = firstString(dict["text"], dict["content"]), !text.isEmpty {
                return text
            }
            return ""
        }

        guard let blocks = rawContent as? [[String: Any]] else {
            return ""
        }

        let textParts = blocks.compactMap { block -> String? in
            switch block["type"] as? String {
            case "text":
                return (block["text"] as? String)?.nonEmpty
            default:
                return nil
            }
        }

        return joinNonEmpty(textParts)
    }

    private static func parseDate(_ rawValue: Any?) -> Date? {
        ParserUtilities.parseISO8601Date(rawValue)
    }

    private static func parseMillisecondsDate(_ rawValue: Any?) -> Date? {
        guard let milliseconds = doubleValue(rawValue) else {
            return nil
        }

        return Date(timeIntervalSince1970: milliseconds / 1000.0)
    }

    private static func boolValue(_ rawValue: Any?) -> Bool? {
        if let value = rawValue as? Bool {
            return value
        }

        if let value = rawValue as? NSNumber {
            return value.boolValue
        }

        return nil
    }

    private static func intValue(_ rawValue: Any?) -> Int? {
        if let value = rawValue as? Int {
            return value
        }

        if let value = rawValue as? NSNumber {
            return value.intValue
        }

        if let value = rawValue as? String {
            return Int(value)
        }

        return nil
    }

    private static func doubleValue(_ rawValue: Any?) -> Double? {
        if let value = rawValue as? Double {
            return value
        }

        if let value = rawValue as? NSNumber {
            return value.doubleValue
        }

        if let value = rawValue as? String {
            return Double(value)
        }

        return nil
    }

    private static func firstString(_ values: Any?...) -> String? {
        for value in values {
            if let string = value as? String, !string.isEmpty {
                return string
            }
        }
        return nil
    }

    private static func joinNonEmpty(_ values: [String]) -> String {
        values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

enum ClaudeParserError: Error {
    case invalidPidFile
}
