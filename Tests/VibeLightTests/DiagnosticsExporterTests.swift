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

    #expect(output.lastPathComponent.starts(with: "vibespot-diagnostics-"))
    #expect(FileManager.default.fileExists(atPath: manifestURL.path))
    #expect(FileManager.default.fileExists(atPath: settingsURL.path))
}

@Test
func diagnosticsExporterEmbedsTheCurrentSettings() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: nil)

    var settings = AppSettings.default
    settings.theme = .dark
    settings.historyMode = .liveOnly
    settings.launchAtLogin = false

    let exporter = DiagnosticsExporter()
    let output = try exporter.export(settings: settings, to: root)

    let manifestURL = output.appendingPathComponent("manifest.json")
    let data = try Data(contentsOf: manifestURL)
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let manifest = try decoder.decode(DiagnosticsExportManifest.self, from: data)

    #expect(manifest.settings == settings)
    #expect(manifest.applicationName == "VibeSpot")
}
