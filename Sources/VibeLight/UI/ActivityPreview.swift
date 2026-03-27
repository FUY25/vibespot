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
        if secondsSinceModification < 5 {
            return .working
        }

        if lastJSONLEntryType == "tool_use" || lastJSONLEntryType == "user" {
            return .working
        }

        return .waiting
    }
}
