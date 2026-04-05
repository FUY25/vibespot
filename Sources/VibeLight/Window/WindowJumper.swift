import AppKit
import Foundation

enum WindowJumper {
    enum ProcessExecutionError: Error, Equatable {
        case timedOut
    }

    private static let jumpQueue = DispatchQueue(label: "Flare.WindowJumper", qos: .userInitiated)

    private static func log(_ message: String) {
        print("[WindowJumper] \(message)")
    }

    @MainActor
    static func jumpToSession(_ result: SearchResult) {
        guard result.status == "live", let pid = result.pid else {
            log("jumpToSession: skipped — status=\(result.status), pid=\(result.pid ?? -1)")
            return
        }

        log("jumpToSession: session=\(result.sessionId.prefix(8))… tool=\(result.tool) pid=\(pid)")
        jumpQueue.async {
            performJump(for: pid)
        }
    }

    static func parentPID(for pid: Int) -> Int? {
        switch parentPIDLookup(for: pid) {
        case .success(let parentPID):
            return parentPID
        case .processFailure, .launchFailure, .invalidOutput:
            return nil
        }
    }

    private static func performJump(for pid: Int) {
        log("performJump: starting for pid=\(pid)")

        // Yield Flare's activation before attempting the jump so the target
        // terminal can reliably grab focus regardless of macOS window ordering.
        yieldToTerminalProcess(pid: pid)

        if jumpViaTerminal(pid: pid) {
            log("performJump: jumpViaTerminal succeeded")
            return
        }
        log("performJump: jumpViaTerminal failed, trying activateTerminalApplication")

        if activateTerminalApplication() {
            log("performJump: activateTerminalApplication succeeded")
            return
        }
        log("performJump: activateTerminalApplication failed, trying parent chain")

        let result = activateFirstAvailableApplication(startingAt: pid)
        log("performJump: activateFirstAvailableApplication result=\(result)")
    }

    /// Yield activation to the running app that owns this PID (or its parent chain).
    private static func yieldToTerminalProcess(pid: Int) {
        var currentPID: Int? = pid
        var visited = Set<Int>()

        while let p = currentPID, visited.insert(p).inserted {
            if let app = NSRunningApplication(processIdentifier: pid_t(p)),
               app.activationPolicy != .prohibited {
                let name = app.localizedName ?? "unknown"
                log("yieldToTerminalProcess: yielding to \(name) (pid=\(p), bundle=\(app.bundleIdentifier ?? "nil"))")
                DispatchQueue.main.async {
                    NSApp.yieldActivation(to: app)
                }
                return
            }
            switch parentPIDLookup(for: p) {
            case .success(let parent) where parent != p:
                currentPID = parent
            default:
                log("yieldToTerminalProcess: no activatable app found in parent chain from pid=\(pid)")
                currentPID = nil
            }
        }
    }

    private static func jumpViaTerminal(pid: Int) -> Bool {
        let ttyResult = ttyLookup(for: pid)
        switch ttyResult {
        case .success(let tty):
            let targetTTY = tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
            log("jumpViaTerminal: pid=\(pid) → tty=\(targetTTY)")

            let terminalResult = runAppleScript(buildTerminalAppScript(targetTTY: targetTTY))
            log("jumpViaTerminal: Terminal.app script returned \(terminalResult ?? "nil")")
            if terminalResult == "ok" {
                openBundleOnMainThread("com.apple.Terminal")
                return true
            }

            let itermResult = runAppleScript(buildITermScript(targetTTY: targetTTY))
            log("jumpViaTerminal: iTerm script returned \(itermResult ?? "nil")")
            if itermResult == "ok" {
                openBundleOnMainThread("com.googlecode.iterm2")
                return true
            }

            return false
        case .processFailure(let output):
            log("jumpViaTerminal: tty lookup process failed for pid=\(pid), status=\(output.terminationStatus), stderr=\(output.stderr)")
            return false
        case .launchFailure(let error):
            log("jumpViaTerminal: tty lookup launch failed for pid=\(pid): \(error)")
            return false
        case .invalidOutput(let output):
            log("jumpViaTerminal: tty lookup invalid output for pid=\(pid): stdout='\(output.trimmedStdout)'")
            return false
        }
    }

    private static func openBundleOnMainThread(_ bundleIdentifier: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first,
              let bundleURL = app.bundleURL else { return }
        if Thread.isMainThread {
            NSWorkspace.shared.open(bundleURL)
        } else {
            DispatchQueue.main.async {
                NSWorkspace.shared.open(bundleURL)
            }
        }
    }

    private static func buildTerminalAppScript(targetTTY: String) -> String {
        """
        set targetTTY to \(appleScriptStringLiteral(targetTTY))

        try
            path to application id "com.apple.Terminal"
        on error
            return "missing"
        end try

        if application "Terminal" is not running then
            return "not-running"
        end if

        tell application "Terminal"
            repeat with terminalWindow in windows
                repeat with terminalTab in tabs of terminalWindow
                    if tty of terminalTab is targetTTY then
                        set selected of terminalTab to true
                        set index of terminalWindow to 1
                        activate
                        return "ok"
                    end if
                end repeat
            end repeat
        end tell

        return "not-found"
        """
    }

