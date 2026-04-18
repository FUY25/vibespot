import Foundation
import Testing
@testable import Flare

private struct MockProcessRunner: ProcessRunning {
    let paths: [String: String]

    func which(_ command: String) async -> String? {
        paths[command]
    }
}

@Suite("Environment check service")
struct EnvironmentCheckServiceTests {
    @Test("reports codex and claude binary presence")
    func reportsCodexAndClaudeBinaryPresence() async {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-check-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        try? FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent(".codex", isDirectory: true),
            withIntermediateDirectories: true
        )
        try? FileManager.default.createDirectory(
            at: tempRoot.appendingPathComponent(".claude", isDirectory: true),
            withIntermediateDirectories: true
        )

        let service = EnvironmentCheckService(
            fileManager: .default,
            processRunner: MockProcessRunner(paths: [
                "codex": "/usr/local/bin/codex",
                "claude": "/usr/local/bin/claude",
            ]),
            homeDirectoryPath: tempRoot.path
        )

        let result = await service.runChecks()
        #expect(result.codex.isAvailable)
        #expect(result.codex.resolvedPath == "/usr/local/bin/codex")
        #expect(result.claude.isAvailable)
        #expect(result.claude.resolvedPath == "/usr/local/bin/claude")
        #expect(result.missingAccessiblePaths.isEmpty)
        #expect(result.checkedPaths.contains(tempRoot.path + "/.codex"))
        #expect(result.checkedPaths.contains(tempRoot.path + "/.claude"))
    }

    @Test("reports missing accessible paths without hardcoded project directories")
    func reportsMissingAccessiblePathsWithoutHardcodedProjectDirectories() async {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("env-check-missing-\(UUID().uuidString)", isDirectory: true)
        let service = EnvironmentCheckService(
            fileManager: .default,
            processRunner: MockProcessRunner(paths: [:]),
            homeDirectoryPath: tempRoot.path
        )

        let result = await service.runChecks()
        #expect(result.codex.isAvailable == false)
        #expect(result.claude.isAvailable == false)
        #expect(result.checkedPaths == [tempRoot.path + "/.codex", tempRoot.path + "/.claude"])
        #expect(result.missingAccessiblePaths == result.checkedPaths)
    }
}
