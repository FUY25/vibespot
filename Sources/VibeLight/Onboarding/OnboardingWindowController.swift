import AppKit
import WebKit

@MainActor
final class OnboardingWindowController: NSWindowController, WKNavigationDelegate, OnboardingBridgeDelegate {
    private let settingsStore: SettingsStore
    private let launchAtLoginSupported: Bool
    private let environmentCheckService: EnvironmentCheckService
    private let terminalAutomationChecker: any TerminalAutomationChecking
    private let onFinish: @MainActor @Sendable () -> Void

    private var settings: AppSettings
    private var environmentResult: EnvironmentCheckResult?
    private var terminalAutomationResult = TerminalAutomationCheckResult(status: .unknown)
    private var environmentCheckTask: Task<Void, Never>?
    private var terminalCheckTask: Task<Void, Never>?

    private let language: OnboardingLanguage
    private(set) var currentCard: OnboardingCard = .quickActivation

    private let webView: WKWebView
    private let bridge = OnboardingBridge()
    private var isWebViewReady = false
    private var pendingStateJSON: String?

    init(
        settingsStore: SettingsStore,
        launchAtLoginSupported: Bool = LaunchAtLoginManager().isSupportedRuntime,
        environmentCheckService: EnvironmentCheckService = EnvironmentCheckService(),
        terminalAutomationChecker: any TerminalAutomationChecking = TerminalAutomationCheckService(),
        preferredLanguageCodeProvider: @escaping @Sendable () -> String? = { Locale.preferredLanguages.first },
        onFinish: @escaping @MainActor @Sendable () -> Void
    ) {
        self.settingsStore = settingsStore
        self.launchAtLoginSupported = launchAtLoginSupported
        self.environmentCheckService = environmentCheckService
        self.terminalAutomationChecker = terminalAutomationChecker
        self.onFinish = onFinish
        self.settings = settingsStore.load()
        self.language = OnboardingLanguage(preferredLanguageCode: preferredLanguageCodeProvider())

        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        config.userContentController = contentController
        self.webView = WKWebView(frame: .zero, configuration: config)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = language.windowTitle
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        if #available(macOS 13.0, *) {
            window.toolbarStyle = .preference
        }

        super.init(window: window)

        bridge.delegate = self
        contentController.add(bridge, name: "onboardingBridge")

