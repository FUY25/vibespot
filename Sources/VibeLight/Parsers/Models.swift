import Foundation

struct ParsedMessage: Sendable {
    let role: String
    let content: String
    let timestamp: Date
    let toolCalls: [String]
    let sessionId: String?
    let gitBranch: String?
    let cwd: String?
}

struct ParsedSessionMeta: Sendable {
    let sessionId: String
    let title: String
    let firstPrompt: String?
    let projectPath: String
    let gitBranch: String
    let startedAt: Date
    let isSidechain: Bool
}

struct ParsedHistoryEntry: Sendable {
    let sessionId: String
    let prompt: String
    let project: String
    let timestamp: Date
}

struct ParsedPidEntry: Sendable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Date
}

struct CodexSessionMeta: Sendable {
    let id: String
    let cwd: String?
    let cliVersion: String
    let source: String
    let isSubagent: Bool
}

enum ContextConfidence: String, Sendable {
    case high
    case medium
    case low
    case unknown
}

struct SessionContextTelemetry: Sendable {
    let effectiveModel: String?
    let contextWindowTokens: Int?
    let contextUsedEstimate: Int?
    let contextPercentEstimate: Int?
    let contextConfidence: ContextConfidence
    let contextSource: String?
    let lastContextSampleAt: Date?

    static let empty = SessionContextTelemetry(
        effectiveModel: nil,
        contextWindowTokens: nil,
        contextUsedEstimate: nil,
        contextPercentEstimate: nil,
        contextConfidence: .unknown,
        contextSource: nil,
        lastContextSampleAt: nil
    )
}

enum SessionTitleNormalizer {
    private static let xmlTagPattern = try? NSRegularExpression(pattern: "<[^>]+>")
    private static let structuredContextPrefixes = [
        "<environment_context",
        "<command-",
        "<system_instruction",
    ]
    private static let codexContextHeadings = [
        "context from my ide setup:",
    ]
    private static let codexRequestHeadings = [
        "my request for codex:",
        "my request for claude:",
        "my request:",
    ]
    private static let codexMetadataHeadings = [
        "active file:",
        "open tabs:",
        "open files:",
        "current selection:",
        "selected text:",
        "selection:",
        "workspace state:",
        "directory tree:",
        "project structure:",
        "file path:",
    ]
    private static let strongOutputPrefixes = [
        "zsh:",
        "bash:",
        "sh:",
        "fish:",
        "powershell:",
        "pwsh:",
        "cmd:",
    ]
    private static let outputPrefixes = strongOutputPrefixes + [
        "exit code:",
        "duration:",
        "output:",
        "stdout:",
        "stderr:",
        "traceback (most recent call last):",
        "stack trace:",
        "caused by:",
        "npm err!",
        "error:",
        "fatal:",
        "exception:",
        "(bash completed",
        "api error:",
        "task #",
        "set model to",
    ]

    static func titleCandidate(from rawContent: String) -> String? {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let lowercased = trimmed.lowercased()
        if structuredContextPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return nil
        }

