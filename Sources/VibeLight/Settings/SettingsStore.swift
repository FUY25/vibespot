import Foundation

final class SettingsStore {
    private static let settingsKey = "flare.settings.v1"
    private static let legacyHotkeyKeyCodeKey = "flare.hotkeyKeyCode"
    private static let legacyHotkeyModifiersKey = "flare.hotkeyModifiers"
    private static let legacyThemeKey = "flare.theme"
    private static let legacyHistoryModeKey = "flare.historyMode"
    private static let legacyLaunchAtLoginKey = "flare.launchAtLogin"
    private static let legacyOnboardingCompletedKey = "flare.onboardingCompleted"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        if let settings = loadPersistedSettings() {
            return settings
        }

        if let legacySettings = loadLegacySettings() {
            save(legacySettings)
            return legacySettings
        }

        return .default
    }

    func save(_ settings: AppSettings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        defaults.set(data, forKey: Self.settingsKey)
        removeLegacyKeys()
    }

    private func loadPersistedSettings() -> AppSettings? {
        guard let data = defaults.data(forKey: Self.settingsKey) else {
            return nil
        }

        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }

    private func loadLegacySettings() -> AppSettings? {
        guard defaults.object(forKey: Self.legacyHotkeyKeyCodeKey) != nil
            || defaults.object(forKey: Self.legacyHotkeyModifiersKey) != nil
            || defaults.object(forKey: Self.legacyThemeKey) != nil
            || defaults.object(forKey: Self.legacyHistoryModeKey) != nil
            || defaults.object(forKey: Self.legacyLaunchAtLoginKey) != nil
            || defaults.object(forKey: Self.legacyOnboardingCompletedKey) != nil
        else {
            return nil
        }

        var settings = AppSettings.default

        if let hotkeyKeyCode = defaults.object(forKey: Self.legacyHotkeyKeyCodeKey) as? Int {
            settings.hotkeyKeyCode = UInt32(hotkeyKeyCode)
        }

        if let hotkeyModifiers = defaults.object(forKey: Self.legacyHotkeyModifiersKey) as? Int {
            settings.hotkeyModifiers = UInt32(hotkeyModifiers)
        }

        if let themeRaw = defaults.string(forKey: Self.legacyThemeKey),
           let theme = AppTheme(rawValue: themeRaw) {
            settings.theme = theme
        }

        if let historyRaw = defaults.string(forKey: Self.legacyHistoryModeKey),
           let historyMode = SearchHistoryMode(rawValue: historyRaw) {
            settings.historyMode = historyMode
        }

        if defaults.object(forKey: Self.legacyLaunchAtLoginKey) != nil {
            settings.launchAtLogin = defaults.bool(forKey: Self.legacyLaunchAtLoginKey)
        }

        if defaults.object(forKey: Self.legacyOnboardingCompletedKey) != nil {
            settings.onboardingCompleted = defaults.bool(forKey: Self.legacyOnboardingCompletedKey)
        }

        return settings
    }

    private func removeLegacyKeys() {
        defaults.removeObject(forKey: Self.legacyHotkeyKeyCodeKey)
        defaults.removeObject(forKey: Self.legacyHotkeyModifiersKey)
        defaults.removeObject(forKey: Self.legacyThemeKey)
        defaults.removeObject(forKey: Self.legacyHistoryModeKey)
        defaults.removeObject(forKey: Self.legacyLaunchAtLoginKey)
        defaults.removeObject(forKey: Self.legacyOnboardingCompletedKey)
    }
}
