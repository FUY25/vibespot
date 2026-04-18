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
