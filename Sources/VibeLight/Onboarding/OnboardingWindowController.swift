import AppKit
import WebKit

@MainActor
final class OnboardingWindowController: NSWindowController, WKNavigationDelegate, OnboardingBridgeDelegate {
    enum Step {
        case welcome
        case setup
    }

    private let settingsStore: SettingsStore
    private let launchAtLoginSupported: Bool
    private let environmentCheckService: EnvironmentCheckService
    private let onFinish: @MainActor @Sendable () -> Void
    private var settings: AppSettings
    private var environmentResult: EnvironmentCheckResult?
    private var environmentCheckTask: Task<Void, Never>?
    private(set) var step: Step = .welcome

    private let webView: WKWebView
    private let bridge = OnboardingBridge()
    private var isWebViewReady = false
    private var pendingStateJSON: String?

    init(
        settingsStore: SettingsStore,
        launchAtLoginSupported: Bool = LaunchAtLoginManager().isSupportedRuntime,
        environmentCheckService: EnvironmentCheckService = EnvironmentCheckService(),
        onFinish: @escaping @MainActor @Sendable () -> Void
    ) {
        self.settingsStore = settingsStore
        self.launchAtLoginSupported = launchAtLoginSupported
        self.environmentCheckService = environmentCheckService
        self.onFinish = onFinish
        self.settings = settingsStore.load()

        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        config.userContentController = contentController
        self.webView = WKWebView(frame: .zero, configuration: config)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = VibeSpotBranding.welcomeTitle
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
    }

    func showOnboarding() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
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
        var payload: [String: Any] = [
            "step": step == .welcome ? "welcome" : "setup",
            "launchAtLogin": settings.launchAtLogin,
            "launchAtLoginSupported": launchAtLoginSupported,
            "hotkey": settings.hotkeyBinding.displayString,
        ]

        switch step {
        case .welcome:
            payload["headline"] = "Spotlight for Claude Code and Codex."
            payload["body"] = "Jump back into live agent runs and past threads from one fast native search surface."
            payload["detail"] = "Everything stays local. VibeSpot reads the session data already on your machine and helps you switch context before you lose it."
        case .setup:
            payload["body"] = "VibeSpot is ready once it can either search local session history or help you start a first session."
            payload["checksRunning"] = environmentCheckTask != nil && environmentResult == nil
            if let environmentResult {
                payload["headline"] = environmentResult.readinessHeadline
                payload["detail"] = environmentResult.readinessDetail
                payload["codexFound"] = environmentResult.codex.isAvailable
                payload["claudeFound"] = environmentResult.claude.isAvailable
                payload["codexHistoryStatus"] = environmentResult.codexData.statusLabel
                payload["claudeHistoryStatus"] = environmentResult.claudeData.statusLabel
                payload["canFinish"] = environmentResult.canFinishOnboarding
                payload["missingPaths"] = environmentResult.missingAccessiblePaths
                payload["checkedPaths"] = environmentResult.checkedPaths
            } else {
                payload["headline"] = "Check your local environment"
                payload["detail"] = "Run checks so VibeSpot can verify that you either have local session history or at least one supported CLI ready."
                payload["codexFound"] = false
                payload["claudeFound"] = false
                payload["codexHistoryStatus"] = "Unknown"
                payload["claudeHistoryStatus"] = "Unknown"
                payload["canFinish"] = false
                payload["missingPaths"] = []
                payload["checkedPaths"] = []
            }
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: payload),
            let json = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return json
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

    private func finishOnboarding() {
        if step == .setup, environmentResult?.canFinishOnboarding == false {
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

    func onboardingBridgeDidRequestContinue(_ bridge: OnboardingBridge) {
        step = .setup
        updateWebState()
        runEnvironmentChecks()
    }

    func onboardingBridgeDidRequestBack(_ bridge: OnboardingBridge) {
        environmentCheckTask?.cancel()
        environmentCheckTask = nil
        step = .welcome
        updateWebState()
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
        let newHeight = max(560, min(height + 44, 700))
        frame.size.height = newHeight
        frame.origin.y = maxY - newHeight
        window.setFrame(frame, display: true, animate: true)
    }
}
