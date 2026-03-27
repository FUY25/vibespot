import AppKit
import WebKit

@MainActor
final class SearchPanelController: NSObject, WebBridgeDelegate, WKNavigationDelegate {
    var onSelect: ((SearchResult) -> Void)?
    var sessionIndex: SessionIndex?
    var isVisible: Bool { panel.isVisible }
    var hidesOnDeactivate: Bool { panel.hidesOnDeactivate }

    private let panel: SearchPanel
    private let webView: WKWebView
    private let webBridge = WebBridge()
    private let searchDebouncer = Debouncer(delay: 0.08)

    private var results: [SearchResult] = []
    private var deactivationObserver: NSObjectProtocol?
    private var panelResignKeyObserver: NSObjectProtocol?
    private var lastPushedResultsJSON: String = ""
    private var isWebViewReady = false
    private var pendingResetAndFocus = false
    private var pendingTheme: String?
    private var pendingResultsJSON: String?
    private var iconBaseURL: String?

    private let panelWidth: CGFloat = 720
    private let minPanelHeight: CGFloat = 104

    private static let isRunningTests: Bool = {
        if NSClassFromString("XCTestCase") != nil { return true }
        let processName = ProcessInfo.processInfo.processName.lowercased()
        if processName.contains("xctest") { return true }
        return ProcessInfo.processInfo.environment.keys.contains { key in
            key.localizedCaseInsensitiveContains("xctest")
                || key.localizedCaseInsensitiveContains("swift_testing")
        }
    }()

    override init() {
        self.panel = SearchPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: minPanelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        let config = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        config.userContentController = contentController
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        self.webView = WKWebView(frame: .zero, configuration: config)

        super.init()

        contentController.add(webBridge, name: "bridge")
        webBridge.delegate = self

        configurePanel()
        configureWebView()
        configureInteractions()
    }

    func toggle() {
        panel.isVisible ? hide() : show()
    }

    func show() {
        searchDebouncer.cancel()

        if !panel.isVisible {
            centerPanelOnActiveScreen()
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        requestResetAndFocus()
        pushTheme()
        refreshResults(query: "")
    }

    func hide() {
        searchDebouncer.cancel()
        panel.orderOut(nil)
    }

    // MARK: - WebBridgeDelegate

    func webBridge(_ bridge: WebBridge, didReceiveSearch query: String) {
        refreshResults(query: query)
    }

    func webBridge(_ bridge: WebBridge, didSelectSession sessionId: String, status: String, tool: String) {
        guard let result = results.first(where: { $0.sessionId == sessionId }) else { return }
        hide()
        onSelect?(result)
    }

    func webBridgeDidRequestEscape(_ bridge: WebBridge) {
        hide()
    }

    func webBridge(_ bridge: WebBridge, didRequestResize height: CGFloat) {
        guard height > 0 else { return }
        var frame = panel.frame
        let maxY = frame.maxY
        let newHeight = max(minPanelHeight, height + 2) // +2 for border
        frame.size = NSSize(width: panelWidth, height: newHeight)
        frame.origin.y = maxY - newHeight
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    // MARK: - Private

    private func refreshResults(query: String) {
        guard let sessionIndex else {
            pushResults([])
            return
        }

        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let matches = try sessionIndex.search(query: trimmed, liveOnly: trimmed.isEmpty)
            if trimmed.lowercased().hasPrefix("new") {
                let actionRows = makeNewSessionActionRows()
                pushResults(actionRows + matches)
            } else {
                pushResults(matches)
            }
        } catch {
            pushResults([])
            print("SearchPanelController search failed: \(error)")
        }
    }

    private func pushResults(_ newResults: [SearchResult]) {
        results = newResults
        let json = WebBridge.resultsToJSONString(results)

        // Skip push if results haven't changed
        guard json != lastPushedResultsJSON else { return }
        lastPushedResultsJSON = json
        pendingResultsJSON = json

        guard isWebViewReady else { return }
        pushResultsJSONIfNeeded()
    }

    private func pushResultsJSONIfNeeded() {
        guard let json = pendingResultsJSON else { return }
        pendingResultsJSON = nil
        let escaped = escapeForSingleQuotedJavaScriptString(json)
        webView.evaluateJavaScript("updateResults('\(escaped)')", completionHandler: nil)
        updateGhostSuggestion()
    }

    private func updateGhostSuggestion() {
        guard isWebViewReady else { return }

        // Get the current search query from JS and compute ghost
        webView.evaluateJavaScript("document.getElementById('searchInput').value") { [weak self] value, _ in
            guard let self, let query = value as? String, !query.isEmpty else {
                self?.webView.evaluateJavaScript("setGhostSuggestion(null)", completionHandler: nil)
                return
            }

            let suggestion = self.computeGhostSuggestion(query: query)
            if let suggestion {
                let escaped = suggestion.replacingOccurrences(of: "'", with: "\\'")
                self.webView.evaluateJavaScript("setGhostSuggestion('\(escaped)')", completionHandler: nil)
            } else {
                self.webView.evaluateJavaScript("setGhostSuggestion(null)", completionHandler: nil)
            }
        }
    }

    private func computeGhostSuggestion(query: String) -> String? {
        let titleMatch = results.first(where: {
            $0.title.lowercased().hasPrefix(query.lowercased())
        })?.title

        let projectMatch = titleMatch ?? results.first(where: {
            let name = $0.projectName.isEmpty
                ? URL(fileURLWithPath: $0.project).lastPathComponent
                : $0.projectName
            return name.lowercased().hasPrefix(query.lowercased())
        }).map {
            $0.projectName.isEmpty
                ? URL(fileURLWithPath: $0.project).lastPathComponent
                : $0.projectName
        }

        return titleMatch ?? projectMatch
    }

    private func makeNewSessionActionRows() -> [SearchResult] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let recentProject = (try? sessionIndex?.mostRecentProject()) ?? nil
        let project = recentProject?.project.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectName = recentProject?.projectName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedProject = project.isEmpty ? homePath : project
        let resolvedProjectName = projectName.isEmpty ? "~" : projectName
        let now = Date()

        return [
            SearchResult(
                sessionId: "new-claude", tool: "claude", title: "New Claude session",
                project: resolvedProject, projectName: resolvedProjectName, gitBranch: "",
                status: "action", startedAt: now, pid: nil, tokenCount: 0,
                lastActivityAt: now, activityPreview: nil, activityStatus: .closed, snippet: nil
            ),
            SearchResult(
                sessionId: "new-codex", tool: "codex", title: "New Codex session",
                project: resolvedProject, projectName: resolvedProjectName, gitBranch: "",
                status: "action", startedAt: now, pid: nil, tokenCount: 0,
                lastActivityAt: now, activityPreview: nil, activityStatus: .closed, snippet: nil
            ),
        ]
    }