    private static func buildITermScript(targetTTY: String) -> String {
        """
        set targetTTY to \(appleScriptStringLiteral(targetTTY))

        try
            path to application id "com.googlecode.iterm2"
        on error
            return "missing"
        end try

        if application "iTerm" is not running then
            return "not-running"
        end if

        tell application "iTerm"
            repeat with aWindow in windows
                repeat with aTab in tabs of aWindow
                    repeat with aSession in sessions of aTab
                        if tty of aSession is targetTTY then
                            select aSession
                            select aTab
                            select aWindow
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
            end repeat
        end tell

        return "not-found"
        """
    }

    private static func runAppleScript(_ script: String) -> String? {
        do {
            let result = try runProcess(
                executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                arguments: ["-e", script]
            )
            guard result.terminationStatus == 0 else {
                log("runAppleScript: exit=\(result.terminationStatus), stderr=\(result.stderr.prefix(200))")
                return nil
            }
            return result.trimmedStdout
        } catch {
            log("runAppleScript: launch error: \(error)")
            return nil
        }
    }

    private static func ttyLookup(for pid: Int) -> ProcessLookup<String> {
        do {
            let result = try runProcess(
                executableURL: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-p", String(pid), "-o", "tty="]
            )

            guard result.terminationStatus == 0 else {
                return .processFailure(result)
            }

            let tty = result.trimmedStdout
            guard !tty.isEmpty, tty != "?" else {
                return .invalidOutput(result)
            }

            return .success(tty)
        } catch {
            return .launchFailure(error.localizedDescription)
        }
    }

    private static func parentPIDLookup(for pid: Int) -> ProcessLookup<Int> {
        do {
            let result = try runProcess(
                executableURL: URL(fileURLWithPath: "/bin/ps"),
                arguments: ["-p", String(pid), "-o", "ppid="]
            )

            guard result.terminationStatus == 0 else {
                return .processFailure(result)
            }

            let output = result.trimmedStdout
            guard let parentPID = Int(output), parentPID > 0 else {
                return .invalidOutput(result)
            }

            return .success(parentPID)
        } catch {
            return .launchFailure(error.localizedDescription)
        }
    }

    private static func activateFirstAvailableApplication(startingAt pid: Int) -> Bool {
        var currentPID: Int? = pid
        var visited = Set<Int>()

        while let candidatePID = currentPID, visited.insert(candidatePID).inserted {
            if activateApplication(for: candidatePID) {
                return true
            }

            switch parentPIDLookup(for: candidatePID) {
            case .success(let parentPID) where parentPID != candidatePID:
                currentPID = parentPID
            case .success, .processFailure, .launchFailure, .invalidOutput:
                currentPID = nil
            }
        }

        return false
    }

    private static func activateApplication(for pid: Int) -> Bool {
        if Thread.isMainThread {
            return activate(NSRunningApplication(processIdentifier: pid_t(pid)))
        }

        return DispatchQueue.main.sync {
            activate(NSRunningApplication(processIdentifier: pid_t(pid)))
        }
    }

    private static let terminalBundleIDs = [
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "net.kovidgoyal.kitty",
    ]

    private static func activateTerminalApplication() -> Bool {
        for bundleID in terminalBundleIDs {
            let apps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if let app = apps.first {
                if Thread.isMainThread {
                    if activate(app) { return true }
                } else {
                    let activated = DispatchQueue.main.sync { activate(app) }
                    if activated { return true }
                }
            }
        }
        return false
    }

    private static func activate(_ application: NSRunningApplication?) -> Bool {
        guard let application else {
            log("activate: nil application")
            return false
        }

        let name = application.localizedName ?? "unknown"
        let bundle = application.bundleIdentifier ?? "nil"

        guard application.activationPolicy != .prohibited else {
            log("activate: \(name) (\(bundle)) has prohibited activation policy")
            return false
        }

        if let bundleURL = application.bundleURL {
            NSWorkspace.shared.open(bundleURL)
        }

        let result = application.activate(options: [])
        log("activate: \(name) (\(bundle)) → \(result ? "success" : "failed")")
        return result
    }

    static func runProcess(
        executableURL: URL,
        arguments: [String],
        timeout: TimeInterval = 1.5
    ) throws -> ProcessOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let finished = DispatchSemaphore(value: 0)

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { _ in
            finished.signal()
        }

        try process.run()

        if finished.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning {
                process.terminate()
                _ = finished.wait(timeout: .now() + 0.2)
            }
            throw ProcessExecutionError.timedOut
        }

        let stdout = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ProcessOutput(
            terminationStatus: process.terminationStatus,
            stdout: String(data: stdout, encoding: .utf8) ?? "",
            stderr: String(data: stderr, encoding: .utf8) ?? ""
        )
    }

    private static func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}

struct ProcessOutput {
    let terminationStatus: Int32
    let stdout: String
    let stderr: String

    var trimmedStdout: String {
        stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private enum ProcessLookup<Value> {
    case success(Value)
    case processFailure(ProcessOutput)
    case launchFailure(String)
    case invalidOutput(ProcessOutput)
}
