import Foundation
import Testing
@testable import Flare

@Suite("Source switch coordinator")
struct SourceSwitchCoordinatorTests {
    @MainActor
    @Test("keeps the current index active until the staged build succeeds")
    func keepsTheCurrentIndexActiveUntilTheStagedBuildSucceeds() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "source-switch-coordinator-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let workspace = SessionIndexWorkspace(rootDirectoryURL: rootURL)
        let currentResolution = makeResolution(
            claudeRootPath: "/tmp/current-claude",
            codexRootPath: "/tmp/current-codex"
        )
        let nextResolution = makeResolution(
            claudeRootPath: "/tmp/next-claude",
            codexRootPath: "/tmp/next-codex"
        )

        let currentIndex = try SessionIndex(dbPath: try workspace.activeDatabaseURL(for: currentResolution.effectiveFingerprint).path)
        try insertSession(id: "current-session", title: "Current session", into: currentIndex)

        let activationEvents = EventLog()
        var activatedIndex: SessionIndex?
        let coordinator = SourceSwitchCoordinator(workspace: workspace) { stagedIndex, _ in
            activationEvents.append("build-start")
            let currentSessionIDs = try currentIndex.search(query: "", includeHistory: true).map { $0.sessionId }
            #expect(currentSessionIDs == ["current-session"])

            try insertSession(id: "next-session", title: "Next session", into: stagedIndex)
            activationEvents.append("build-end")
        }

        try await coordinator.switchToSource(nextResolution) { readyIndex in
            activationEvents.append("activate")
            activatedIndex = readyIndex
        }

        let readyIndex = try #require(activatedIndex)
        let currentSessionIDs = try currentIndex.search(query: "", includeHistory: true).map { $0.sessionId }
        let nextSessionIDs = try readyIndex.search(query: "", includeHistory: true).map { $0.sessionId }

        #expect(activationEvents.values == ["build-start", "build-end", "activate"])
        #expect(currentSessionIDs == ["current-session"])
        #expect(nextSessionIDs == ["next-session"])
    }

    @MainActor
    @Test("failed staged build does not replace the active index")
    func failedStagedBuildDoesNotReplaceTheActiveIndex() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "source-switch-coordinator-failure-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let workspace = SessionIndexWorkspace(rootDirectoryURL: rootURL)
        let currentResolution = makeResolution(
            claudeRootPath: "/tmp/current-claude",
            codexRootPath: "/tmp/current-codex"
        )
        let nextResolution = makeResolution(
            claudeRootPath: "/tmp/next-claude",
            codexRootPath: "/tmp/next-codex"
        )

        let currentIndex = try SessionIndex(dbPath: try workspace.activeDatabaseURL(for: currentResolution.effectiveFingerprint).path)
        try insertSession(id: "current-session", title: "Current session", into: currentIndex)

        var activationCount = 0
        let coordinator = SourceSwitchCoordinator(workspace: workspace) { stagedIndex, _ in
            try insertSession(id: "partial-session", title: "Partial session", into: stagedIndex)
            struct BuildFailure: Error {}
            throw BuildFailure()
        }

        do {
            try await coordinator.switchToSource(nextResolution) { _ in
                activationCount += 1
            }
            Issue.record("Expected staged build failure")
        } catch {}

        let currentSessionIDs = try currentIndex.search(query: "", includeHistory: true).map { $0.sessionId }
        let nextActiveURL = try workspace.activeDatabaseURL(for: nextResolution.effectiveFingerprint)

        #expect(activationCount == 0)
        #expect(currentSessionIDs == ["current-session"])
        #expect(!FileManager.default.fileExists(atPath: nextActiveURL.path))
    }

    private func makeResolution(
        claudeRootPath: String,
        codexRootPath: String
    ) -> SessionSourceResolution {
        SessionSourceResolution(
            claudeRootPath: claudeRootPath,
            codexRootPath: codexRootPath,
            claudeProjectsPath: claudeRootPath + "/projects",
            claudeSessionsPath: claudeRootPath + "/sessions",
            codexSessionsPath: codexRootPath + "/sessions",
            codexStatePath: codexRootPath + "/state_5.sqlite",
            autoClaudeAvailable: true,
            autoCodexAvailable: true,
            usingCustomClaude: true,
            usingCustomCodex: true,
            customRequestedButUnavailable: false,
            autoFallbackForClaude: false,
            autoFallbackForCodex: false,
            requestedMode: .custom
        )
    }

    private func insertSession(id: String, title: String, into index: SessionIndex) throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try index.upsertSession(
            id: id,
            tool: "claude",
            title: title,
            project: "/tmp/project",
            projectName: "project",
            gitBranch: "main",
            status: "closed",
            startedAt: now,
            pid: nil,
            lastActivityAt: now
        )
    }
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [String] {
        lock.lock()
        let snapshot = storage
        lock.unlock()
        return snapshot
    }
}
