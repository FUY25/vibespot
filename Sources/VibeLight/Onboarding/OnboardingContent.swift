import Foundation

enum OnboardingLanguage: String, Sendable, Equatable {
    case english
    case chinese

    init(preferredLanguageCode: String?) {
        if preferredLanguageCode?.lowercased().hasPrefix("zh") == true {
            self = .chinese
        } else {
            self = .english
        }
    }

    var code: String {
        switch self {
        case .english:
            return "en"
        case .chinese:
            return "zh-Hans"
        }
    }

    var windowTitle: String {
        switch self {
        case .english:
            return "Welcome to VibeSpot"
        case .chinese:
            return "欢迎使用 VibeSpot"
        }
    }

    var backLabel: String {
        switch self {
        case .english:
            return "Back"
        case .chinese:
            return "上一步"
        }
    }

    var nextLabel: String {
        switch self {
        case .english:
            return "Next"
        case .chinese:
            return "下一步"
        }
    }

    var finishLabel: String {
        switch self {
        case .english:
            return "Start Using VibeSpot"
        case .chinese:
            return "开始使用 VibeSpot"
        }
    }

    var changeShortcutLabel: String {
        switch self {
        case .english:
            return "Change shortcut"
        case .chinese:
            return "修改快捷键"
        }
    }

    var resetShortcutLabel: String {
        switch self {
        case .english:
            return "Reset"
        case .chinese:
            return "恢复默认"
        }
    }

    var runChecksLabel: String {
        switch self {
        case .english:
            return "Run check again"
        case .chinese:
            return "重新检查"
        }
    }

    var checkingLabel: String {
        switch self {
        case .english:
            return "Checking…"
        case .chinese:
            return "检查中…"
        }
    }

    var allowTerminalLabel: String {
        switch self {
        case .english:
            return "Allow access"
        case .chinese:
            return "允许访问"
        }
    }

    var checkAgainLabel: String {
        switch self {
        case .english:
            return "Check again"
        case .chinese:
            return "再次检查"
        }
    }

    var openAtLoginLabel: String {
        switch self {
        case .english:
            return "Open VibeSpot at login"
        case .chinese:
            return "登录后自动打开 VibeSpot"
        }
    }

    var unsupportedLaunchAtLoginLabel: String {
        switch self {
        case .english:
            return "Available in packaged app builds only"
        case .chinese:
            return "仅打包后的应用支持"
        }
    }

    var gifPlaceholderLabel: String {
        switch self {
        case .english:
            return "Demo"
        case .chinese:
            return "演示"
        }
    }

    var demoPlaceholderPrompt: String {
        switch self {
        case .english:
            return "Drop the recorded demo here later."
        case .chinese:
            return "之后把录好的演示放在这里。"
        }
    }

    func sentence(for card: OnboardingCard, defaultHotkey: String) -> String {
        switch (self, card) {
        case (.english, .quickActivation):
            return "Anytime, anywhere. Press your shortcut to see live sessions and recent messages."
        case (.english, .shortcutSetup):
            return "Default: \(defaultHotkey). Change it if you want."
        case (.english, .fastSwitch):
            return "Pick a session. Press Enter to jump back in."
        case (.english, .searchSessions):
            return "Fuzzy-search by keyword to find the right window or reopen an old session fast."
        case (.english, .checkAccess):
            return "Let VibeSpot read your local history so search works."
        case (.english, .startNewSession):
            return "New sessions at your fingertips. Open VibeSpot and type new."
        case (.english, .allowTerminalControl):
            return "Allow Terminal control to start new sessions from VibeSpot."
        case (.english, .quickSetup):
            return "Choose whether VibeSpot opens when you sign in."
        case (.chinese, .quickActivation):
            return "按下快捷键，立刻打开 VibeSpot。"
        case (.chinese, .shortcutSetup):
            return "默认是 \(defaultHotkey)，你也可以现在改。"
        case (.chinese, .fastSwitch):
            return "按 Enter，直接回到正在进行中的对话。"
        case (.chinese, .searchSessions):
            return "搜索任意 session。按 Tab 在历史记录和进行中的 session 之间切换，按 Enter 恢复或打开。"
        case (.chinese, .checkAccess):
            return "先让 VibeSpot 读到本地历史记录，搜索才有用。"
        case (.chinese, .startNewSession):
            return "输入 new claude 或 new codex，直接开始新 session。"
        case (.chinese, .allowTerminalControl):
            return "允许控制 Terminal，直接启动新的 session。"
        case (.chinese, .quickSetup):
            return "选择是否在登录后自动打开 VibeSpot。"
        }
    }

