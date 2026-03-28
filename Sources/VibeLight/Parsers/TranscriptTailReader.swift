// Sources/VibeLight/Parsers/TranscriptTailReader.swift
import Foundation

struct PreviewExchange: Sendable {
    let role: String     // "user" | "assistant"
    let text: String
    let isError: Bool
}

struct PreviewData: Sendable {
    let headline: String?
    let exchanges: [PreviewExchange]
    let files: [String]  // full paths, most recent first
}

enum TranscriptTailReader {
    private static let initialTailReadSize: UInt64 = 4096
    private static let maxTailReadSize: UInt64 = 65536

    private static let assistantActionPrefixes = [
        "running ",
        "checking ",
        "updating ",
        "editing ",
        "applying ",
        "investigating ",
        "analyzing ",
        "building ",
        "testing ",
        "implementing ",
        "searching ",
        "reading ",
        "writing ",
        "refactoring ",
        "reviewing ",
    ]

    private struct TailMessage: Sendable {
        let role: String
        let text: String
        let isError: Bool
    }

    private struct ParsedTailData: Sendable {
        let exchangesNewestFirst: [PreviewExchange]
        let messagesNewestFirst: [TailMessage]
        let files: [String]
    }

    private enum HeadlineSignal {
        case waiting(String)
        case error(String)
        case action(String)
    }

    static func read(fileURL: URL, exchangeCount: Int = 3) -> PreviewData {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return PreviewData(headline: nil, exchanges: [], files: [])
        }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let safeExchangeCount = max(0, exchangeCount)

        var readSize = min(fileSize, initialTailReadSize)
        var parsed = ParsedTailData(exchangesNewestFirst: [], messagesNewestFirst: [], files: [])
        var compactExchanges: [PreviewExchange] = []
        var headline: String?

        while true {
            handle.seek(toFileOffset: fileSize - readSize)
            let data = handle.readData(ofLength: Int(readSize))
            guard let text = String(data: data, encoding: .utf8) else {
                return PreviewData(headline: nil, exchanges: [], files: [])
            }
            parsed = parseTailText(text)

            let meaningfulExchanges = parsed.exchangesNewestFirst
                .reversed()
                .filter { isMeaningfulExchange(role: $0.role, text: $0.text) }
            let meaningfulCount = meaningfulExchanges.count
            compactExchanges = Array(meaningfulExchanges.suffix(safeExchangeCount))
            headline = deriveHeadline(from: parsed.messagesNewestFirst, exchanges: compactExchanges)
            let reachedBound = readSize >= fileSize || readSize >= maxTailReadSize
            let hasEnoughExchangeContext = meaningfulCount >= safeExchangeCount
            if (hasEnoughExchangeContext && headline != nil) || reachedBound {
                break
            }

            let nextReadSize = min(maxTailReadSize, min(fileSize, readSize * 2))
            if nextReadSize == readSize {
                break
            }
            readSize = nextReadSize
        }

