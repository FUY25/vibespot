import Foundation

struct SessionIndexWorkspace {
    private let rootDirectoryURL: URL
    private let legacyDatabaseURL: URL?
    private let fileManager: FileManager

    init(
        rootDirectoryURL: URL,
        legacyDatabaseURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.rootDirectoryURL = rootDirectoryURL
        self.legacyDatabaseURL = legacyDatabaseURL
        self.fileManager = fileManager
    }

    func activeDatabaseURL(for effectiveFingerprint: String) throws -> URL {
        let workspaceDirectoryURL = try ensureWorkspaceDirectory(for: effectiveFingerprint)
        let activeURL = workspaceDirectoryURL.appendingPathComponent("active.sqlite3", isDirectory: false)
        try migrateLegacyDatabaseIfNeeded(to: activeURL)
        return activeURL
    }

    func prepareStagingDatabaseURL(for effectiveFingerprint: String) throws -> URL {
        let workspaceDirectoryURL = try ensureWorkspaceDirectory(for: effectiveFingerprint)
        let stagingURL = workspaceDirectoryURL.appendingPathComponent("staging.sqlite3", isDirectory: false)
        try removeDatabaseArtifacts(at: stagingURL)
        return stagingURL
    }

    @discardableResult
    func promoteStagingToActive(for effectiveFingerprint: String) throws -> URL {
        let activeURL = try activeDatabaseURL(for: effectiveFingerprint)
        let stagingURL = workspaceDirectoryURL(for: effectiveFingerprint)
            .appendingPathComponent("staging.sqlite3", isDirectory: false)

        guard fileManager.fileExists(atPath: stagingURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }

        let backupURL = workspaceDirectoryURL(for: effectiveFingerprint)
            .appendingPathComponent("active-backup-\(UUID().uuidString).sqlite3", isDirectory: false)

        try removeDatabaseArtifacts(at: backupURL)
        if fileManager.fileExists(atPath: activeURL.path) {
            _ = try fileManager.replaceItemAt(activeURL, withItemAt: stagingURL, backupItemName: backupURL.lastPathComponent)
            try removeDatabaseArtifacts(at: backupURL)
            return activeURL
        }

        try fileManager.moveItem(at: stagingURL, to: activeURL)
        return activeURL
    }

    private func ensureWorkspaceDirectory(for effectiveFingerprint: String) throws -> URL {
        let workspaceDirectoryURL = workspaceDirectoryURL(for: effectiveFingerprint)
        try fileManager.createDirectory(at: workspaceDirectoryURL, withIntermediateDirectories: true)
        return workspaceDirectoryURL
    }

    private func workspaceDirectoryURL(for effectiveFingerprint: String) -> URL {
        rootDirectoryURL.appendingPathComponent(encodedFingerprint(effectiveFingerprint), isDirectory: true)
    }

    private func migrateLegacyDatabaseIfNeeded(to activeURL: URL) throws {
        guard let legacyDatabaseURL else {
            return
        }
        guard !fileManager.fileExists(atPath: activeURL.path) else {
            return
        }
        let legacyArtifacts = databaseArtifactURLs(for: legacyDatabaseURL)
        guard legacyArtifacts.contains(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return
        }
        let activeArtifacts = databaseArtifactURLs(for: activeURL)
        for (legacyArtifactURL, activeArtifactURL) in zip(legacyArtifacts, activeArtifacts) {
            guard fileManager.fileExists(atPath: legacyArtifactURL.path) else {
                continue
            }
            try fileManager.moveItem(at: legacyArtifactURL, to: activeArtifactURL)
        }
    }

    private func removeDatabaseArtifacts(at databaseURL: URL) throws {
        for artifactURL in databaseArtifactURLs(for: databaseURL) where fileManager.fileExists(atPath: artifactURL.path) {
            try fileManager.removeItem(at: artifactURL)
        }
    }

    private func databaseArtifactURLs(for databaseURL: URL) -> [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-shm"),
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-journal"),
        ]
    }

    private func encodedFingerprint(_ effectiveFingerprint: String) -> String {
        effectiveFingerprint.utf8.map { String(format: "%02x", $0) }.joined()
    }
}
