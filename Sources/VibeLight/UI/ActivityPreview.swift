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
        // Tool activity (including edit/write calls) remains working unless
        // we have an explicit assistant prompt captured separately.
        if lastJSONLEntryType == "user"
            || lastJSONLEntryType == "tool_result" {
            return .working
        }

        // Defensive fallback: if upstream normalization regresses and a prompt-bearing
        // assistant turn arrives tagged as tool_use, prefer waiting over a false working state.
        if lastJSONLEntryType == "tool_use",
           activityPreview?.kind == .assistant {
            return .waiting
        }

        if lastJSONLEntryType == "tool_use" {
            return .working
        }

        // "assistant" or anything else with no recent file activity = waiting for user
        return .waiting
    }
}