        return PreviewData(
            headline: headline,
            exchanges: compactExchanges,
            files: Array(parsed.files.prefix(5))
        )
    }

    static func extractLastUserPrompt(fileURL: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else {
            return nil
        }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        var readSize = min(fileSize, initialTailReadSize * 2)
        while true {
            handle.seek(toFileOffset: fileSize - readSize)
            let data = handle.readData(ofLength: Int(readSize))

            guard let text = String(data: data, encoding: .utf8) else {
                return nil
            }

            if let prompt = extractLastUserPrompt(fromTailText: text) {
                return prompt
            }

            let reachedBound = readSize >= fileSize || readSize >= maxTailReadSize
            if reachedBound {
                break
            }
            let nextReadSize = min(maxTailReadSize, min(fileSize, readSize * 2))
            if nextReadSize == readSize {
                break
            }
            readSize = nextReadSize
        }

        return nil
    }

    static func previewToJSONString(_ preview: PreviewData) -> String {
        var exchangeArray: [[String: Any]] = []
        for ex in preview.exchanges {
            exchangeArray.append([
                "role": ex.role,
                "text": ex.text,
                "isError": ex.isError,
            ])
        }

        let dict: [String: Any] = [
            "headline": preview.headline ?? NSNull(),
            "exchanges": exchangeArray,
            "files": preview.files,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            return "{\"headline\":null,\"exchanges\":[],\"files\":[]}"
        }
        return string
    }

    private static func deriveHeadline(from messagesNewestFirst: [TailMessage], exchanges: [PreviewExchange]) -> String? {
        if let signal = latestStateSignal(in: messagesNewestFirst) {
            switch signal {
            case .waiting(let prompt):
                return "Waiting: \(prompt)"
            case .error(let summary):
                return "Error: \(summary)"
            case .action(let action):
                return action
            }
        }
        if let latestUserAsk = latestMeaningfulUserAsk(in: messagesNewestFirst, exchanges: exchanges) {
            return "Current task: \(latestUserAsk)"
        }
        return nil
    }

    private static func latestStateSignal(in messagesNewestFirst: [TailMessage]) -> HeadlineSignal? {
        for message in messagesNewestFirst {
            if message.role == "assistant",
               let prompt = waitingPromptCandidate(from: message.text) {
                return .waiting(prompt)
            }

            if message.role == "assistant" {
                let text = message.text
                if isAssistantErrorStateMessage(text) {
                    let summary = conciseSnippet(from: strippingErrorPrefix(from: text), maxLength: 160)
                    return .error(summary)
                }
                if isAssistantActionUpdate(text),
                   waitingPromptCandidate(from: text) == nil,
                   !isAssistantStatusChatter(text) {
                    return .action(conciseSnippet(from: text, maxLength: 160))
                }
            }

            if isSubstantiveNeutralStateMessage(message) {
                return nil
            }
        }
        return nil
    }

    private static func isSubstantiveNeutralStateMessage(_ message: TailMessage) -> Bool {
        let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard message.role == "assistant" || message.role == "user" else { return false }

        if message.role == "assistant", isAssistantStatusChatter(trimmed) {
            return false
        }

        return true
    }

    private static func latestMeaningfulUserAsk(
        in messagesNewestFirst: [TailMessage],
        exchanges: [PreviewExchange]
    ) -> String? {
        for message in messagesNewestFirst where message.role == "user" {
            if let title = SessionTitleNormalizer.displayTitleCandidate(from: message.text) {
                return conciseSnippet(from: title, maxLength: 160)
            }
        }

        for exchange in exchanges.reversed() where exchange.role == "user" {
            if let title = SessionTitleNormalizer.displayTitleCandidate(from: exchange.text) {
                return conciseSnippet(from: title, maxLength: 160)
            }
        }

        return nil
    }

    private static func waitingPromptCandidate(from text: String) -> String? {
        let normalized = normalizeWhitespace(in: text)
        guard !normalized.isEmpty else { return nil }
        guard IndexingHelpers.assistantMessageNeedsUserInput(normalized) else {
            return nil
        }

        if let question = firstQuestionSentence(in: normalized) {
            return conciseSnippet(from: question, maxLength: 160)
        }

        return conciseSnippet(from: normalized, maxLength: 160)
    }

    private static func firstQuestionSentence(in text: String) -> String? {
        guard let questionMarkIndex = text.firstIndex(of: "?") else {
            return nil
        }

        let sentenceStart = text[..<questionMarkIndex]
            .lastIndex(where: { ".!?\n".contains($0) })
            .map { text.index(after: $0) } ?? text.startIndex
        let sentence = text[sentenceStart...questionMarkIndex]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sentence.isEmpty ? nil : sentence
    }

    private static func isErrorText(_ text: String) -> Bool {
        let lower = text.lowercased()
        let errorSignals = [
            "api error:",
            "\"type\":\"invalid_request_error\"",
            "invalid_request_error",
            "error:",
            " failed ",
            "failed:",
            "exception",
            "traceback",
            "fatal:",
        ]
        return errorSignals.contains(where: { lower.contains($0) })
    }

    private static func strippingErrorPrefix(from text: String) -> String {
        let prefixes = ["API Error:", "Error:"]
        for prefix in prefixes where text.hasPrefix(prefix) {
            return text.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private static func conciseSnippet(from text: String, maxLength: Int) -> String {
        let normalized = normalizeWhitespace(in: text)
        guard normalized.count > maxLength else { return normalized }
        let index = normalized.index(normalized.startIndex, offsetBy: maxLength)
        return String(normalized[..<index]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isMeaningfulExchange(role: String, text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard role == "assistant" else { return true }

        guard !isErrorText(trimmed), waitingPromptCandidate(from: trimmed) == nil else {
            return true
        }

        return !isAssistantStatusChatter(trimmed)
    }

    private static func isAssistantStatusChatter(_ text: String) -> Bool {
        guard isAssistantActionUpdate(text) else {
            return false
        }

        let normalized = normalizeWhitespace(in: text).lowercased()
        let genericSignals = [
            "quick checks",
            "focused checks",
            "parser checks",
            "nearby files",
            "for context",
            "summary formatting",
        ]

        if genericSignals.contains(where: { normalized.contains($0) }) {
            return true
        }

        return false
    }

    private static func isAssistantActionUpdate(_ text: String) -> Bool {
        let lower = text.lowercased()
        return assistantActionPrefixes.contains(where: { lower.hasPrefix($0) })
    }

    private static func isAssistantErrorStateMessage(_ text: String) -> Bool {
        guard waitingPromptCandidate(from: text) == nil else { return false }
        let normalized = normalizeWhitespace(in: text)
        guard !normalized.isEmpty else { return false }

        let lower = normalized.lowercased()
        guard let activeSignal = firstActiveAssistantErrorSignal(in: lower) else { return false }
        guard !containsResolvedErrorContext(lower) else {
            return isFreshFailureAfterResolvedContext(lower, activeSignal: activeSignal)
        }

        return true
    }

    private static func isExchangeError(role: String, text: String) -> Bool {
        guard role == "assistant" else { return false }
        return isAssistantErrorStateMessage(text)
    }

    private static func argumentObject(from payload: [String: Any]) -> [String: Any] {
        if let arguments = payload["arguments"] as? [String: Any] {
            return arguments
        }
        if let argumentsString = payload["arguments"] as? String,
           let object = jsonObject(from: argumentsString) {
            return object
        }
        if let input = payload["input"] as? [String: Any] {
            return input
        }
        if let inputString = payload["input"] as? String,
           let object = jsonObject(from: inputString) {
            return object
        }
        return [:]
    }

    private static func jsonObject(from line: String) -> [String: Any]? {
        ParserUtilities.jsonObject(from: line)
    }

    private static func extractText(from content: Any?) -> String {
        if let text = content as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { block -> String? in
            let t = block["type"] as? String
            if t == "text" || t == "input_text" || t == "output_text" { return block["text"] as? String }
            return nil
        }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Extract only actual user-typed text from Claude message content,
    /// excluding tool_result blocks that are sent back as "user" messages.
    private static func extractUserOnlyText(from content: Any?) -> String {
        if let text = content as? String { return text.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let blocks = content as? [[String: Any]] else { return "" }
        return blocks.compactMap { block -> String? in
            guard block["type"] as? String == "text" else { return nil }
            return block["text"] as? String
        }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeWhitespace(in value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func parseTailText(_ text: String) -> ParsedTailData {
        var exchangesNewestFirst: [PreviewExchange] = []
        var messagesNewestFirst: [TailMessage] = []
        var files: [String] = []
        var seenFiles = Set<String>()

        let lines = text.split(whereSeparator: \.isNewline).reversed()
        for line in lines {
            guard let record = jsonObject(from: String(line)) else { continue }
            guard let type = record["type"] as? String else { continue }

            // Claude format: type == "user" | "assistant", message.content holds text
            if type == "user" || type == "assistant" {
                let message = record["message"] as? [String: Any] ?? [:]
                let content = type == "user"
                    ? extractUserOnlyText(from: message["content"])
                    : extractText(from: message["content"])
                if !content.isEmpty {
                    let normalized = normalizeWhitespace(in: content)
                    let isError = isExchangeError(role: type, text: normalized)
                    messagesNewestFirst.append(TailMessage(role: type, text: normalized, isError: isError))
                    exchangesNewestFirst.append(
                        PreviewExchange(role: type, text: String(normalized.prefix(200)), isError: isError)
                    )
                }
            }

            // Codex format: type == "response_item", payload.type == "message", payload.role + payload.content
            if type == "response_item",
               let payload = record["payload"] as? [String: Any],
               let payloadType = payload["type"] as? String, payloadType == "message",
               let role = payload["role"] as? String, role == "user" || role == "assistant" {
                let content = extractText(from: payload["content"])
                if !content.isEmpty {
                    let normalized = normalizeWhitespace(in: content)
                    let isError = isExchangeError(role: role, text: normalized)
                    messagesNewestFirst.append(TailMessage(role: role, text: normalized, isError: isError))
                    exchangesNewestFirst.append(
                        PreviewExchange(role: role, text: String(normalized.prefix(200)), isError: isError)
                    )
                }
            }

            // Extract file paths from tool_use (Claude format)
            if type == "assistant" {
                let message = record["message"] as? [String: Any] ?? [:]
                if let blocks = message["content"] as? [[String: Any]] {
                    for block in blocks {
                        if block["type"] as? String == "tool_use",
                           let input = block["input"] as? [String: Any] {
                            let path = (input["file_path"] as? String) ?? (input["path"] as? String) ?? ""
                            if !path.isEmpty && !seenFiles.contains(path) && files.count < 5 {
                                seenFiles.insert(path)
                                files.append(path)
                            }
                        }
                    }
                }
            }

            // Extract file paths from function_call (Codex format)
            if type == "response_item",
               let payload = record["payload"] as? [String: Any],
               let payloadType = payload["type"] as? String,
               (payloadType == "function_call" || payloadType == "custom_tool_call") {
                let args = argumentObject(from: payload)
                let path = (args["file_path"] as? String) ?? (args["path"] as? String) ?? ""
                if !path.isEmpty && !seenFiles.contains(path) && files.count < 5 {
                    seenFiles.insert(path)
                    files.append(path)
                }
            }
        }

        return ParsedTailData(
            exchangesNewestFirst: exchangesNewestFirst,
            messagesNewestFirst: messagesNewestFirst,
            files: files
        )
    }

    private static func extractLastUserPrompt(fromTailText text: String) -> String? {
        let lines = text.split(whereSeparator: \.isNewline).reversed()
        for line in lines {
            guard let record = jsonObject(from: String(line)) else { continue }
            guard let type = record["type"] as? String else { continue }

            if type == "user" {
                let message = record["message"] as? [String: Any] ?? [:]
                let content = extractUserOnlyText(from: message["content"])
                if let title = SessionTitleNormalizer.displayTitleCandidate(from: content) {
                    return title
                }
            }

            if type == "response_item",
               let payload = record["payload"] as? [String: Any],
               let payloadType = payload["type"] as? String, payloadType == "message",
               let role = payload["role"] as? String, role == "user" {
                let content = extractText(from: payload["content"])
                if let title = SessionTitleNormalizer.displayTitleCandidate(from: content) {
                    return title
                }
            }
        }

        return nil
    }

    private static func containsResolvedErrorContext(_ lowercasedText: String) -> Bool {
        let resolvedPhrases = [
            "i fixed the error",
            "fixed the error",
            "resolved the error",
            "error is fixed",
            "earlier error",
            "previous error",
            "after fixing",
            "all checks are green",
            "no longer failing",
            "now passes",
            "is now passing",
        ]
        return resolvedPhrases.contains(where: { lowercasedText.contains($0) })
    }

    private static func firstActiveAssistantErrorSignal(in lowercasedText: String) -> String? {
        let activeSignals = [
            "api error:",
            "error:",
            "fatal:",
            "exception:",
            "traceback",
            "failed to ",
            "build failed",
            "swift build failed",
            "test failed",
            "tests failed",
            "command failed",
            "command timed out",
            "request timed out",
        ]
        if let prefixMatch = activeSignals.first(where: { lowercasedText.hasPrefix($0) }) {
            return prefixMatch
        }

        if lowercasedText.contains("\"type\":\"invalid_request_error\"")
            || lowercasedText.contains("invalid_request_error")
        {
            return "invalid_request_error"
        }

        let sentenceBoundarySignals = activeSignals.map { " \($0)" } + activeSignals.map { ". \($0)" }
        for index in sentenceBoundarySignals.indices where lowercasedText.contains(sentenceBoundarySignals[index]) {
            return activeSignals[index % activeSignals.count]
        }
        return nil
    }

    private static func isFreshFailureAfterResolvedContext(_ lowercasedText: String, activeSignal: String) -> Bool {
        let alwaysActiveSignals: Set<String> = [
            "api error:",
            "fatal:",
            "exception:",
            "traceback",
            "command failed",
            "command timed out",
            "request timed out",
            "invalid_request_error",
        ]
        if alwaysActiveSignals.contains(activeSignal) {
            return true
        }

        let contextualFailureSignals: Set<String> = [
            "build failed",
            "swift build failed",
            "test failed",
            "tests failed",
            "failed to ",
        ]
        if contextualFailureSignals.contains(activeSignal) {
            let freshContextSignals = [
                ". \(activeSignal)",
                ", \(activeSignal)",
                " \(activeSignal) in ",
            ]
            if freshContextSignals.contains(where: { lowercasedText.contains($0) }) {
                return true
            }
        }

        let escalationSignals = [
            " again",
            " still ",
            " still.",
            " still,",
        ]
        return escalationSignals.contains(where: { lowercasedText.contains($0) })
    }
}
