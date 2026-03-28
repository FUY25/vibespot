import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private struct RuntimeBehavior {
        let startsRuntimeServices: Bool

        static let automatic = RuntimeBehavior(
            startsRuntimeServices: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        )
    }

    private let runtimeBehavior: RuntimeBehavior
    private var statusItem: NSStatusItem?
    private var sessionIndex: SessionIndex?
    private var hotkeyManager: HotkeyManager?
    private var searchPanelController: SearchPanelController?
    private var indexer: Indexer?
    private var sessionCountTimer: Timer?

    override init() {
        self.runtimeBehavior = .automatic
        super.init()
    }

    init(startsRuntimeServices: Bool) {
        self.runtimeBehavior = RuntimeBehavior(startsRuntimeServices: startsRuntimeServices)
        super.init()
    }

    var statusItemTitle: String? {
        statusItem?.button?.title
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.title = makeStatusItemTitle(count: 0)
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItem?.menu = nil

        guard runtimeBehavior.startsRuntimeServices else {
            return
        }

        do {
            let sessionIndex = try makeSessionIndex()
            let panelController = SearchPanelController()
            panelController.sessionIndex = sessionIndex
            panelController.onSelect = { result in
                Self.routeSelection(result)
            }

            let hotkeyManager = HotkeyManager { [weak self] in
                self?.togglePanel(nil)
            }
            let indexer = Indexer(sessionIndex: sessionIndex)

            self.sessionIndex = sessionIndex
            self.searchPanelController = panelController
            self.hotkeyManager = hotkeyManager
            self.indexer = indexer

            refreshStatusItemTitle()
            startSessionCountUpdates()
            hotkeyManager.register()
            indexer.start()
        } catch {
            print("AppDelegate failed to initialize runtime services: \(error)")
            refreshStatusItemTitle()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanupRuntimeServices()
    }

    @objc
    private func togglePanel(_ sender: Any?) {
        if let event = NSApp.currentEvent, event.type == .rightMouseUp {
            showContextMenu()
            return
        }
        searchPanelController?.toggle()
    }

    private func showContextMenu() {
        let menu = NSMenu()

        let lightItem = NSMenuItem(title: "Light", action: #selector(switchToLight), keyEquivalent: "")
        lightItem.target = self
        let darkItem = NSMenuItem(title: "Dark", action: #selector(switchToDark), keyEquivalent: "")
        darkItem.target = self
        let autoItem = NSMenuItem(title: "Auto", action: #selector(switchToAuto), keyEquivalent: "")
        autoItem.target = self

        let current = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua])
        if NSApp.appearance == nil {
            autoItem.state = .on
        } else if current == .darkAqua {
            darkItem.state = .on
        } else {
            lightItem.state = .on
        }

        menu.addItem(NSMenuItem(title: "Appearance", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(lightItem)
        menu.addItem(darkItem)
        menu.addItem(autoItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit VibeLight", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    @objc private func switchToLight() {
        NSApp.appearance = NSAppearance(named: .aqua)
    }

    @objc private func switchToDark() {
        NSApp.appearance = NSAppearance(named: .darkAqua)
    }

    @objc private func switchToAuto() {
        NSApp.appearance = nil
    }

    func removeStatusItem() {
        cleanupRuntimeServices()

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func cleanupRuntimeServices() {
        sessionCountTimer?.invalidate()
        sessionCountTimer = nil

        hotkeyManager?.unregister()
        hotkeyManager = nil

        indexer?.stop()
        indexer = nil

        searchPanelController?.hide()
        searchPanelController = nil
        sessionIndex = nil
    }

    private func startSessionCountUpdates() {
        sessionCountTimer?.invalidate()
        sessionCountTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshStatusItemTitle()
            }
        }
    }

    private func refreshStatusItemTitle() {
        let count: Int

        if let sessionIndex {
            count = (try? sessionIndex.liveSessionCount()) ?? 0
        } else {
            count = 0
        }

        let newTitle = makeStatusItemTitle(count: count)
        guard statusItem?.button?.title != newTitle else { return }
        statusItem?.button?.title = newTitle
    }

    private func makeStatusItemTitle(count: Int) -> String {
        "VL: \(count)"
    }

    static func routeSelection(
        _ result: SearchResult,
        launch: (String, String) -> Void = { command, directory in
            TerminalLauncher.launch(command: command, directory: directory)
        },
        jump: (SearchResult) -> Void = { result in
            WindowJumper.jumpToSession(result)
        }
    ) {
        let launchDirectory = normalizedLaunchDirectory(from: result.project)

        if result.status == "action" {
            let isCodexAction = result.tool == "codex" || result.sessionId == "new-codex"
            let command = isCodexAction ? "codex" : "claude"
            launch(command, launchDirectory)
            return
        }

        if result.status == "live" {
            jump(result)
            return
        }

        let command: String
        if result.tool == "codex" {
            command = "codex resume \(result.sessionId)"
        } else {
            command = "claude --resume \(result.sessionId)"
        }
        launch(command, launchDirectory)
    }

    private static func normalizedLaunchDirectory(from project: String) -> String {
        let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        return trimmed
    }

    private func makeSessionIndex() throws -> SessionIndex {
        let fileManager = FileManager.default
        let applicationSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let vibeLightSupportURL = applicationSupportURL.appendingPathComponent("VibeLight", isDirectory: true)
        try fileManager.createDirectory(
            at: vibeLightSupportURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        let dbURL = vibeLightSupportURL.appendingPathComponent("index.sqlite3", isDirectory: false)
        return try SessionIndex(dbPath: dbURL.path)
    }
}
