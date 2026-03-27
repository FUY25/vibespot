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
        }

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
        searchPanelController?.toggle()
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

        statusItem?.button?.title = makeStatusItemTitle(count: count)
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
        if result.status == "action" {
            let command = result.sessionId == "new-codex" ? "codex" : "claude"
            launch(command, result.project)
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
        launch(command, result.project)
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
