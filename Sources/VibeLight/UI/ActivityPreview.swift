import Foundation

struct ActivityPreview: Sendable, Equatable {
    enum Kind: String, Sendable {
        case tool
        case fileEdit
        case assistant
    }

    let text: String
    let kind: Kind
}

enum SessionActivityStatus: String, Sendable {
    case working
    case waiting
    case closed

    private static let activeWriteWindow: TimeInterval = 5
    private static let toolActivityGraceWindow: TimeInterval = 10

    static func determine(
        sessionStatus: String,
        lastFileModification: Date,
        lastActivityAt: Date,
        lastJSONLEntryType: String?,
        activityPreview: ActivityPreview? = nil,
        now: Date = Date()
    ) -> SessionActivityStatus {
        guard sessionStatus == "live" else {
            return .closed
        }

        let secondsSinceModification = now.timeIntervalSince(lastFileModification)
        let secondsSinceActivity = now.timeIntervalSince(lastActivityAt)

        // File modified very recently — model is actively writing
        if secondsSinceModification < activeWriteWindow {
            return .working
        }

        // A fresh user turn means the agent has likely just started responding.
        if lastJSONLEntryType == "user" {
            return .working
        }

        // Defensive fallback: if upstream normalization regresses and a prompt-bearing
        // assistant turn arrives tagged as tool_use, prefer waiting over a false working state.
        if lastJSONLEntryType == "tool_use",
           activityPreview?.kind == .assistant {
            return .waiting
        }

        // Tool-use and tool-result entries are ambiguous. Keep them working briefly
        // after activity lands, then downgrade once the session has gone quiet.
        if lastJSONLEntryType == "tool_result" {
            return secondsSinceActivity < toolActivityGraceWindow ? .working : .waiting
        }

        if lastJSONLEntryType == "tool_use" {
            return secondsSinceActivity < toolActivityGraceWindow ? .working : .waiting
        }

        // "assistant" or anything else with no recent file activity = waiting for user
        return .waiting
    }
}
