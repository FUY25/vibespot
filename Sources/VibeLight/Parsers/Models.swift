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
