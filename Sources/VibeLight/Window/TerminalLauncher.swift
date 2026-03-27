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
            try? process.run()
            process.waitUntilExit()
        }
    }

    static func buildScript(command: String, directory: String) -> String {
        let escapedDir = escapeForAppleScript(directory)
        let escapedCmd = escapeForAppleScript(command)

        return """
        tell application "Terminal"
            do script "cd \"\(escapedDir)\" && \(escapedCmd)"
            activate
        end tell
        """
    }

    private static func escapeForAppleScript(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
