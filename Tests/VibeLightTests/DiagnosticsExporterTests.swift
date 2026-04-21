import Foundation
import Testing
@testable import Flare

@Test
func diagnosticsExporterCreatesSnapshotFiles() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)

    let exporter = DiagnosticsExporter()
    let output = try exporter.export(settings: .default, to: root)

    let manifestURL = output.appendingPathComponent("manifest.json")
    let settingsURL = output.appendingPathComponent("settings.json")
    let sourceResolutionURL = output.appendingPathComponent("source-resolution.json")
    let environmentURL = output.appendingPathComponent("environment-check.json")
    let workspaceURL = output.appendingPathComponent("index-workspace.json")
    let issuesURL = output.appendingPathComponent("runtime-issues.json")
    let readmeURL = output.appendingPathComponent("README.txt")

    #expect(output.lastPathComponent.starts(with: "vibespot-diagnostics-"))
    #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    #expect(FileManager.default.fileExists(atPath: settingsURL.path))
    #expect(FileManager.default.fileExists(atPath: sourceResolutionURL.path))
    #expect(FileManager.default.fileExists(atPath: environmentURL.path))
    #expect(FileManager.default.fileExists(atPath: workspaceURL.path))
    #expect(FileManager.default.fileExists(atPath: issuesURL.path))
    #expect(FileManager.default.fileExists(atPath: readmeURL.path))
}

@Test
func diagnosticsExporterEmbedsTheCurrentSettings() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)

    var settings = AppSettings.default
    settings.theme = .dark
    settings.historyMode = .liveOnly
    settings.launchAtLogin = false

    let exporter = DiagnosticsExporter(issueSnapshotProvider: {
        [RuntimeIssue(recordedAt: Date(timeIntervalSince1970: 0), component: "SearchPanel", message: "Sample issue")]
    })
    let output = try exporter.export(settings: settings, to: root)

    let manifestURL = output.appendingPathComponent("manifest.json")
    let workspaceURL = output.appendingPathComponent("index-workspace.json")
    let data = try Data(contentsOf: manifestURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(DiagnosticsExportManifest.self, from: data)

    #expect(manifest.settings == settings)
    #expect(manifest.applicationName == "VibeSpot")
    #expect(manifest.recentIssueCount == 1)
    #expect(manifest.supportURL.contains("github.com/FUY25/vibespot/issues"))

    let workspaceData = try Data(contentsOf: workspaceURL)
    let workspace = try decoder.decode(DiagnosticsIndexWorkspaceSnapshot.self, from: workspaceData)
    #expect(workspace.activeDatabasePath.contains("active.sqlite3"))
}
