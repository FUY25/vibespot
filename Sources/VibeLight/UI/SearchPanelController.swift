import AppKit
import WebKit

struct NewSessionCommand: Equatable, Sendable {
    let tool: String
    let flags: [String]
    let prompt: String
}

@MainActor
final class SearchPanelController: NSObject, WebBridgeDelegate, WKNavigationDelegate {
    var onSelect: ((SearchResult) -> Void)?
    var onLaunchAction: ((String, String) -> Void)?
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
    private var appearanceObservation: NSKeyValueObservation?
    private var lastPushedResultsJSON: String = ""
    private var lastSearchQuery: String?
    private var isWebViewReady = false
    private var pendingResetAndFocus = false
    private var pendingTheme: String?
    private var pendingResultsJSON: String?
    private var iconBaseURL: String?

    private let panelWidth: CGFloat = 720
    private let previewExtraWidth: CGFloat = 470
    private let minPanelHeight: CGFloat = 104
    private var isPreviewVisible = false
    private var isLiveOnlyMode = false

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
        isPreviewVisible = false

        if !panel.isVisible {
            centerPanelOnActiveScreen()
        }

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)

        requestResetAndFocus()
        pushTheme()
        pushMode()
        refreshResults(query: "")
    }

    func hide() {
        searchDebouncer.cancel()
        isPreviewVisible = false
        panel.orderOut(nil)
    }

    // MARK: - WebBridgeDelegate

    func webBridge(_ bridge: WebBridge, didReceiveSearch query: String) {
        lastSearchQuery = query
        refreshResults(query: query)
    }

    func webBridge(_ bridge: WebBridge, didSelectSession sessionId: String, status: String, tool: String) {
        guard let result = results.first(where: { $0.sessionId == sessionId }) else { return }
        hide()
        if result.status == "action" {
            let query = lastSearchQuery ?? ""
            let command = Self.newSessionLaunchCommand(selectedTool: result.tool, query: query)
            let directory = Self.normalizedLaunchDirectory(from: result.project)
            if let onLaunchAction {
                onLaunchAction(command, directory)
            } else {
                TerminalLauncher.launch(command: command, directory: directory)
            }
            return
        }
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
        let currentWidth = isPreviewVisible ? panelWidth + previewExtraWidth : panelWidth
        frame.size = NSSize(width: currentWidth, height: newHeight)
        frame.origin.y = maxY - newHeight
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }

    func webBridge(_ bridge: WebBridge, didRequestPreview sessionId: String) {
        guard let fileURL = findSessionFile(sessionId: sessionId) else { return }
        let liveResult = results.first(where: { $0.sessionId == sessionId })
        Task.detached(priority: .utility) { [weak self] in
            let transcriptPreview = TranscriptTailReader.read(fileURL: fileURL)
            let mergedPreview = Self.mergePreviewState(transcriptPreview: transcriptPreview, with: liveResult)
            let json = TranscriptTailReader.previewToJSONString(mergedPreview)
            await MainActor.run { [weak self] in
                guard let self, self.isWebViewReady else { return }
                let escaped = self.escapeForSingleQuotedJavaScriptString(json)
                self.webView.evaluateJavaScript("updatePreview('\(escaped)')", completionHandler: nil)
            }
        }
    }

    func webBridge(_ bridge: WebBridge, didChangePreviewVisibility visible: Bool) {
        isPreviewVisible = visible
        var frame = panel.frame
        let targetWidth = visible ? panelWidth + previewExtraWidth : panelWidth
        frame.size.width = targetWidth
        panel.setFrame(frame, display: true, animate: false)
    }

    func webBridgeDidToggleMode(_ bridge: WebBridge) {
        isLiveOnlyMode.toggle()
        let fallbackQuery = lastSearchQuery ?? ""
        guard isWebViewReady else {
            refreshResults(query: fallbackQuery)
            return
        }

        webView.evaluateJavaScript("document.getElementById('searchInput')?.value ?? ''") { [weak self] value, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let currentQuery = (value as? String) ?? fallbackQuery
                self.lastSearchQuery = currentQuery
                self.refreshResults(query: currentQuery)
                self.pushMode()
            }
        }
    }

    // MARK: - Private

    private func findSessionFile(sessionId: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fm = FileManager.default

        let claudeProjectsPath = home + "/.claude/projects"
        if let projectDirs = try? fm.contentsOfDirectory(atPath: claudeProjectsPath) {
            for projectDir in projectDirs {
                let path = "\(claudeProjectsPath)/\(projectDir)/\(sessionId).jsonl"
                if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
            }
        }

        // Codex: exact match first
        let codexPath = home + "/.codex/sessions/\(sessionId).jsonl"
        if fm.fileExists(atPath: codexPath) { return URL(fileURLWithPath: codexPath) }

        // Codex: session files may have prefixed names (e.g. rollout-...-<uuid>.jsonl)
        let codexRoot = URL(fileURLWithPath: home + "/.codex/sessions", isDirectory: true)
        if let enumerator = fm.enumerator(
            at: codexRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                guard fileURL.pathExtension == "jsonl" else { continue }
                let fileName = fileURL.deletingPathExtension().lastPathComponent
                if fileName.contains(sessionId) {
                    return fileURL
                }
            }
        }

        return nil
    }

    private func refreshResults(query: String) {
        guard let sessionIndex else {
            pushResults([])
            return
        }

        do {
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let effectiveLiveOnly = trimmed.isEmpty ? true : isLiveOnlyMode
            let matches = try sessionIndex.search(query: trimmed, liveOnly: effectiveLiveOnly)
            let command = Self.parseNewSessionCommand(from: trimmed)
            if Self.looksLikeNewSessionIntent(trimmed) || command != nil {
                let actionRows = makeNewSessionActionRows(for: trimmed, command: command)
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
        // Ghost suggestion is now computed locally in JS — no round-trip needed
    }

    private func makeNewSessionActionRows(for query: String, command: NewSessionCommand?) -> [SearchResult] {
        let homePath = FileManager.default.homeDirectoryForCurrentUser.path
        let recentProject = (try? sessionIndex?.mostRecentProject()) ?? nil
        let project = recentProject?.project.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let projectName = recentProject?.projectName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolvedProject = project.isEmpty ? homePath : project
        let resolvedProjectName = projectName.isEmpty ? "~" : projectName
        let now = Date()

        let claudeRow = SearchResult(
            sessionId: "new-claude", tool: "claude", title: "New Claude session",
            project: resolvedProject, projectName: resolvedProjectName, gitBranch: "",
            status: "action", startedAt: now, pid: nil, tokenCount: 0,
            lastActivityAt: now, activityPreview: nil, activityStatus: .closed, snippet: nil
        )
        let codexRow = SearchResult(
            sessionId: "new-codex", tool: "codex", title: "New Codex session",
            project: resolvedProject, projectName: resolvedProjectName, gitBranch: "",
            status: "action", startedAt: now, pid: nil, tokenCount: 0,
            lastActivityAt: now, activityPreview: nil, activityStatus: .closed, snippet: nil
        )

        if let command {
            return command.tool == "codex" ? [codexRow, claudeRow] : [claudeRow, codexRow]
        }
        if Self.matchesCodexLaunchIntent(query) {
            return [codexRow, claudeRow]
        }
        if Self.matchesClaudeLaunchIntent(query) {
            return [claudeRow, codexRow]
        }

        return [
            claudeRow,
            codexRow,
        ]
    }

    private static let codexFlags: Set<String> = ["--yolo", "--help"]
    private static let claudeFlags: Set<String> = ["--help"]
    private static let codexAliases: Set<String> = ["codex", "code", "cod", "co"]
    private static let claudeAliases: Set<String> = ["claude", "clau", "cl", "cla"]

    static func looksLikeNewSessionIntent(_ query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }

        if matchesCodexLaunchIntent(normalized) || matchesClaudeLaunchIntent(normalized) {
            return true
        }
        if normalized == "new" || normalized.hasPrefix("new ") {
            return true
        }

        let tokens = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return false }
        if tokens[0] == "new" && tokens.count == 1 {
            return true
        }
        if tokens[0] == "new", tokens.count >= 2 {
            return matchesCodexLaunchIntent(tokens[1]) || matchesClaudeLaunchIntent(tokens[1])
        }
        return false
    }

    static func matchesCodexLaunchIntent(_ query: String) -> Bool {
        matchesLaunchIntentToken(in: query, aliases: codexAliases)
    }

    static func matchesClaudeLaunchIntent(_ query: String) -> Bool {
        matchesLaunchIntentToken(in: query, aliases: claudeAliases)
    }

    static func parseNewSessionCommand(from query: String) -> NewSessionCommand? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let tokens = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }

        let lowerTokens = tokens.map { $0.lowercased() }
        var tool: String?
        var nextIndex = 0

        if lowerTokens[0] == "new" {
            if lowerTokens.count > 1, matchesCodexLaunchIntent(lowerTokens[1]) {
                tool = "codex"
                nextIndex = 2
            } else if lowerTokens.count > 1, matchesClaudeLaunchIntent(lowerTokens[1]) {
                tool = "claude"
                nextIndex = 2
            } else {
                return nil
            }
        } else if matchesCodexLaunchIntent(lowerTokens[0]) {
            tool = "codex"
            nextIndex = 1
        } else if matchesClaudeLaunchIntent(lowerTokens[0]) {
            tool = "claude"
            nextIndex = 1
        } else {
            return nil
        }

        let resolvedTool = tool ?? "claude"
        let allowedFlags = resolvedTool == "codex" ? codexFlags : claudeFlags

        var flags: [String] = []
        var promptTokens: [String] = []
        var index = nextIndex

        while index < tokens.count {
            let lowered = lowerTokens[index]
            if promptTokens.isEmpty, lowered.hasPrefix("-"), allowedFlags.contains(lowered) {
                flags.append(lowered)
                index += 1
                continue
            }

            promptTokens = Array(tokens[index...])
            break
        }

        return NewSessionCommand(
            tool: resolvedTool,
            flags: flags,
            prompt: promptTokens.joined(separator: " ")
        )
    }

    static func newSessionLaunchCommand(selectedTool: String, query: String) -> String {
        let defaultTool = selectedTool.lowercased() == "codex" ? "codex" : "claude"
        if let parsed = parseNewSessionCommand(from: query), parsed.tool == defaultTool {
            return commandString(from: parsed)
        }

        if defaultTool == "codex" {
            return commandString(from: NewSessionCommand(tool: "codex", flags: [], prompt: query))
        }
        return commandString(from: NewSessionCommand(tool: "claude", flags: [], prompt: query))
    }

    private static func matchesLaunchIntentToken(in query: String, aliases: Set<String>) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        let tokens = normalized.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return false }

        let token: String
        if tokens[0] == "new", tokens.count >= 2 {
            token = tokens[1]
        } else {
            token = tokens[0]
        }

        guard token.count >= 2 else { return false }
        if aliases.contains(token) { return true }
        for alias in aliases where alias.hasPrefix(token) {
            return true
        }
        return false
    }

    private static func commandString(from command: NewSessionCommand) -> String {
        var parts = [command.tool]
        parts.append(contentsOf: command.flags)
        if !command.prompt.isEmpty {
            parts.append(shellSingleQuote(command.prompt))
        }
        return parts.joined(separator: " ")
    }

    private static func shellSingleQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }

    private static func normalizedLaunchDirectory(from project: String) -> String {
        let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        return trimmed
    }

    nonisolated static func mergePreviewState(
        transcriptPreview: PreviewData,
        with result: SearchResult?
    ) -> PreviewData {
        guard let result else {
            return transcriptPreview
        }

        if result.healthStatus.lowercased() == "error" {
            let detail = cleanedPreviewDetail(result.healthDetail) ?? transcriptPreview.detail
            return PreviewData(
                state: .error,
                detail: detail,
                exchanges: transcriptPreview.exchanges,
                files: transcriptPreview.files
            )
        }

        if result.activityStatus == .working {
            let detail = cleanedPreviewDetail(result.activityPreview?.text) ?? transcriptPreview.detail
            return PreviewData(
                state: .working,
                detail: detail,
                exchanges: transcriptPreview.exchanges,
                files: transcriptPreview.files
            )
        }

        if result.activityStatus == .waiting {
            let detail = cleanedPreviewDetail(result.activityPreview?.text) ?? transcriptPreview.detail
            let state: PreviewState = detail?.contains("?") == true ? .question : .waiting
            return PreviewData(
                state: state,
                detail: detail,
                exchanges: transcriptPreview.exchanges,
                files: transcriptPreview.files
            )
        }

        return transcriptPreview
    }

    nonisolated private static func cleanedPreviewDetail(_ rawText: String?) -> String? {
        guard var cleaned = rawText?.trimmingCharacters(in: .whitespacesAndNewlines), !cleaned.isEmpty else {
            return nil
        }

        while let firstScalar = cleaned.unicodeScalars.first,
              leadingPreviewSymbols.contains(firstScalar) {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return cleaned.isEmpty ? nil : cleaned
    }

    nonisolated private static let leadingPreviewSymbols = CharacterSet(charactersIn: "▶▸▹✎•●◦▪▫")

    private func pushTheme() {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let theme = isDark ? "dark" : "light"
        pendingTheme = theme

        guard isWebViewReady else { return }
        pushThemeIfNeeded()
    }

    private func pushMode() {
        guard isWebViewReady else { return }
        let mode = isLiveOnlyMode ? "live" : "all"
        webView.evaluateJavaScript("setMode('\(mode)')", completionHandler: nil)
    }

    private func pushThemeIfNeeded() {
        guard let theme = pendingTheme else { return }
        pendingTheme = nil
        webView.evaluateJavaScript("setTheme('\(theme)')", completionHandler: nil)
    }

    private func requestResetAndFocus() {
        // resetAndFocus() clears JS-side rows, so force the next push even if JSON is identical.
        lastPushedResultsJSON = ""
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

        // Intercept nav keys at NSPanel level → call JS directly
        // This bypasses WKWebView's IPC event pipeline for snappier navigation
        panel.keyHandler = { [weak self] keyCode, modifiers in
            guard let self, self.isWebViewReady else { return false }
            switch keyCode {
            case 125: // Arrow Down
                self.webView.evaluateJavaScript("moveSelection(1)", completionHandler: nil)
                return true
            case 126: // Arrow Up
                self.webView.evaluateJavaScript("moveSelection(-1)", completionHandler: nil)
                return true
            case 53: // Escape
                self.hide()
                return true
            case 36: // Enter
                self.webView.evaluateJavaScript("activateSelected()", completionHandler: nil)
                return true
            case 48: // Tab
                self.webView.evaluateJavaScript("handleTab()", completionHandler: nil)
                return true
            default:
                return false
            }
        }
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
        if let htmlURL = Bundle.module.url(forResource: "panel", withExtension: "html", subdirectory: "Web")
            ?? Bundle.module.url(forResource: "panel", withExtension: "html") {
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

        // Watch for appearance changes to push theme live
        appearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
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

    /// Intercept arrow/escape/enter/tab at the native level and forward
    /// directly to JS via evaluateJavaScript, bypassing WKWebView's IPC
    /// event pipeline for lower-latency navigation.
    var keyHandler: ((UInt16, NSEvent.ModifierFlags) -> Bool)?

    override func keyDown(with event: NSEvent) {
        if let handler = keyHandler, handler(event.keyCode, event.modifierFlags) {
            return // consumed
        }
        super.keyDown(with: event)
    }
}
