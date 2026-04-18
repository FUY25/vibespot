import Foundation
import Testing
@testable import Flare

@Suite("Session index workspace")
struct SessionIndexWorkspaceTests {
    @Test("uses separate active and staging database URLs per effective fingerprint")
    func usesSeparateActiveAndStagingDatabaseURLsPerEffectiveFingerprint() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "session-index-workspace-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let workspace = SessionIndexWorkspace(rootDirectoryURL: rootURL)

        let firstActiveURL = try workspace.activeDatabaseURL(for: "claude-a\u{0}codex-a")
        let firstStagingURL = try workspace.prepareStagingDatabaseURL(for: "claude-a\u{0}codex-a")
        let secondActiveURL = try workspace.activeDatabaseURL(for: "claude-b\u{0}codex-b")
        let secondStagingURL = try workspace.prepareStagingDatabaseURL(for: "claude-b\u{0}codex-b")

        #expect(firstActiveURL.lastPathComponent == "active.sqlite3")
        #expect(firstStagingURL.lastPathComponent == "staging.sqlite3")
        #expect(secondActiveURL.lastPathComponent == "active.sqlite3")
        #expect(secondStagingURL.lastPathComponent == "staging.sqlite3")

        #expect(firstActiveURL != firstStagingURL)
        #expect(secondActiveURL != secondStagingURL)
        #expect(firstActiveURL.deletingLastPathComponent() == firstStagingURL.deletingLastPathComponent())
        #expect(secondActiveURL.deletingLastPathComponent() == secondStagingURL.deletingLastPathComponent())
        #expect(firstActiveURL.deletingLastPathComponent() != secondActiveURL.deletingLastPathComponent())
        #expect(FileManager.default.fileExists(atPath: firstActiveURL.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: secondActiveURL.deletingLastPathComponent().path))
    }

    @Test("promotes the staged database into the active slot")
    func promotesTheStagedDatabaseIntoTheActiveSlot() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "session-index-workspace-promote-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let workspace = SessionIndexWorkspace(rootDirectoryURL: rootURL)
        let fingerprint = "claude-root\u{0}codex-root"
        let activeURL = try workspace.activeDatabaseURL(for: fingerprint)
        let stagingURL = try workspace.prepareStagingDatabaseURL(for: fingerprint)

        try Data("old-active".utf8).write(to: activeURL)
        try Data("new-staged".utf8).write(to: stagingURL)

        let promotedURL = try workspace.promoteStagingToActive(for: fingerprint)

        let activeContents = try String(decoding: Data(contentsOf: promotedURL), as: UTF8.self)
        #expect(promotedURL == activeURL)
        #expect(activeContents == "new-staged")
        #expect(!FileManager.default.fileExists(atPath: stagingURL.path))
    }

    @Test("legacy database migration moves sqlite sidecar artifacts together")
    func legacyDatabaseMigrationMovesSQLiteSidecarArtifactsTogether() throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "session-index-workspace-legacy-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let legacyDirectoryURL = rootURL.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectoryURL, withIntermediateDirectories: true)
        let legacyDatabaseURL = legacyDirectoryURL.appendingPathComponent("index.sqlite3", isDirectory: false)

        let legacyArtifacts: [(url: URL, contents: String)] = [
            (legacyDatabaseURL, "base"),
            (URL(fileURLWithPath: legacyDatabaseURL.path + "-wal"), "wal"),
            (URL(fileURLWithPath: legacyDatabaseURL.path + "-shm"), "shm"),
            (URL(fileURLWithPath: legacyDatabaseURL.path + "-journal"), "journal"),
        ]

        for artifact in legacyArtifacts {
            try Data(artifact.contents.utf8).write(to: artifact.url)
        }

        let workspace = SessionIndexWorkspace(
            rootDirectoryURL: rootURL.appendingPathComponent("workspaces", isDirectory: true),
            legacyDatabaseURL: legacyDatabaseURL
        )

        let activeURL = try workspace.activeDatabaseURL(for: "claude-root\u{0}codex-root")

        let migratedArtifacts: [(url: URL, contents: String)] = [
            (activeURL, "base"),
            (URL(fileURLWithPath: activeURL.path + "-wal"), "wal"),
            (URL(fileURLWithPath: activeURL.path + "-shm"), "shm"),
            (URL(fileURLWithPath: activeURL.path + "-journal"), "journal"),
        ]

        for artifact in migratedArtifacts {
            #expect(FileManager.default.fileExists(atPath: artifact.url.path))
            let contents = try String(decoding: Data(contentsOf: artifact.url), as: UTF8.self)
            #expect(contents == artifact.contents)
        }

        for artifact in legacyArtifacts {
            #expect(!FileManager.default.fileExists(atPath: artifact.url.path))
        }
    }
}
