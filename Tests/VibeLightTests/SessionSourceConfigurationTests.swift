import Foundation
import Testing
@testable import Flare

@Suite("Session source configuration")
struct SessionSourceConfigurationTests {
    @Test("effective fingerprint depends on effective roots only")
    func effectiveFingerprintDependsOnEffectiveRootsOnly() {
        let locator = SessionSourceLocator(homeDirectoryPath: "/Users/me")

        var automaticSettings = AppSettings.default
        automaticSettings.sessionSourceConfiguration = SessionSourceConfiguration(
            claude: ToolSessionSourceConfiguration(mode: .automatic, customRoot: ""),
            codex: ToolSessionSourceConfiguration(mode: .automatic, customRoot: "")
        )

        var customInvalidSettings = AppSettings.default
        customInvalidSettings.sessionSourceConfiguration = SessionSourceConfiguration(
            claude: ToolSessionSourceConfiguration(
                mode: .custom,
                customRoot: "/tmp/invalid-claude-\(UUID().uuidString)"
            ),
            codex: ToolSessionSourceConfiguration(
                mode: .custom,
                customRoot: "/tmp/invalid-codex-\(UUID().uuidString)"
            )
        )

        let automaticResolution = locator.resolve(for: automaticSettings)
        let customInvalidResolution = locator.resolve(for: customInvalidSettings)

        #expect(automaticResolution.effectiveFingerprint == customInvalidResolution.effectiveFingerprint)
    }

    @Test("reports unavailable when custom is invalid and auto is missing")
    func reportsUnavailableWhenCustomIsInvalidAndAutoIsMissing() {
        let missingHomeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-home-\(UUID().uuidString)", isDirectory: true)
            .path
        let locator = SessionSourceLocator(homeDirectoryPath: missingHomeDirectory)

        var settings = AppSettings.default
        settings.sessionSourceConfiguration = SessionSourceConfiguration(
            claude: ToolSessionSourceConfiguration(
                mode: .custom,
                customRoot: "/tmp/missing-claude-\(UUID().uuidString)"
            ),
            codex: ToolSessionSourceConfiguration(
                mode: .custom,
                customRoot: "/tmp/missing-codex-\(UUID().uuidString)"
            )
        )

        let resolution = locator.resolve(for: settings)

        #expect(resolution.claude.status == .unavailable)
        #expect(resolution.codex.status == .unavailable)
    }
}
