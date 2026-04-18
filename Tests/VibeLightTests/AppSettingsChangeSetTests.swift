import Carbon
import Foundation
import Testing
@testable import Flare

@MainActor
struct AppSettingsChangeSetTests {
    @Test
    func historyModeChangeDoesNotRequestHotkeyOrSourceWork() {
        let oldSettings = AppSettings.default
        var newSettings = oldSettings
        newSettings.historyMode = .liveOnly

        let resolution = makeResolution(
            claudeRootPath: "/Users/test/.claude",
            codexRootPath: "/Users/test/.codex"
        )
        let changeSet = AppSettingsChangeSet(
            oldSettings: oldSettings,
            newSettings: newSettings,
            oldSessionSourceResolution: resolution,
            newSessionSourceResolution: resolution
        )

        #expect(!changeSet.themeChanged)
        #expect(changeSet.historyModeChanged)
        #expect(!changeSet.hotkeyChanged)
        #expect(!changeSet.sourceFingerprintChanged)
    }

    @Test
    func detectsThemeHotkeyAndSourceChangesIndependently() {
        let oldSettings = AppSettings.default
        var newSettings = oldSettings
        newSettings.theme = .dark
        newSettings.hotkeyKeyCode = UInt32(kVK_ANSI_K)
        newSettings.hotkeyModifiers = UInt32(cmdKey | optionKey)

        let oldResolution = makeResolution(
            claudeRootPath: "/Users/test/.claude",
            codexRootPath: "/Users/test/.codex"
        )
        let newResolution = makeResolution(
            claudeRootPath: "/tmp/custom-claude",
            codexRootPath: "/tmp/custom-codex"
        )

        let changeSet = AppSettingsChangeSet(
            oldSettings: oldSettings,
            newSettings: newSettings,
            oldSessionSourceResolution: oldResolution,
            newSessionSourceResolution: newResolution
        )

        #expect(changeSet.themeChanged)
        #expect(!changeSet.historyModeChanged)
        #expect(changeSet.hotkeyChanged)
        #expect(changeSet.sourceFingerprintChanged)
    }

    @Test
    func appDelegateHistoryModeSetterPersistsWithoutChangingSourceFingerprint() {
        let suite = UserDefaults(suiteName: "AppSettingsChangeSetTests.history.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        var initialSettings = store.load()
        initialSettings.onboardingCompleted = true
        initialSettings.historyMode = .liveAndHistory
        store.save(initialSettings)

        let delegate = AppDelegate(startsRuntimeServices: false, settingsStore: store)
        let originalFingerprint = delegate.currentSessionSourceFingerprintForTesting

        delegate.applyHistoryModeForTesting(.liveOnly)

        #expect(store.load().historyMode == .liveOnly)
        #expect(delegate.currentSessionSourceFingerprintForTesting == originalFingerprint)
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
            usingCustomClaude: false,
            usingCustomCodex: false,
            customRequestedButUnavailable: false,
            autoFallbackForClaude: false,
            autoFallbackForCodex: false,
            requestedMode: .automatic
        )
    }
}
