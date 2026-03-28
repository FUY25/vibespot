import Foundation

enum CodexParser {
    static func parseSessionIndex(url: URL) throws -> [ParsedSessionMeta] {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard !text.isEmpty else {
            return []
        }

        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard
                let record = jsonObject(from: String(line)),
                let id = record["id"] as? String
            else {
                return nil
            }

            let title = nonEmptyString(record["thread_name"]) ?? "Untitled"
            let updatedAt = parseDate(record["updated_at"]) ?? .distantPast

            return ParsedSessionMeta(
                sessionId: id,
                title: title,
                firstPrompt: nil,
                projectPath: "",
                gitBranch: "",
                startedAt: updatedAt,
                isSidechain: false
            )
        }
    }

    static func parseSessionFile(url: URL) throws -> (meta: CodexSessionMeta?, messages: [ParsedMessage]) {
        let text = try String(contentsOf: url, encoding: .utf8)
        guard !text.isEmpty else {
            return (nil, [])
        }

        var meta: CodexSessionMeta?
        var messages: [ParsedMessage] = []

        for line in text.split(whereSeparator: \.isNewline) {
            guard
                let record = jsonObject(from: String(line)),
                let type = record["type"] as? String
            else {
                continue
            }

            let timestamp = parseDate(record["timestamp"]) ?? .distantPast

            switch type {
            case "session_meta":
                guard let payload = record["payload"] as? [String: Any] else {
                    continue
                }
                let source = payload["source"] as? [String: Any]
                let isSubagent = source?["subagent"] != nil

                meta = CodexSessionMeta(
                    id: nonEmptyString(payload["id"]) ?? "",
                    cwd: nonEmptyString(payload["cwd"]),
                    cliVersion: nonEmptyString(payload["cli_version"]) ?? "",
                    source: nonEmptyString(payload["source"]) ?? nonEmptyString(payload["originator"]) ?? "cli",
                    isSubagent: isSubagent
                )

            case "response_item":
                guard
                    let payload = record["payload"] as? [String: Any],
                    let payloadType = payload["type"] as? String
                else {
                    continue
                }

                switch payloadType {
                case "message":
                    guard let role = payload["role"] as? String, role != "developer" else {
                        continue
                    }

                    let content = flattenContent(payload["content"])
                    guard !content.isEmpty else {
                        continue
                    }

                    let mappedRole = role == "user" ? "user" : "assistant"
                    messages.append(
                        ParsedMessage(
                            role: mappedRole,
                            content: content,
                            timestamp: timestamp,
                            toolCalls: [],
                            sessionId: meta?.id,
                            gitBranch: nil,
                            cwd: meta?.cwd
                        )
                    )
                case "function_call", "custom_tool_call":
                    guard let toolCall = flattenToolCall(payload) else {
                        continue
                    }

                    messages.append(
                        ParsedMessage(
                            role: "assistant",
                            content: "",
                            timestamp: timestamp,
                            toolCalls: [toolCall],
                            sessionId: meta?.id,
                            gitBranch: nil,
                            cwd: meta?.cwd
                        )
                    )

                case "function_call_output", "custom_tool_call_output":
                    let content = flattenToolOutput(payload["output"])
                    guard !content.isEmpty else {
                        continue
                    }

                    messages.append(
                        ParsedMessage(
                            role: "assistant",
                            content: content,
                            timestamp: timestamp,
                            toolCalls: [],
                            sessionId: meta?.id,
                            gitBranch: nil,
                            cwd: meta?.cwd
                        )
                    )

                default:
                    continue
                }

            default:
                continue
            }
        }

        return (meta, messages)
    }

    private static func jsonObject(from line: String) -> [String: Any]? {
        ParserUtilities.jsonObject(from: line)
    }

    private static func parseDate(_ rawValue: Any?) -> Date? {
        ParserUtilities.parseISO8601Date(rawValue)
    }

    private static func flattenContent(_ rawContent: Any?) -> String {
        if let text = nonEmptyString(rawContent) {
            return text
        }

        guard let blocks = rawContent as? [[String: Any]] else {
            return ""
        }

        let parts = blocks.compactMap { block -> String? in
            switch block["type"] as? String {
            case "input_text", "output_text", "text":
                return nonEmptyString(block["text"])
            default:
                return nil
            }
        }

        return parts.joined(separator: "\n")
    }

    private static func flattenToolCall(_ payload: [String: Any]) -> String? {
        guard let name = nonEmptyString(payload["name"]) else {
            return nil
        }

        let detail = firstNonEmptyString(
            stringifyValue(payload["arguments"]),
            stringifyValue(payload["input"]),
            nonEmptyString(payload["command"]),
            nonEmptyString(payload["prompt"]),
            nonEmptyString(payload["description"])
        )

        guard let detail else {
            return name
        }

        return "\(name): \(detail)"
    }

    private static func flattenToolOutput(_ rawOutput: Any?) -> String {
        if let text = nonEmptyString(rawOutput) {
            if
                let parsed = jsonObject(from: text),
                let nestedText = firstNonEmptyString(
                    nonEmptyString(parsed["output"]),
                    nonEmptyString(parsed["text"]),
                    nonEmptyString(parsed["content"])
                )
            {
                return nestedText
            }

            return text
        }

        if let object = rawOutput as? [String: Any] {
            return firstNonEmptyString(
                nonEmptyString(object["output"]),
                nonEmptyString(object["text"]),
                nonEmptyString(object["content"]),
                flattenContent(object["content"])
            ) ?? ""
        }

        return flattenContent(rawOutput)
    }

    private static func stringifyValue(_ value: Any?) -> String? {
        if let text = nonEmptyString(value) {
            return text
        }

        guard let value else {
            return nil
        }

        guard JSONSerialization.isValidJSONObject(value) else {
            return nil
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: value),
            let text = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return nonEmptyString(text)
    }

    private static func firstNonEmptyString(_ values: String?...) -> String? {
        for value in values {
            if let value {
                return value
            }
        }
        return nil
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        (value as? String)?.nonEmpty
    }
}
