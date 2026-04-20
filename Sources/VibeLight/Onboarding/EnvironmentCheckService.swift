import Foundation

struct EnvironmentCheckResult: Sendable, Equatable {
    enum FirstSuccessState: String, Sendable, Equatable {
        case readyToSearch
        case canCreateFirstSession
        case blocked
    }

    struct ToolState: Sendable, Equatable {
        let isAvailable: Bool
        let resolvedPath: String?
    }

    struct SessionDataState: Sendable, Equatable {
        let rootPath: String
        let exists: Bool
        let isReadable: Bool
        let hasSessionData: Bool

        var statusLabel: String {
            if hasSessionData {
                return "Ready"
            }
            if exists == false {
                return "Missing"
            }
            if isReadable == false {
                return "Unreadable"
            }
            return "Empty"
        }
    }

    let codex: ToolState
    let claude: ToolState
    let codexData: SessionDataState
    let claudeData: SessionDataState
    let checkedPaths: [String]
    let missingAccessiblePaths: [String]

    var canSearchLocalSessions: Bool {
        codexData.hasSessionData || claudeData.hasSessionData
    }

    var canCreateFirstSession: Bool {
        codex.isAvailable || claude.isAvailable
    }

    var firstSuccessState: FirstSuccessState {
        if canSearchLocalSessions {
            return .readyToSearch
        }
        if canCreateFirstSession {
            return .canCreateFirstSession
        }
        return .blocked
    }

    var canFinishOnboarding: Bool {
        firstSuccessState != .blocked
    }

    var readinessHeadline: String {
        switch firstSuccessState {
        case .readyToSearch:
            return "You're ready to search"
        case .canCreateFirstSession:
            return "You're almost ready"
        case .blocked:
            return "One more step before VibeSpot is useful"
        }
    }

    var readinessDetail: String {
        switch firstSuccessState {
        case .readyToSearch:
            return "VibeSpot found readable local session history on this Mac. Finish setup and open search."
        case .canCreateFirstSession:
            return "A supported CLI is installed, but there is no local session history yet. Finish setup, then start your first Codex or Claude session to seed search."
        case .blocked:
            return "Install Codex or Claude, or restore readable ~/.codex or ~/.claude data, then run checks again."
        }
    }
}

protocol ProcessRunning: Sendable {
    func which(_ command: String) async -> String?
}

struct SystemProcessRunner: ProcessRunning {
    func which(_ command: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
            process.arguments = [command]
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
                return
            }

            process.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let path = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: path?.isEmpty == false ? path : nil)
            }
        }
    }
}

struct EnvironmentCheckService: @unchecked Sendable {
    let fileManager: FileManager
    let processRunner: any ProcessRunning
    let homeDirectoryPath: String

    init(
        fileManager: FileManager = .default,
        processRunner: any ProcessRunning = SystemProcessRunner(),
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.fileManager = fileManager
        self.processRunner = processRunner
        self.homeDirectoryPath = homeDirectoryPath
    }

    func runChecks() async -> EnvironmentCheckResult {
        let codexPath = await processRunner.which("codex")
        let claudePath = await processRunner.which("claude")

        let codexRoot = homeDirectoryPath + "/.codex"
        let claudeRoot = homeDirectoryPath + "/.claude"
        let checkedPaths = [codexRoot, claudeRoot]
        let codexData = makeCodexDataState(rootPath: codexRoot)
        let claudeData = makeClaudeDataState(rootPath: claudeRoot)

        let missingAccessiblePaths = checkedPaths.filter { path in
            !fileManager.fileExists(atPath: path) || !fileManager.isReadableFile(atPath: path)
        }

        return EnvironmentCheckResult(
            codex: EnvironmentCheckResult.ToolState(
                isAvailable: codexPath != nil,
                resolvedPath: codexPath
            ),
            claude: EnvironmentCheckResult.ToolState(
                isAvailable: claudePath != nil,
                resolvedPath: claudePath
            ),
            codexData: codexData,
            claudeData: claudeData,
            checkedPaths: checkedPaths,
            missingAccessiblePaths: missingAccessiblePaths
        )
    }

    private func makeCodexDataState(rootPath: String) -> EnvironmentCheckResult.SessionDataState {
        let exists = fileManager.fileExists(atPath: rootPath)
        let isReadable = exists && fileManager.isReadableFile(atPath: rootPath)
        let hasSessionData = isReadable && (
            fileManager.fileExists(atPath: rootPath + "/session_index.jsonl")
                || directoryContainsMatch(
                    at: rootPath + "/sessions",
                    predicate: { $0.hasSuffix(".jsonl") }
                )
        )

        return EnvironmentCheckResult.SessionDataState(
            rootPath: rootPath,
            exists: exists,
            isReadable: isReadable,
            hasSessionData: hasSessionData
        )
    }

    private func makeClaudeDataState(rootPath: String) -> EnvironmentCheckResult.SessionDataState {
        let exists = fileManager.fileExists(atPath: rootPath)
        let isReadable = exists && fileManager.isReadableFile(atPath: rootPath)
        let hasSessionData = isReadable && directoryContainsMatch(
            at: rootPath + "/projects",
            predicate: { $0.hasSuffix(".jsonl") || $0.hasSuffix("/sessions-index.json") }
        )

        return EnvironmentCheckResult.SessionDataState(
            rootPath: rootPath,
            exists: exists,
            isReadable: isReadable,
            hasSessionData: hasSessionData
        )
    }

    private func directoryContainsMatch(at path: String, predicate: (String) -> Bool) -> Bool {
        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return false
        }

        for case let item as String in enumerator {
            if predicate(item) {
                return true
            }
        }
        return false
    }
}
