import Foundation

struct SourceSwitchCoordinator {
    typealias IndexBuilder = @Sendable (SessionIndex, SessionSourceResolution) throws -> Void

    private let workspace: SessionIndexWorkspace
    private let indexBuilder: IndexBuilder

    init(
        workspace: SessionIndexWorkspace,
        indexBuilder: @escaping IndexBuilder = IndexScanner.buildFullScan
    ) {
        self.workspace = workspace
        self.indexBuilder = indexBuilder
    }

    func switchToSource(
        _ sourceResolution: SessionSourceResolution,
        onReady: @escaping @MainActor (SessionIndex) -> Void
    ) async throws {
        let stagingURL = try workspace.prepareStagingDatabaseURL(for: sourceResolution.effectiveFingerprint)

        do {
            let stagedIndex = try SessionIndex(dbPath: stagingURL.path)
            try indexBuilder(stagedIndex, sourceResolution)
        }

        guard !Task.isCancelled else {
            return
        }

        let activeURL = try workspace.promoteStagingToActive(for: sourceResolution.effectiveFingerprint)
        let readyIndex = try SessionIndex(dbPath: activeURL.path)
        await onReady(readyIndex)
    }
}