        configureWindow()
        updateWebState()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        environmentCheckTask?.cancel()
        terminalCheckTask?.cancel()
    }

    func showOnboarding() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func makeViewStateForTesting() -> OnboardingViewState {
        makeViewState()
    }

    private func configureWindow() {
        guard let contentView = window?.contentView else { return }

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        contentView.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            webView.topAnchor.constraint(equalTo: contentView.topAnchor),
            webView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        if let htmlURL = Bundle.module.url(forResource: "onboarding", withExtension: "html", subdirectory: "Web")
            ?? Bundle.module.url(forResource: "onboarding", withExtension: "html")
        {
            let readAccessRoot = Bundle.module.resourceURL ?? htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: readAccessRoot)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isWebViewReady = true
            self.flushPendingState()
        }
    }

    private func updateWebState() {
        pendingStateJSON = makeStateJSON()
        flushPendingState()
    }

    private func flushPendingState() {
        guard isWebViewReady, let pendingStateJSON else { return }
        self.pendingStateJSON = nil
        let escaped = pendingStateJSON
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        webView.evaluateJavaScript("updateOnboardingState('\(escaped)')", completionHandler: nil)
    }

    private func makeStateJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(makeViewState()),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    private func makeViewState() -> OnboardingViewState {
        let cardIndex = OnboardingCard.allCases.firstIndex(of: currentCard) ?? 0
        let defaultHotkey = HotkeyBinding.default.displayString
        let hotkey = settings.hotkeyBinding.displayString
        let accessStatuses = makeAccessStatuses()
        let rightPane: OnboardingRightPaneState

        switch currentCard {
        case .quickActivation, .fastSwitch, .searchSessions, .startNewSession:
            rightPane = OnboardingRightPaneState(
                kind: "demo",
                chromeLabel: language.cardChromeLabel(for: currentCard),
                placeholderLabel: language.gifPlaceholderLabel,
                placeholderPrompt: language.demoPlaceholderPrompt,
                shortcutActions: nil,
                accessStatuses: nil,
                accessActionTitle: nil,
                terminalStatus: nil,
                terminalActionTitle: nil,
                launchAtLoginLabel: nil,
                launchAtLoginSupportedLabel: nil
            )
        case .shortcutSetup:
            rightPane = OnboardingRightPaneState(
                kind: "shortcut",
                chromeLabel: language.cardChromeLabel(for: currentCard),
                placeholderLabel: nil,
                placeholderPrompt: nil,
                shortcutActions: [language.changeShortcutLabel, language.resetShortcutLabel],
                accessStatuses: nil,
                accessActionTitle: nil,
                terminalStatus: nil,
                terminalActionTitle: nil,
                launchAtLoginLabel: nil,
                launchAtLoginSupportedLabel: nil
            )
        case .checkAccess:
            rightPane = OnboardingRightPaneState(
                kind: "access",
                chromeLabel: language.cardChromeLabel(for: currentCard),
                placeholderLabel: nil,
                placeholderPrompt: nil,
                shortcutActions: nil,
                accessStatuses: accessStatuses,
                accessActionTitle: environmentCheckTask == nil ? language.runChecksLabel : language.checkingLabel,
                terminalStatus: nil,
                terminalActionTitle: nil,
                launchAtLoginLabel: nil,
                launchAtLoginSupportedLabel: nil
            )
        case .allowTerminalControl:
            rightPane = OnboardingRightPaneState(
                kind: "terminal",
                chromeLabel: language.cardChromeLabel(for: currentCard),
                placeholderLabel: nil,
                placeholderPrompt: nil,
                shortcutActions: nil,
                accessStatuses: nil,
                accessActionTitle: nil,
                terminalStatus: makeTerminalStatusPill(),
                terminalActionTitle: terminalAutomationResult.status == .ready ? language.checkAgainLabel : language.allowTerminalLabel,
                launchAtLoginLabel: nil,
                launchAtLoginSupportedLabel: nil
            )
        case .quickSetup:
            rightPane = OnboardingRightPaneState(
                kind: "quickSetup",
                chromeLabel: language.cardChromeLabel(for: currentCard),
                placeholderLabel: nil,
                placeholderPrompt: nil,
                shortcutActions: nil,
                accessStatuses: nil,
                accessActionTitle: nil,
                terminalStatus: nil,
                terminalActionTitle: nil,
                launchAtLoginLabel: language.openAtLoginLabel,
                launchAtLoginSupportedLabel: launchAtLoginSupported ? nil : language.unsupportedLaunchAtLoginLabel
            )
        }

        return OnboardingViewState(
            languageCode: language.code,
            cardID: currentCard.rawValue,
            cardIndex: cardIndex,
            cardCount: OnboardingCard.allCases.count,
            progressLabel: "\(cardIndex + 1) / \(OnboardingCard.allCases.count)",
            sentence: language.sentence(for: currentCard, defaultHotkey: defaultHotkey),
            hotkey: hotkey,
            defaultHotkey: defaultHotkey,
            canGoBack: cardIndex > 0,
            canFinish: currentCard == .quickSetup && (environmentResult?.canFinishOnboarding ?? false),
            quitLabel: language.quitLabel,
            backLabel: language.backLabel,
            primaryActionTitle: currentCard == .quickSetup ? language.finishLabel : language.nextLabel,
            rightPane: rightPane,
            launchAtLogin: settings.launchAtLogin
        )
    }

    private func makeAccessStatuses() -> [OnboardingStatusPillState] {
        guard let environmentResult else {
            return [
                OnboardingStatusPillState(label: toolHistoryLabel("Codex"), value: localizedUnknownStatus(), tone: "neutral"),
                OnboardingStatusPillState(label: toolHistoryLabel("Claude"), value: localizedUnknownStatus(), tone: "neutral"),
            ]
        }

        return [
            makeAccessStatus(label: toolHistoryLabel("Codex"), state: environmentResult.codexData),
            makeAccessStatus(label: toolHistoryLabel("Claude"), state: environmentResult.claudeData),
        ]
    }

    private func toolHistoryLabel(_ tool: String) -> String {
        switch language {
        case .english:
            return "\(tool) history"
        case .chinese:
            return "\(tool) 历史记录"
        }
    }

    private func localizedUnknownStatus() -> String {
        switch language {
        case .english:
            return "Not checked"
        case .chinese:
            return "未检查"
        }
    }

    private func makeAccessStatus(label: String, state: EnvironmentCheckResult.SessionDataState) -> OnboardingStatusPillState {
        let value: String
        let tone: String
        if state.hasSessionData {
            value = language == .english ? "Ready" : "已就绪"
            tone = "ready"
        } else if state.exists == false {
            value = language == .english ? "Missing" : "未找到"
            tone = "warn"
        } else if state.isReadable == false {
            value = language == .english ? "Unreadable" : "不可读取"
            tone = "warn"
        } else {
            value = language == .english ? "Empty" : "为空"
            tone = "neutral"
        }

        return OnboardingStatusPillState(label: label, value: value, tone: tone)
    }

    private func makeTerminalStatusPill() -> OnboardingStatusPillState {
        let tone: String
        switch terminalAutomationResult.status {
        case .ready:
            tone = "ready"
        case .unknown:
            tone = "neutral"
        case .needsAccess, .unavailable:
            tone = "warn"
        }

        return OnboardingStatusPillState(
            label: language == .english ? "Terminal" : "Terminal",
            value: language.terminalStatusText(for: terminalAutomationResult.status),
            tone: tone
        )
    }

    private func advanceCard() {
        guard let index = OnboardingCard.allCases.firstIndex(of: currentCard),
              index < OnboardingCard.allCases.count - 1 else {
            return
        }
        currentCard = OnboardingCard.allCases[index + 1]
        enterCardIfNeeded()
        updateWebState()
    }

    private func goBackCard() {
        guard let index = OnboardingCard.allCases.firstIndex(of: currentCard),
              index > 0 else {
            return
        }
        currentCard = OnboardingCard.allCases[index - 1]
        updateWebState()
    }

    private func enterCardIfNeeded() {
        if currentCard == .checkAccess, environmentResult == nil, environmentCheckTask == nil {
            runEnvironmentChecks()
        }
    }

    private func runEnvironmentChecks() {
        environmentResult = nil
        updateWebState()

        environmentCheckTask?.cancel()
        let service = environmentCheckService
        environmentCheckTask = Task.detached(priority: .utility) { [service] in
            let result = await service.runChecks()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.environmentCheckTask = nil
                self.environmentResult = result
                self.updateWebState()
            }
        }
    }

    private func runTerminalAutomationCheck() {
        terminalCheckTask?.cancel()
        let checker = terminalAutomationChecker
        terminalCheckTask = Task.detached(priority: .utility) { [checker] in
            let result = await checker.runCheck()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.terminalCheckTask = nil
                self.terminalAutomationResult = result
                self.updateWebState()
            }
        }
    }

    private func finishOnboarding() {
        guard currentCard == .quickSetup, environmentResult?.canFinishOnboarding == true else {
            return
        }
        settings.onboardingCompleted = true
        settingsStore.save(settings)
        onFinish()
    }

    private func openShortcutPicker() {
        guard let window else { return }
        let controller = ShortcutCaptureWindowController(currentBinding: settings.hotkeyBinding) { [weak self] binding in
            guard let self else { return }
            self.settings.hotkeyKeyCode = binding.keyCode
            self.settings.hotkeyModifiers = binding.modifiers
            self.updateWebState()
        }
        controller.presentSheet(for: window)
    }

    // MARK: - OnboardingBridgeDelegate

    func onboardingBridgeDidRequestNext(_ bridge: OnboardingBridge) {
        advanceCard()
    }

    func onboardingBridgeDidRequestBack(_ bridge: OnboardingBridge) {
        goBackCard()
    }

    func onboardingBridgeDidRequestQuit(_ bridge: OnboardingBridge) {
        window?.close()
    }

    func onboardingBridgeDidRequestFinish(_ bridge: OnboardingBridge) {
        finishOnboarding()
    }

    func onboardingBridgeDidRequestRunChecks(_ bridge: OnboardingBridge) {
        runEnvironmentChecks()
    }

    func onboardingBridgeDidRequestRunTerminalCheck(_ bridge: OnboardingBridge) {
        runTerminalAutomationCheck()
    }

    func onboardingBridge(_ bridge: OnboardingBridge, didSetLaunchAtLogin enabled: Bool) {
        guard launchAtLoginSupported else {
            updateWebState()
            return
        }
        settings.launchAtLogin = enabled
        updateWebState()
    }

    func onboardingBridgeDidRequestShortcutChange(_ bridge: OnboardingBridge) {
        openShortcutPicker()
    }

    func onboardingBridgeDidRequestShortcutReset(_ bridge: OnboardingBridge) {
        settings.hotkeyKeyCode = HotkeyBinding.default.keyCode
        settings.hotkeyModifiers = HotkeyBinding.default.modifiers
        updateWebState()
    }

    func onboardingBridge(_ bridge: OnboardingBridge, didRequestResize height: CGFloat) {
        guard height > 0, let window else { return }
        var frame = window.frame
        let maxY = frame.maxY
        let newHeight = max(540, min(height + 44, 720))
        frame.size.height = newHeight
        frame.origin.y = maxY - newHeight
        window.setFrame(frame, display: true, animate: true)
    }
}
