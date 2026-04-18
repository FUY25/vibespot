import Carbon
import Foundation

enum SearchHistoryMode: String, Codable, Sendable {
    case liveOnly
    case liveAndHistory
}

enum AppTheme: String, Codable, Sendable {
    case system
    case light
    case dark
}

struct AppSettings: Codable, Equatable, Sendable {
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32
    var theme: AppTheme
    var historyMode: SearchHistoryMode
    var launchAtLogin: Bool
    var onboardingCompleted: Bool
    var sessionSourceConfiguration: SessionSourceConfiguration

    static let `default` = AppSettings(
        hotkeyKeyCode: UInt32(kVK_Space),
        hotkeyModifiers: UInt32(cmdKey | shiftKey),
        theme: .system,
        historyMode: .liveAndHistory,
        launchAtLogin: true,
        onboardingCompleted: false,
        sessionSourceConfiguration: .default
    )

    init(
        hotkeyKeyCode: UInt32,
        hotkeyModifiers: UInt32,
        theme: AppTheme,
        historyMode: SearchHistoryMode,
        launchAtLogin: Bool,
        onboardingCompleted: Bool,
        sessionSourceConfiguration: SessionSourceConfiguration = .default
    ) {
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.theme = theme
        self.historyMode = historyMode
        self.launchAtLogin = launchAtLogin
        self.onboardingCompleted = onboardingCompleted
        self.sessionSourceConfiguration = sessionSourceConfiguration
    }

    var hotkeyBinding: HotkeyBinding {
        HotkeyBinding(keyCode: hotkeyKeyCode, modifiers: hotkeyModifiers)
    }

    enum CodingKeys: String, CodingKey {
        case hotkeyKeyCode
        case hotkeyModifiers
        case theme
        case historyMode
        case launchAtLogin
        case onboardingCompleted
        case sessionSourceConfiguration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.hotkeyKeyCode = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode)
            ?? Self.default.hotkeyKeyCode
        self.hotkeyModifiers = try container.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers)
            ?? Self.default.hotkeyModifiers
        self.theme = try container.decodeIfPresent(AppTheme.self, forKey: .theme)
            ?? Self.default.theme
        self.historyMode = try container.decodeIfPresent(SearchHistoryMode.self, forKey: .historyMode)
            ?? Self.default.historyMode
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin)
            ?? Self.default.launchAtLogin
        self.onboardingCompleted = try container.decodeIfPresent(Bool.self, forKey: .onboardingCompleted)
            ?? Self.default.onboardingCompleted
        self.sessionSourceConfiguration = try container.decodeIfPresent(
            SessionSourceConfiguration.self,
            forKey: .sessionSourceConfiguration
        ) ?? Self.default.sessionSourceConfiguration
    }
}
