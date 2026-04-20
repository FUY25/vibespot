import Foundation

enum TerminalLauncher {
    static func launch(command: String, directory: String) {
        let script = buildScript(command: command, directory: directory)

        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", script]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus != 0 {
                    RuntimeIssueStore.shared.record(
                        component: "TerminalLauncher",
                        message: "osascript exited with status \(process.terminationStatus)"
                    )
                    print("TerminalLauncher: osascript exited with status \(process.terminationStatus)")
                }
            } catch {
                RuntimeIssueStore.shared.record(component: "TerminalLauncher", error: error)
                print("TerminalLauncher: failed to launch osascript (\(error))")
            }
        }
    }

    static func buildScript(command: String, directory: String) -> String {
        let expandedDirectory = (directory as NSString).expandingTildeInPath
        let escapedDir = escapeForAppleScriptStringLiteral(expandedDirectory)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        let commandFragment: String
        if trimmedCommand.isEmpty {
            commandFragment = ""
        } else {
            let escapedCmd = escapeForAppleScriptStringLiteral(trimmedCommand)
            commandFragment = " & \" && \(escapedCmd)\""
        }

        return """
        tell application "Terminal"
            do script "cd " & quoted form of "\(escapedDir)"\(commandFragment)
            activate
        end tell
        """
    }

    // Escapes content for safe inclusion inside an AppleScript string literal.
    private static func escapeForAppleScriptStringLiteral(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
    }
}
