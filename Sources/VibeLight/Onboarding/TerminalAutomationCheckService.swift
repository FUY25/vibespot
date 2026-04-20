import Foundation

struct TerminalAutomationCheckResult: Sendable, Equatable {
    enum Status: String, Sendable, Equatable {
        case unknown
        case ready
        case needsAccess
        case unavailable
    }

    let status: Status
    let detail: String?

    init(status: Status, detail: String? = nil) {
        self.status = status
        self.detail = detail
    }
}

protocol TerminalAutomationChecking: Sendable {
    func runCheck() async -> TerminalAutomationCheckResult
}

struct TerminalAutomationCheckService: TerminalAutomationChecking {
    func runCheck() async -> TerminalAutomationCheckResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = [
                "-e",
                #"tell application "Terminal" to count windows"#
            ]
            process.standardOutput = stdout
            process.standardError = stderr

            do {
                try process.run()
            } catch {
                continuation.resume(returning: TerminalAutomationCheckResult(status: .unavailable, detail: error.localizedDescription))
                return
            }

            process.terminationHandler = { process in
                let errorText = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: TerminalAutomationCheckResult(status: .ready))
                    return
                }

                let lowered = errorText.lowercased()
                if lowered.contains("-1743")
                    || lowered.contains("not authorized")
                    || lowered.contains("not permitted")
                    || lowered.contains("permission") {
                    continuation.resume(returning: TerminalAutomationCheckResult(status: .needsAccess, detail: errorText.isEmpty ? nil : errorText))
                    return
                }

                continuation.resume(returning: TerminalAutomationCheckResult(
                    status: .unavailable,
                    detail: errorText.isEmpty ? nil : errorText
                ))
            }
        }
    }
}
