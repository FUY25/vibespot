import Foundation
import Testing
@testable import Flare

@Suite("Settings store")
struct SettingsStoreTests {
    @Test("uses expected defaults")
    func usesExpectedDefaults() {
        let suite = UserDefaults(suiteName: "SettingsStoreTests.defaults.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)

        #expect(store.load() == .default)
    }

    @Test("persists and reloads")
    func persistsAndReloads() {
        let suite = UserDefaults(suiteName: "SettingsStoreTests.persist.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)

        var settings = store.load()
        settings.hotkeyKeyCode = 40
        settings.hotkeyModifiers = 128
        settings.theme = .dark
        settings.historyMode = .liveOnly
        settings.launchAtLogin = false
        settings.onboardingCompleted = true
        store.save(settings)

        let reloaded = store.load()
        #expect(reloaded == settings)
    }

    @Test("persists independent Claude and Codex source settings")
    func persistsIndependentClaudeAndCodexSourceSettings() {
        let suite = UserDefaults(suiteName: "SettingsStoreTests.sources.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)

        let customClaudeRoot = "/tmp/claude-custom-\(UUID().uuidString)"
        var settings = AppSettings.default
        settings.sessionSourceConfiguration = SessionSourceConfiguration(
            claude: ToolSessionSourceConfiguration(mode: .custom, customRoot: customClaudeRoot),
            codex: ToolSessionSourceConfiguration(mode: .automatic, customRoot: "")
        )

        store.save(settings)

        let reloaded = store.load()
        #expect(reloaded.sessionSourceConfiguration.claude.mode == .custom)
        #expect(reloaded.sessionSourceConfiguration.claude.customRoot == customClaudeRoot)
        #expect(reloaded.sessionSourceConfiguration.codex.mode == .automatic)
        #expect(reloaded.sessionSourceConfiguration.codex.customRoot.isEmpty)
        #expect(reloaded.sessionSourceConfiguration == settings.sessionSourceConfiguration)
    }

    @Test("migrates legacy flat session source payload")
    func migratesLegacyFlatSessionSourcePayload() {
        let suite = UserDefaults(suiteName: "SettingsStoreTests.legacySource.\(UUID().uuidString)")!
        let legacyPayload = """
        {
          "hotkeyKeyCode": 49,
          "hotkeyModifiers": 1048576,
          "theme": "system",
          "historyMode": "liveAndHistory",
          "launchAtLogin": true,
          "onboardingCompleted": false,
          "sessionSourceConfiguration": {
            "mode": "custom",
            "customClaudeRoot": "/Users/me/.claude-workspace",
            "customCodexRoot": "/Users/me/.codex-workspace"
          }
        }
        """
        suite.set(Data(legacyPayload.utf8), forKey: "flare.settings.v1")

        let loaded = SettingsStore(defaults: suite).load()

        #expect(loaded.sessionSourceConfiguration.claude.mode == .custom)
        #expect(loaded.sessionSourceConfiguration.claude.customRoot == "/Users/me/.claude-workspace")
        #expect(loaded.sessionSourceConfiguration.codex.mode == .custom)
        #expect(loaded.sessionSourceConfiguration.codex.customRoot == "/Users/me/.codex-workspace")
    }

    @Test("migrates legacy keys")
    func migratesLegacyKeys() {
        let suite = UserDefaults(suiteName: "SettingsStoreTests.legacy.\(UUID().uuidString)")!
        suite.set(42, forKey: "flare.hotkeyKeyCode")
        suite.set(256, forKey: "flare.hotkeyModifiers")
        suite.set("dark", forKey: "flare.theme")
        suite.set("liveOnly", forKey: "flare.historyMode")
        suite.set(false, forKey: "flare.launchAtLogin")
        suite.set(true, forKey: "flare.onboardingCompleted")

        let store = SettingsStore(defaults: suite)
        let loaded = store.load()

        #expect(loaded.hotkeyKeyCode == 42)
        #expect(loaded.hotkeyModifiers == 256)
        #expect(loaded.theme == .dark)
        #expect(loaded.historyMode == .liveOnly)
        #expect(loaded.launchAtLogin == false)
        #expect(loaded.onboardingCompleted == true)
        #expect(suite.data(forKey: "flare.settings.v1") != nil)
        #expect(suite.object(forKey: "flare.hotkeyKeyCode") == nil)
    }
}
