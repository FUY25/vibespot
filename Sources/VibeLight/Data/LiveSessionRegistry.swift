import Foundation

struct LiveSession {
    let pid: Int
    let sessionId: String
    let cwd: String
    let isAlive: Bool
}

enum LiveSessionRegistry {
    private static let sessionsPath: String = {
        FileManager.default.homeDirectoryForCurrentUser.path + "/.claude/sessions"
    }()

    static func scan() -> [LiveSession] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: sessionsPath) else { return [] }

        return files.compactMap { filename -> LiveSession? in
            guard filename.hasSuffix(".json") else { return nil }
            let path = (sessionsPath as NSString).appendingPathComponent(filename)
            let url = URL(fileURLWithPath: path)
            guard let entry = try? ClaudeParser.parsePidFile(url: url) else { return nil }

            let alive = isProcessAlive(pid: entry.pid)
            return LiveSession(pid: entry.pid, sessionId: entry.sessionId, cwd: entry.cwd, isAlive: alive)
        }
    }

    private static func isProcessAlive(pid: Int) -> Bool {
        // kill(pid, 0) returns 0 if process exists
        kill(Int32(pid), 0) == 0
    }
}
