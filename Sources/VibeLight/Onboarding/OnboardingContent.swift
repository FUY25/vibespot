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

    var quitLabel: String {
        switch self {
        case .english:
            return "Quit"
        case .chinese:
            return "退出"
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
            return "GIF placeholder"
        case .chinese:
            return "GIF 占位"
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
            return "Press your shortcut and VibeSpot appears instantly with your current session state and context."
        case (.english, .shortcutSetup):
            return "The default shortcut is \(defaultHotkey), and you can change it here if another combo feels more natural."
        case (.english, .fastSwitch):
            return "Press Enter to jump straight back into the conversation that is still running."
        case (.english, .searchSessions):
            return "Search sessions or active sessions here, press Tab to switch state, and press Enter to resume history or surface the current active session."
        case (.english, .checkAccess):
            return "VibeSpot needs to find and read your local chat history before session search becomes genuinely useful."
        case (.english, .startNewSession):
            return "Type new claude or new codex in the search bar to launch a fresh session immediately."
        case (.english, .allowTerminalControl):
            return "To launch a new session directly, VibeSpot may need permission to control Terminal."
        case (.english, .quickSetup):
            return "Choose whether VibeSpot should open automatically whenever you sign in."
        case (.chinese, .quickActivation):
            return "按下快捷键后，VibeSpot 会立刻出现，并显示你当前的会话状态和上下文。"
        case (.chinese, .shortcutSetup):
            return "默认快捷键是 \(defaultHotkey)，如果你有更顺手的组合，也可以在这里改掉。"
        case (.chinese, .fastSwitch):
            return "按下 Enter 就可以直接回到正在进行中的对话，不用再自己找窗口。"
        case (.chinese, .searchSessions):
            return "你可以在这里搜索 session 或现有 session，按 Tab 切换状态，按 Enter 恢复历史对话或调出当前 active session。"
        case (.chinese, .checkAccess):
            return "VibeSpot 需要先找到并读取你本地的 chat history，session 搜索才会真正有用。"
        case (.chinese, .startNewSession):
            return "在搜索栏输入 new claude 或 new codex，就可以直接唤起一个新的 session。"
        case (.chinese, .allowTerminalControl):
            return "为了直接启动新的 session，VibeSpot 可能需要获得控制 Terminal 的权限。"
        case (.chinese, .quickSetup):
            return "你可以顺手决定是否在登录后自动打开 VibeSpot。"
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
    let quitLabel: String
    let backLabel: String
    let primaryActionTitle: String
    let rightPane: OnboardingRightPaneState
    let launchAtLogin: Bool
}
