import Foundation

struct EnvironmentCheckResult: Sendable, Equatable {
    struct ToolState: Sendable, Equatable {
        let isAvailable: Bool
        let resolvedPath: String?
    }

    let codex: ToolState
    let claude: ToolState
    let checkedPaths: [String]
    let missingAccessiblePaths: [String]
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

        let checkedPaths = [
            homeDirectoryPath + "/.codex",
            homeDirectoryPath + "/.claude",
        ]

        let missingAccessiblePaths = checkedPaths.filter { path in
            !fileManager.fileExists(atPath: path)
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
            checkedPaths: checkedPaths,
            missingAccessiblePaths: missingAccessiblePaths
        )
    }
}
