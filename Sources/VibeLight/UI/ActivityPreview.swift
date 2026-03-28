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
        activityPreview: ActivityPreview? = nil,
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

        // File not modified recently — check what the last entry was.
        // Most tool activity still means work is in flight, but stale file-edit
        // permission prompts are waiting on user input rather than active work.
        if lastJSONLEntryType == "user"
            || lastJSONLEntryType == "tool_result" {
            return .working
        }

        if lastJSONLEntryType == "tool_use" {
            if activityPreview?.kind == .fileEdit {
                return .waiting
            }
            return .working
        }

        // "assistant" or anything else with no recent file activity = waiting for user
        return .waiting
    }
}
