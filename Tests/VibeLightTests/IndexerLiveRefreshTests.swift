import Foundation
import Dispatch
import Testing
@testable import Flare

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private func makeCustomResolution() -> SessionSourceResolution {
    SessionSourceResolution(
        claudeRootPath: "/tmp/custom/.claude",
        codexRootPath: "/tmp/custom/.codex",
        claudeProjectsPath: "/tmp/custom/.claude/projects",
        claudeSessionsPath: "/tmp/custom/.claude/sessions",
        codexSessionsPath: "/tmp/custom/.codex/sessions",
        codexStatePath: "/tmp/custom/.codex/state_5.sqlite",
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

private func makeResolution(root: URL) -> SessionSourceResolution {
    SessionSourceResolution(
        claudeRootPath: root.appendingPathComponent(".claude", isDirectory: true).path,
        codexRootPath: root.appendingPathComponent(".codex", isDirectory: true).path,
        claudeProjectsPath: root.appendingPathComponent(".claude/projects", isDirectory: true).path,
        claudeSessionsPath: root.appendingPathComponent(".claude/sessions", isDirectory: true).path,
        codexSessionsPath: root.appendingPathComponent(".codex/sessions", isDirectory: true).path,
        codexStatePath: root.appendingPathComponent(".codex/state_5.sqlite").path,
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

@Test
func codexAndClaudeTranscriptChangesTriggerImmediateLiveRefresh() {
    let changedPaths = [
        "/Users/me/.claude/projects/project-a/session-1.jsonl",
        "/Users/me/.codex/sessions/2026/03/29/rollout-abc.jsonl",
    ]

    #expect(Indexer.shouldRefreshLiveSessions(forChangedPaths: changedPaths))
}

@Test
func shouldRefreshLiveSessionsUsesResolvedSourcePaths() {
    let customResolution = makeCustomResolution()

    let changedPaths = [
        "/tmp/custom/.claude/projects/project-a/session-1.jsonl",
        "/tmp/custom/.codex/sessions/2026/03/29/rollout-abc.jsonl",
    ]

    #expect(Indexer.shouldRefreshLiveSessions(forChangedPaths: changedPaths, sourceResolution: customResolution))
}

@Test
func unrelatedChangesDoNotForceImmediateLiveRefresh() {
    let changedPaths = [
        "/Users/me/.claude/projects/project-a/sessions-index.json",
        "/Users/me/.codex/session_index.jsonl",
        "/Users/me/project/README.md",
    ]

    #expect(Indexer.shouldRefreshLiveSessions(forChangedPaths: changedPaths) == false)
}

@Test
func codexMetadataChangesUseTargetedRefreshInsteadOfFullReindex() {
    let refreshPlan = Indexer.codexMetadataRefreshPlan(
        forChangedPaths: [
            "/tmp/custom/.codex/session_index.jsonl",
            "/tmp/custom/.codex/state_5.sqlite",
        ],
        sourceResolution: makeCustomResolution()
    )

    #expect(refreshPlan.forceFullTranscriptReindex == false)
    #expect(refreshPlan.refreshTitles)
    #expect(refreshPlan.refreshGitBranches)
}

@Test
func codexMetadataChangesTreatWALAndSHMAsGitBranchRefreshTriggers() {
    let refreshPlan = Indexer.codexMetadataRefreshPlan(
        forChangedPaths: [
            "/tmp/custom/.codex/state_5.sqlite-wal",
            "/tmp/custom/.codex/state_5.sqlite-shm",
        ],
        sourceResolution: makeCustomResolution()
    )

    #expect(refreshPlan.forceFullTranscriptReindex == false)
    #expect(refreshPlan.refreshTitles == false)
    #expect(refreshPlan.refreshGitBranches)
}

@MainActor
@Test
func performFullScanRunsOnChangeHandlingQueue() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("indexer-fullscan-queue-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    try fileManager.createDirectory(
        at: tempRoot.appendingPathComponent(".claude/projects", isDirectory: true),
        withIntermediateDirectories: true,
        attributes: nil
    )
    try fileManager.createDirectory(
        at: tempRoot.appendingPathComponent(".claude/sessions", isDirectory: true),
        withIntermediateDirectories: true,
        attributes: nil
    )
    try fileManager.createDirectory(
        at: tempRoot.appendingPathComponent(".codex/sessions", isDirectory: true),
        withIntermediateDirectories: true,
        attributes: nil
    )

    let queueSpecificKey = DispatchSpecificKey<Void>()
    let queue = DispatchQueue(label: "IndexerLiveRefreshTests.performFullScan", qos: .utility)
    queue.setSpecific(key: queueSpecificKey, value: ())

    let index = try SessionIndex(dbPath: tempRoot.appendingPathComponent("index.sqlite3").path)
    let indexer = Indexer(
        sessionIndex: index,
        sourceResolution: makeResolution(root: tempRoot),
        changeHandlingQueue: queue
    )

    let ranOnChangeHandlingQueue = LockedFlag()
    indexer.onPerformFullScanForTesting = {
        ranOnChangeHandlingQueue.set(DispatchQueue.getSpecific(key: queueSpecificKey) != nil)
    }

    indexer.performFullScan()

    #expect(ranOnChangeHandlingQueue.get())
}

@MainActor
@Test
func stopQuiescesPreviouslyQueuedChangeHandlingWork() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory
        .appendingPathComponent("indexer-stop-queue-\(UUID().uuidString)", isDirectory: true)
    defer { try? fileManager.removeItem(at: tempRoot) }

    let resolution = makeResolution(root: tempRoot)
    try fileManager.createDirectory(atPath: resolution.claudeRootPath, withIntermediateDirectories: true, attributes: nil)
    try fileManager.createDirectory(atPath: resolution.codexRootPath, withIntermediateDirectories: true, attributes: nil)

    let queue = DispatchQueue(label: "IndexerLiveRefreshTests.stop", qos: .utility)
    let index = try SessionIndex(dbPath: tempRoot.appendingPathComponent("index.sqlite3").path)
    let indexer = Indexer(sessionIndex: index, sourceResolution: resolution, changeHandlingQueue: queue)

    indexer.start()

    let blocker = DispatchSemaphore(value: 0)
    queue.async {
        blocker.wait()
    }

    let didRun = LockedFlag()
    indexer.enqueueChangeHandlingForTesting { _ in
        didRun.set(true)
    }

    Task.detached {
        try? await Task.sleep(nanoseconds: 50_000_000)
        blocker.signal()
    }

    indexer.stop()
    indexer.waitForChangeHandlingQueueForTesting()

    #expect(didRun.get() == false)
}

@Test
func fileWatcherDefaultsToBackgroundQueue() {
    #expect(FileWatcher.defaultCallbackQueueLabel != DispatchQueue.main.label)
}

@Test
func indexerHeavyChangeHandlingUsesBackgroundQueue() {
    #expect(Indexer.changeHandlingQueueLabel != DispatchQueue.main.label)
}

@Test
func promptDerivedTitlesStayWeakForFastLiveRefresh() {
    #expect(
        IndexingHelpers.hasWeakLiveTitle(
            currentTitle: "old prompt",
            projectName: "vibelight",
            storedLastUserPrompt: "old prompt"
        )
    )
}

@Test
func smartTitlesDoNotStayWeakForFastLiveRefresh() {
    #expect(
        IndexingHelpers.hasWeakLiveTitle(
            currentTitle: "Ship telemetry in the panel",
            projectName: "vibelight",
            storedLastUserPrompt: "old prompt"
        ) == false
    )
}