    func cardChromeLabel(for card: OnboardingCard) -> String {
        switch (self, card) {
        case (.english, .quickActivation):
            return "Quick activation"
        case (.english, .shortcutSetup):
            return "Shortcut setup"
        case (.english, .fastSwitch):
            return "Fast switch"
        case (.english, .searchSessions):
            return "Search sessions"
        case (.english, .checkAccess):
            return "Check access"
        case (.english, .startNewSession):
            return "Start new session"
        case (.english, .allowTerminalControl):
            return "Terminal access"
        case (.english, .quickSetup):
            return "Quick setup"
        case (.chinese, .quickActivation):
            return "快捷唤起"
        case (.chinese, .shortcutSetup):
            return "设置快捷键"
        case (.chinese, .fastSwitch):
            return "快速切回"
        case (.chinese, .searchSessions):
            return "搜索会话"
        case (.chinese, .checkAccess):
            return "检查访问"
        case (.chinese, .startNewSession):
            return "启动新会话"
        case (.chinese, .allowTerminalControl):
            return "Terminal 权限"
        case (.chinese, .quickSetup):
            return "快速设置"
        }
    }

    func demoChips(for card: OnboardingCard, hotkey: String) -> [String] {
        switch (self, card) {
        case (.english, .quickActivation):
            return [hotkey, "Panel", "Live state"]
        case (.english, .fastSwitch):
            return ["Enter", "Jump back", "Current session"]
        case (.english, .searchSessions):
            return ["Search", "Tab", "Enter"]
        case (.english, .startNewSession):
            return ["new claude", "new codex", "Launch"]
        case (.chinese, .quickActivation):
            return [hotkey, "面板", "实时状态"]
        case (.chinese, .fastSwitch):
            return ["Enter", "切回", "当前会话"]
        case (.chinese, .searchSessions):
            return ["搜索", "Tab", "Enter"]
        case (.chinese, .startNewSession):
            return ["new claude", "new codex", "启动"]
        default:
            return []
        }
    }

    func terminalStatusText(for status: TerminalAutomationCheckResult.Status) -> String {
        switch (self, status) {
        case (.english, .unknown):
            return "Not checked yet"
        case (.english, .ready):
            return "Ready"
        case (.english, .needsAccess):
            return "Needs access"
        case (.english, .unavailable):
            return "Unavailable"
        case (.chinese, .unknown):
            return "尚未检查"
        case (.chinese, .ready):
            return "已就绪"
        case (.chinese, .needsAccess):
            return "需要权限"
        case (.chinese, .unavailable):
            return "不可用"
        }
    }
}

enum OnboardingCard: String, CaseIterable, Sendable, Equatable {
    case quickActivation
    case shortcutSetup
    case fastSwitch
    case searchSessions
    case checkAccess
    case startNewSession
    case allowTerminalControl
    case quickSetup
}

struct OnboardingStatusPillState: Codable, Equatable, Sendable {
    let label: String
    let value: String
    let tone: String
}

struct OnboardingRightPaneState: Codable, Equatable, Sendable {
    let kind: String
    let chromeLabel: String
    let placeholderLabel: String?
    let placeholderPrompt: String?
    let demoChips: [String]?
    let shortcutActions: [String]?
    let accessStatuses: [OnboardingStatusPillState]?
    let accessActionTitle: String?
    let terminalStatus: OnboardingStatusPillState?
    let terminalActionTitle: String?
    let launchAtLoginLabel: String?
    let launchAtLoginSupportedLabel: String?
}

struct OnboardingViewState: Codable, Equatable, Sendable {
    let languageCode: String
    let cardID: String
    let cardIndex: Int
    let cardCount: Int
    let progressLabel: String
    let sentence: String
    let hotkey: String
    let defaultHotkey: String
    let canGoBack: Bool
    let canFinish: Bool
    let backLabel: String
    let primaryActionTitle: String
    let rightPane: OnboardingRightPaneState
    let launchAtLogin: Bool
}