    private func pushTheme() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = isDark ? "dark" : "light"
        pendingTheme = theme

        guard isWebViewReady else { return }
        pushThemeIfNeeded()
    }

    private func pushThemeIfNeeded() {
        guard let theme = pendingTheme else { return }
        pendingTheme = nil
        webView.evaluateJavaScript("setTheme('\(theme)')", completionHandler: nil)
    }

    private func requestResetAndFocus() {
        pendingResetAndFocus = true
        guard isWebViewReady else { return }
        flushPendingWebViewState()
    }

    private func flushPendingWebViewState() {
        if let iconBaseURL {
            let escapedBaseURL = escapeForSingleQuotedJavaScriptString(iconBaseURL)
            webView.evaluateJavaScript("setIconBaseURL('\(escapedBaseURL)')", completionHandler: nil)
            self.iconBaseURL = nil
        }

        pushThemeIfNeeded()

        if pendingResetAndFocus {
            pendingResetAndFocus = false
            webView.evaluateJavaScript("resetAndFocus()", completionHandler: nil)
        }

        pushResultsJSONIfNeeded()
    }

    private func escapeForSingleQuotedJavaScriptString(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
    }

    private func configurePanel() {
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false // Shadow handled by CSS
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.animationBehavior = .utilityWindow
    }

    private func configureWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.setValue(false, forKey: "drawsBackground")

        let container = NSView(frame: panel.frame)
        container.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = container
        container.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            webView.topAnchor.constraint(equalTo: container.topAnchor),
            webView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        isWebViewReady = false

        // Load panel.html from bundle
        if let htmlURL = Bundle.module.url(forResource: "panel", withExtension: "html", subdirectory: "Web") {
            iconBaseURL = Bundle.module.url(forResource: "claude-icon", withExtension: "png")?
                .deletingLastPathComponent()
                .absoluteString

            let readAccessRoot = Bundle.module.resourceURL ?? htmlURL.deletingLastPathComponent()
            webView.loadFileURL(htmlURL, allowingReadAccessTo: readAccessRoot)
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            isWebViewReady = true
            flushPendingWebViewState()
        }
    }

    private func configureInteractions() {
        guard !Self.isRunningTests else { return }

        deactivationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.hide() }
        }

        panelResignKeyObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: panel, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard NSApp.isActive else { return }
                try? await Task.sleep(for: .milliseconds(50))
                guard panel.isVisible, !panel.isKeyWindow, NSApp.isActive else { return }
                guard let keyWindow = NSApp.keyWindow, keyWindow !== panel else { return }
                hide()
            }
        }

        // Watch for appearance changes to push theme
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pushTheme() }
        }
    }

    @MainActor
    deinit {
        if let observer = deactivationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = panelResignKeyObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func centerPanelOnActiveScreen() {
        guard let screen = activeScreen() else {
            panel.center()
            return
        }
        let visibleFrame = screen.visibleFrame
        let topOffset = max(visibleFrame.height * 0.18, 96)
        let origin = NSPoint(
            x: visibleFrame.midX - panelWidth / 2,
            y: max(visibleFrame.minY + 24, visibleFrame.maxY - panel.frame.height - topOffset)
        )
        panel.setFrameOrigin(origin)
    }

    private func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
    }
}

private final class SearchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
