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
        // tool_use means the model is mid-execution (waiting for tool result)
        if lastJSONLEntryType == "tool_use" {
            return .working
        }

        // "user" or "assistant" or anything else with no recent file activity = waiting
        return .waiting
    }
}
