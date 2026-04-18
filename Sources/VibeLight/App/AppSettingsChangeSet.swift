import Foundation

struct AppSettingsChangeSet: Equatable, Sendable {
    let themeChanged: Bool
    let historyModeChanged: Bool
    let hotkeyChanged: Bool
    let sourceFingerprintChanged: Bool
    let launchAtLoginChanged: Bool

    init(
        oldSettings: AppSettings,
        newSettings: AppSettings,
        oldSessionSourceResolution: SessionSourceResolution,
        newSessionSourceResolution: SessionSourceResolution
    ) {
        self.themeChanged = oldSettings.theme != newSettings.theme
        self.historyModeChanged = oldSettings.historyMode != newSettings.historyMode
        self.hotkeyChanged = oldSettings.hotkeyBinding != newSettings.hotkeyBinding
        self.sourceFingerprintChanged = oldSessionSourceResolution.effectiveFingerprint
            != newSessionSourceResolution.effectiveFingerprint
        self.launchAtLoginChanged = oldSettings.launchAtLogin != newSettings.launchAtLogin
    }
}
