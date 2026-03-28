import Foundation

struct LiveSession {
    let pid: Int
    let sessionId: String
    let cwd: String
    let tool: String
    let isAlive: Bool
}

enum LiveSessionRegistry {
    private static let sessionsPath: String = {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/sessions"
    }()
    private static let commandTimeout: DispatchTimeInterval = .seconds(2)

    private struct CodexProcessFileInfo {
        let cwd: String
        let rolloutPath: String
    }

    /// Cache: PID → Codex file identity. A running process keeps the same cwd and
    /// rollout file, so once both are discovered we can reuse them for its lifetime.
    nonisolated(unsafe) private static var codexProcessFileInfoCache: [Int: CodexProcessFileInfo] = [:]

    static func scan() -> [LiveSession] {
        scanClaudeSessions() + scanCodexSessions()
    }

    private static func scanClaudeSessions() -> [LiveSession] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsPath) else { return [] }

        return files.compactMap { filename -> LiveSession? in
            guard filename.hasSuffix(".json") else { return nil }
            let path = (sessionsPath as NSString).appendingPathComponent(filename)
            let url = URL(fileURLWithPath: path)
            guard let entry = try? ClaudeParser.parsePidFile(url: url) else { return nil }

            let alive = isProcessAlive(pid: entry.pid)
            guard !isGhosttySession(pid: entry.pid) else { return nil }
            return LiveSession(pid: entry.pid, sessionId: entry.sessionId, cwd: entry.cwd, tool: "claude", isAlive: alive)
        }
    }

    /// Returns true if any ancestor process of `pid` is the Ghostty terminal.
    static func isGhosttySession(pid: Int) -> Bool {
        var current = pid
        // Walk at most 16 levels up to avoid infinite loops
        for _ in 0..<16 {
            guard current > 1 else { return false }
            guard let ppid = parentPID(of: current) else { return false }
            guard ppid > 1 else { return false }
            if let comm = processComm(of: ppid), comm.lowercased().contains("ghostty") {
                return true
            }
            current = ppid
        }
        return false
    }

    private static func parentPID(of pid: Int) -> Int? {
        guard let output = runCommand(
            executablePath: "/bin/ps",
            arguments: ["-p", String(pid), "-o", "ppid="]
        ) else { return nil }
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func processComm(of pid: Int) -> String? {
        guard let output = runCommand(
            executablePath: "/bin/ps",
            arguments: ["-p", String(pid), "-o", "comm="]
        ) else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func scanCodexSessions() -> [LiveSession] {
        guard let psOutput = runCommand(
            executablePath: "/bin/ps",
            arguments: ["-axo", "uid,pid,comm"]
        ) else {
            return []
        }

        let alivePids = parseCodexPIDs(from: psOutput)
            .filter { isProcessAlive(pid: $0) }
            .filter { !isGhosttySession(pid: $0) }

        // Evict dead PIDs from cache
        let aliveSet = Set(alivePids)
        codexProcessFileInfoCache = codexProcessFileInfoCache.filter { aliveSet.contains($0.key) }

        // Find PIDs that need lsof (not yet resolved to a unique rollout path).
        let uncachedPids = alivePids.filter { codexProcessFileInfoCache[$0] == nil }

        // Single batched lsof call for all uncached PIDs
        if !uncachedPids.isEmpty {
            let pidArgs = uncachedPids.map(String.init).joined(separator: ",")
            if let lsofOutput = runCommand(
                executablePath: "/usr/sbin/lsof",
                arguments: ["-a", "-Fn", "-p", pidArgs]
            ) {
                for pid in uncachedPids {
                    if let processFileInfo = parseCodexProcessFileInfo(from: lsofOutput, pid: pid),
                       let rolloutPath = processFileInfo.rolloutPath
                    {
                        codexProcessFileInfoCache[pid] = CodexProcessFileInfo(
                            cwd: processFileInfo.cwd ?? "",
                            rolloutPath: rolloutPath
                        )
                    }
                }
            }
        }

        let stateDB = CodexStateDB()

        return alivePids.compactMap { pid in
            guard let processFileInfo = codexProcessFileInfoCache[pid] else { return nil }
            guard let sessionId = stateDB.sessionIdByRolloutPath(processFileInfo.rolloutPath) else { return nil }
            return LiveSession(
                pid: pid,
                sessionId: sessionId,
                cwd: processFileInfo.cwd,
                tool: "codex",
                isAlive: true
            )
        }
    }

    static func parseCodexPIDs(from output: String) -> [Int] {
        output
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { return nil }

                let fields = line.split(maxSplits: 2, whereSeparator: \.isWhitespace)
                guard fields.count >= 3 else { return nil }
                guard let pid = Int(fields[1]) else { return nil }

                let command = String(fields[2]).lowercased()
                guard command == "codex" || command.hasSuffix("/codex") else { return nil }
                return pid
            }
    }

    static func parseCwd(from output: String, pid: Int) -> String? {
        parseCodexProcessFileInfo(from: output, pid: pid)?.cwd
    }

    static func parseRolloutPath(from output: String, pid: Int) -> String? {
        parseCodexProcessFileInfo(from: output, pid: pid)?.rolloutPath
    }

    private static func isProcessAlive(pid: Int) -> Bool {
        guard pid > 0 else { return false }
        if kill(Int32(pid), 0) == 0 {
            return true
        }
        return errno == EPERM
    }

    private static func runCommand(executablePath: String, arguments: [String]) -> String? {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let terminationSignal = DispatchSemaphore(value: 0)

        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { _ in
            terminationSignal.signal()
        }

        do {
            try process.run()
        } catch {
            return nil
        }

        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading

        var stdoutData = Data()
        var stderrData = Data()
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stdoutData = stdoutHandle.readDataToEndOfFile()
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrData = stderrHandle.readDataToEndOfFile()
            readGroup.leave()
        }

        if readGroup.wait(timeout: .now() + commandTimeout) == .timedOut {
            process.terminate()
            _ = terminationSignal.wait(timeout: .now() + .milliseconds(200))
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
                _ = terminationSignal.wait(timeout: .now() + .milliseconds(200))
            }
            return nil
        }

        _ = terminationSignal.wait(timeout: .now() + .milliseconds(200))
        if process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = terminationSignal.wait(timeout: .now() + .milliseconds(200))
            return nil
        }

        guard process.terminationStatus == 0 else {
            _ = stderrData
            return nil
        }

        _ = stderrData
        return String(data: stdoutData, encoding: .utf8)
    }

    private static func parseCodexProcessFileInfo(from output: String, pid: Int) -> (cwd: String?, rolloutPath: String?)? {
        var foundTargetProcess = false
        var currentField: String?
        var cwd: String?
        var rolloutCandidates = Set<String>()

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("p"), let linePid = Int(line.dropFirst()) {
                foundTargetProcess = linePid == pid
                currentField = nil
                continue
            }

            guard foundTargetProcess else { continue }

            if line.hasPrefix("f") {
                currentField = String(line.dropFirst())
                continue
            }

            guard line.hasPrefix("n") else { continue }
            let path = String(line.dropFirst())
            guard !path.isEmpty else { continue }

            if currentField == "cwd" {
                cwd = path
            }

            if isCodexRolloutPath(path) {
                rolloutCandidates.insert(path)
            }
        }

        guard cwd != nil || !rolloutCandidates.isEmpty else {
            return nil
        }

        let rolloutPath = rolloutCandidates.count == 1 ? rolloutCandidates.first : nil
        return (cwd, rolloutPath)
    }

    private static func isCodexRolloutPath(_ path: String) -> Bool {
        guard path.contains("/.codex/sessions/"), path.hasSuffix(".jsonl") else {
            return false
        }
        return (path as NSString).lastPathComponent.hasPrefix("rollout-")
    }
}
