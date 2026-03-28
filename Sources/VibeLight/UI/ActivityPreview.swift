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

    static func determine(
        sessionStatus: String,
        lastFileModification: Date,
        lastJSONLEntryType: String?,
        now: Date = Date()
    ) -> SessionActivityStatus {
        guard sessionStatus == "live" else {
            return .closed
        }

        let secondsSinceModification = now.timeIntervalSince(lastFileModification)

        // File modified very recently — model is actively writing
        if secondsSinceModification < 5 {
            return .working
        }

        // File not modified recently — check what the last entry was
        // "user" → model is thinking (hasn't responded yet)
        // "tool_use" → tool is executing
        // "tool_result" → model is processing tool output
        // All three mean the model's turn isn't done yet.
        if lastJSONLEntryType == "user"
            || lastJSONLEntryType == "tool_use"
            || lastJSONLEntryType == "tool_result" {
            return .working
        }

        // "assistant" or anything else with no recent file activity = waiting for user
        return .waiting
    }
}
