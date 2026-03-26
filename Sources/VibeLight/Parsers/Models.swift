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

enum SessionTitleNormalizer {
    private static let xmlTagPattern = try? NSRegularExpression(pattern: "<[^>]+>")
    private static let structuredContextPrefixes = [
        "<environment_context",
        "<command-",
        "<system_instruction",
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
}