        let stripped = strippingXMLTags(from: trimmed)
        let normalized = normalizeWhitespace(in: stripped)
        return normalized.isEmpty ? nil : normalized
    }

    static func firstMeaningfulUserTitle(in messages: [ParsedMessage]) -> String? {
        for message in messages where message.role == "user" {
            if let title = titleCandidate(from: message.content) {
                return title
            }
        }
        return nil
    }

    static func displayTitleCandidate(from rawContent: String) -> String? {
        guard let parserTitle = titleCandidate(from: rawContent) else {
            return nil
        }

        if let preferredDisplayTitle = preferredDisplayTitle(from: rawContent) {
            return preferredDisplayTitle
        }

        if isLikelyOutputOnly(rawContent) {
            return nil
        }

        return parserTitle
    }

    static func lastMeaningfulUserPrompt(in messages: [ParsedMessage]) -> String? {
        for message in messages.reversed() where message.role == "user" {
            if let title = displayTitleCandidate(from: message.content) {
                return title
            }
        }
        return nil
    }

    static func firstMeaningfulDisplayTitle(in messages: [ParsedMessage]) -> String? {
        for message in messages where message.role == "user" {
            if let title = displayTitleCandidate(from: message.content) {
                return title
            }
        }

        return firstMeaningfulUserTitle(in: messages)
    }

    static func strippingXMLTags(from value: String) -> String {
        guard let xmlTagPattern else {
            return value
        }

        let range = NSRange(value.startIndex..., in: value)
        let stripped = xmlTagPattern.stringByReplacingMatches(in: value, range: range, withTemplate: "")
        return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeWhitespace(in value: String) -> String {
        value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func preferredDisplayTitle(from rawContent: String) -> String? {
        let lines = rawContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        enum Section: Equatable {
            case neutral
            case context
            case metadata
            case request
        }

        var section: Section = .neutral
        var firstContextCandidate: String?

        for line in lines where !line.isEmpty {
            if let heading = normalizedMarkdownHeading(from: line) {
                let lowercasedHeading = heading.lowercased()

                if codexRequestHeadings.contains(where: { lowercasedHeading.hasPrefix($0) }) {
                    section = .request
                    continue
                }

                if codexContextHeadings.contains(where: { lowercasedHeading.hasPrefix($0) }) {
                    section = .context
                    continue
                }

                if section != .neutral, codexMetadataHeadings.contains(where: { lowercasedHeading.hasPrefix($0) }) {
                    section = .metadata
                    continue
                }

                if section == .request || section == .context {
                    section = .context
                }
                continue
            }

            switch section {
            case .request:
                if let candidate = titleCandidate(from: line) {
                    return candidate
                }
            case .context:
                if firstContextCandidate == nil, let candidate = titleCandidate(from: line) {
                    firstContextCandidate = candidate
                }
            case .neutral, .metadata:
                continue
            }
        }

        return firstContextCandidate
    }

    private static func normalizedMarkdownHeading(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("#") else {
            return nil
        }

        let heading = trimmed.drop(while: { $0 == "#" || $0 == " " || $0 == "\t" })
        guard !heading.isEmpty else {
            return nil
        }

        return String(heading).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isLikelyOutputOnly(_ rawContent: String) -> Bool {
        let lines = rawContent
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else {
            return false
        }

        if lines.count == 1 {
            return isLikelyOutputLine(lines[0])
        }

        if lines[0].lowercased() == "output:" {
            return true
        }

        return lines.allSatisfy(isLikelyOutputLine(_:))
    }

    private static func isLikelyOutputLine(_ line: String) -> Bool {
        let lowercasedLine = line.lowercased()

        if outputPrefixes.contains(where: { lowercasedLine.hasPrefix($0) }) {
            return true
        }

        if lowercasedLine.hasPrefix("at ") || lowercasedLine.hasPrefix("file \"") {
            return true
        }

        // Git commit output: "[branch-name hash] message" — hash is 7+ hex chars
        if lowercasedLine.hasPrefix("["),
           let closeBracket = lowercasedLine.firstIndex(of: "]") {
            let bracketContent = lowercasedLine[lowercasedLine.index(after: lowercasedLine.startIndex)..<closeBracket]
            let parts = bracketContent.split(separator: " ")
            if parts.count >= 2 {
                let lastPart = parts.last!
                let isHex = lastPart.count >= 7 && lastPart.allSatisfy({ $0.isHexDigit })
                if isHex { return true }
            }
        }

        if lowercasedLine.hasPrefix("#"), let firstCharacter = lowercasedLine.dropFirst().first, firstCharacter.wholeNumberValue != nil {
            return true
        }

        // Line-numbered output: "42→" (cat -n), "478:.foo" / "479- bar" (grep)
        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        if hasLeadingLineNumber(trimmedLine) {
            return true
        }

        return false
    }

    /// Detects line-numbered output patterns: digits followed by a delimiter (→, :, -).
    /// Requires 2+ digits to avoid false positives on natural language like "5-star" or "3: things".
    private static func hasLeadingLineNumber(_ line: String) -> Bool {
        let delimiters: [Character] = ["→", ":", "-"]
        for delimiter in delimiters {
            if let idx = line.firstIndex(of: delimiter) {
                let prefix = line[line.startIndex..<idx]
                if prefix.count >= 2 && prefix.allSatisfy(\.isWholeNumber) {
                    return true
                }
            }
        }
        return false
    }
}
