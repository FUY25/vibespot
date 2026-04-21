import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    typealias SourceSwitchHandler = @Sendable (
        SessionSourceResolution,
        @escaping @MainActor (SessionIndex) -> Void
    ) async throws -> Void
    typealias SessionIndexFactory = @MainActor () throws -> SessionIndex
    typealias FailurePresenter = @MainActor (String, String) -> Void

    private struct RuntimeBehavior {
        let startsRuntimeServices: Bool

        static let automatic = RuntimeBehavior(
            startsRuntimeServices: ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        )
    }

    private let runtimeBehavior: RuntimeBehavior
    private let settingsStore: SettingsStore
    private let launchAtLoginManager: any LaunchAtLoginManaging
    private let sourceSwitchHandler: SourceSwitchHandler
    private let sessionIndexFactoryOverride: SessionIndexFactory?
    private let failurePresenter: FailurePresenter
    private var settings: AppSettings
    private var statusItem: NSStatusItem?
    private var sessionIndex: SessionIndex?
    private var hotkeyManager: HotkeyManager?
    private var preferencesWindowController: PreferencesWindowController?
    private var searchPanelController: SearchPanelController?
    private var onboardingWindowController: OnboardingWindowController?
    private var indexer: Indexer?
    private var sessionCountTimer: Timer?
    private var sourceSwitchTask: Task<Void, Never>?
    private var recoveryReindexTask: Task<Void, Never>?
    private var sourceSwitchGeneration = 0
    private var runtimeServicesStarted = false
    private let sessionSourceLocator = SessionSourceLocator()
    private let sessionFileLocator = SessionFileLocator()
    private var sessionSourceResolution: SessionSourceResolution

    override init() {
        self.runtimeBehavior = .automatic
        self.settingsStore = SettingsStore()
        self.launchAtLoginManager = LaunchAtLoginManager()
        self.sourceSwitchHandler = Self.defaultSourceSwitchHandler
        self.sessionIndexFactoryOverride = nil
        self.failurePresenter = Self.defaultFailurePresenter
        self.settings = settingsStore.load()
        self.sessionSourceResolution = SessionSourceLocator().resolve(for: self.settings)
        super.init()
    }

    init(
        startsRuntimeServices: Bool,
        settingsStore: SettingsStore = SettingsStore(),
        launchAtLoginManager: any LaunchAtLoginManaging = LaunchAtLoginManager(),
        sourceSwitchHandler: @escaping SourceSwitchHandler = AppDelegate.defaultSourceSwitchHandler,
        sessionIndexFactory: SessionIndexFactory? = nil,
        failurePresenter: @escaping FailurePresenter = AppDelegate.defaultFailurePresenter
    ) {
        self.runtimeBehavior = RuntimeBehavior(startsRuntimeServices: startsRuntimeServices)
        self.settingsStore = settingsStore
        self.launchAtLoginManager = launchAtLoginManager
        self.sourceSwitchHandler = sourceSwitchHandler
        self.sessionIndexFactoryOverride = sessionIndexFactory
        self.failurePresenter = failurePresenter
        self.settings = settingsStore.load()
        self.sessionSourceResolution = SessionSourceLocator().resolve(for: self.settings)
        super.init()
    }

    var statusItemTitle: String? {
        guard let title = statusItem?.button?.title, !title.isEmpty else { return nil }
        return title
    }

    var statusItemImage: NSImage? {
        statusItem?.button?.image
    }

    var statusItemToolTipForTesting: String? {
        statusItem?.button?.toolTip
    }

    var isOnboardingVisible: Bool {
        onboardingWindowController?.window?.isVisible == true
    }

    var isPreferencesVisible: Bool {
        preferencesWindowController?.window?.isVisible == true
    }

    var preferencesWindowForTesting: NSWindow? {
        preferencesWindowController?.window
    }

    #if DEBUG
    var preferencesStatusMessageForTesting: String? {
        preferencesWindowController?.currentStatusMessageForTesting
    }

    var runtimeServicesStartedForTesting: Bool {
        runtimeServicesStarted
    }

    var hasIndexerForTesting: Bool {
        indexer != nil
    }
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = VibeSpotBranding.makeApplicationIcon()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = MenuBarLogo.makeImage()
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyUpOrDown
            button.title = ""
            button.toolTip = makeStatusItemToolTip(count: 0)
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        statusItem?.menu = nil
        applyAppearance(for: settings.theme)
        syncLaunchAtLogin()

        guard settings.onboardingCompleted else {
            presentOnboarding()
            return
        }

        startRuntimeServicesIfNeeded()
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
        let menu = makeContextMenu()
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        statusItem?.menu = nil
    }

    func makeContextMenuForTesting() -> NSMenu {
        makeContextMenu()
    }

    @objc func openPreferences() {
        if preferencesWindowController == nil {
            preferencesWindowController = PreferencesWindowController(
                settingsStore: settingsStore,
                launchAtLoginSupported: launchAtLoginManager.isSupportedRuntime,
                onApplySettings: { [weak self] settings in
                    self?.applySettings(settings)
                },
                onReindex: { [weak self] in
                    self?.performReindex() ?? "Could not start reindex."
                },
                onExportDiagnostics: { [weak self] in
                    self?.performDiagnosticsExport()
                }
            )
        }

        preferencesWindowController?.showPreferences()
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()

        let preferencesItem = NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesItem.target = self
        let exportItem = NSMenuItem(title: "Export Diagnostics…", action: #selector(exportDiagnostics), keyEquivalent: "")
        exportItem.target = self
        let lightItem = NSMenuItem(title: "Light", action: #selector(switchToLight), keyEquivalent: "")
        lightItem.target = self
        let darkItem = NSMenuItem(title: "Dark", action: #selector(switchToDark), keyEquivalent: "")
        darkItem.target = self
        let autoItem = NSMenuItem(title: "Auto", action: #selector(switchToAuto), keyEquivalent: "")
        autoItem.target = self

        switch settings.theme {
        case .system:
            autoItem.state = .on
        case .light:
            lightItem.state = .on
        case .dark:
            darkItem.state = .on
        }

        menu.addItem(preferencesItem)
        menu.addItem(exportItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Appearance", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(lightItem)
        menu.addItem(darkItem)
        menu.addItem(autoItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: VibeSpotBranding.quitMenuTitle(), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    func removeStatusItem() {
        cleanupRuntimeServices()

        if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }

    private func cleanupRuntimeServices() {
        sourceSwitchTask?.cancel()
        sourceSwitchTask = nil
        recoveryReindexTask?.cancel()
        recoveryReindexTask = nil
        sessionCountTimer?.invalidate()
        sessionCountTimer = nil

        hotkeyManager?.unregister()
        hotkeyManager = nil

        indexer?.stop()
        indexer = nil
        sessionFileLocator.reset()

        searchPanelController?.hide()
        searchPanelController = nil
        onboardingWindowController?.close()
        onboardingWindowController = nil
        preferencesWindowController?.close()
        preferencesWindowController = nil
        sessionIndex = nil
        runtimeServicesStarted = false
    }

    @discardableResult
    private func syncLaunchAtLogin() -> String? {
        do {
            try launchAtLoginManager.setEnabled(settings.launchAtLogin)
            return nil
        } catch {
            RuntimeIssueStore.shared.record(component: "LaunchAtLogin", error: error)
            print("AppDelegate failed to update launch-at-login state: \(error)")
            return makeUserVisibleErrorMessage(action: "update launch at login", error: error)
        }
    }

    private func applyAppearance(for theme: AppTheme) {
        switch theme {
        case .system:
            NSApp.appearance = nil
        case .light:
            NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:
            NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }

    @discardableResult
    private func performReindex() -> String {
        if let indexer {
            indexer.performFullScan()
            refreshStatusItemTitle()
            return "Reindex started"
        }

        guard runtimeBehavior.startsRuntimeServices else {
            return "Reindex is unavailable while runtime services are disabled."
        }

        guard recoveryReindexTask == nil else {
            return "Reindex already in progress"
        }

        let targetResolution = sessionSourceResolution
        recoveryReindexTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try await self?.sourceSwitchHandler(targetResolution) { readyIndex in
                    guard let self else { return }
                    self.installRuntimeServices(using: readyIndex)
                    self.preferencesWindowController?.presentStatus("Reindex finished")
                }
            } catch is CancellationError {
                return
            } catch {
                RuntimeIssueStore.shared.record(component: "Reindex", error: error)
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.preferencesWindowController?.presentStatus(
                        self.makeUserVisibleErrorMessage(action: "reindex sessions", error: error),
                        isError: true
                    )
                }
                print("AppDelegate failed to recover via reindex: \(error)")
            }

            await MainActor.run { [weak self] in
                self?.recoveryReindexTask = nil
            }
        }

        return "Reindex started"
    }

    @objc private func exportDiagnostics() {
        if let errorMessage = performDiagnosticsExport() {
            preferencesWindowController?.presentStatus(errorMessage, isError: true)
        }
    }

    private func performDiagnosticsExport() -> String? {
        do {
            let exporter = DiagnosticsExporter()
            let outputURL = try exporter.export(settings: settings)
            NSWorkspace.shared.activateFileViewerSelecting([outputURL])
            return nil
        } catch {
            RuntimeIssueStore.shared.record(component: "DiagnosticsExport", error: error)
            print("AppDelegate failed to export diagnostics: \(error)")
            return makeUserVisibleErrorMessage(action: "export diagnostics", error: error)
        }
    }

    @discardableResult
    private func applySettings(_ newSettings: AppSettings) -> String? {
        let previousSettings = settings
        let previousSourceResolution = sessionSourceResolution
        let newSourceResolution = sessionSourceLocator.resolve(for: newSettings)
        let changeSet = AppSettingsChangeSet(
            oldSettings: previousSettings,
            newSettings: newSettings,
            oldSessionSourceResolution: previousSourceResolution,
            newSessionSourceResolution: newSourceResolution
        )

        let shouldDeferSourceCommit = changeSet.sourceFingerprintChanged && runtimeServicesStarted
        if shouldDeferSourceCommit {
            var committedSettings = newSettings
            committedSettings.sessionSourceConfiguration = previousSettings.sessionSourceConfiguration
            settings = committedSettings
            sessionSourceResolution = previousSourceResolution
        } else {
            settings = newSettings
            sessionSourceResolution = newSourceResolution
        }

        if changeSet.themeChanged {
            applyAppearance(for: newSettings.theme)
        }
        if changeSet.historyModeChanged {
            searchPanelController?.applySettings(newSettings)
        }
        preferencesWindowController?.syncSettings(newSettings)

        if changeSet.sourceFingerprintChanged {
            if shouldDeferSourceCommit {
                reconfigureIndexerForSessionSourceChange(
                    targetSettings: newSettings,
                    targetResolution: newSourceResolution
                )
            } else {
                searchPanelController?.applySessionSourceResolution(newSourceResolution)
            }
        }

        if changeSet.launchAtLoginChanged {
            if let errorMessage = syncLaunchAtLogin() {
                return errorMessage
            }
        }
        if changeSet.hotkeyChanged {
            rebuildHotkeyManagerIfNeeded()
        }

        return nil
    }

    private func applyHistoryMode(_ historyMode: SearchHistoryMode) {
        guard settings.historyMode != historyMode else { return }

        settings.historyMode = historyMode
        settingsStore.save(settings)
        searchPanelController?.applySettings(settings)
        preferencesWindowController?.syncSettings(settings)
    }

    private func reconfigureIndexerForSessionSourceChange(
        targetSettings: AppSettings,
        targetResolution: SessionSourceResolution
    ) {
        guard runtimeServicesStarted else { return }

        sourceSwitchTask?.cancel()
        sourceSwitchGeneration += 1
        let generation = sourceSwitchGeneration

        sourceSwitchTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try await self?.sourceSwitchHandler(targetResolution) { readyIndex in
                    guard let self else { return }
                    guard self.runtimeServicesStarted else { return }
                    guard generation == self.sourceSwitchGeneration else { return }

                    self.indexer?.stop()
                    self.sessionFileLocator.reset()

                    let rebuiltIndexer = Indexer(
                        sessionIndex: readyIndex,
                        sourceResolution: targetResolution,
                        sessionFileLocator: self.sessionFileLocator
                    )
                    self.settings = targetSettings
                    self.sessionSourceResolution = targetResolution
                    self.settingsStore.save(self.settings)
                    self.sessionIndex = readyIndex
                    self.searchPanelController?.sessionIndex = readyIndex
                    self.searchPanelController?.applySessionSourceResolution(targetResolution)
                    self.indexer = rebuiltIndexer

                    rebuiltIndexer.start()
                    self.refreshStatusItemTitle()
                }
            } catch is CancellationError {
                return
            } catch {
                RuntimeIssueStore.shared.record(component: "SourceSwitch", error: error)
                await MainActor.run { [weak self] in
                    guard let self, generation == self.sourceSwitchGeneration else { return }
                    self.settingsStore.save(self.settings)
                    self.preferencesWindowController?.syncSettings(self.settings)
                    self.preferencesWindowController?.presentStatus(
                        self.makeUserVisibleErrorMessage(action: "switch session sources", error: error),
                        isError: true
                    )
                }
                print("AppDelegate failed to switch session sources: \(error)")
            }

            await MainActor.run { [weak self] in
                guard let self, generation == self.sourceSwitchGeneration else { return }
                self.sourceSwitchTask = nil
            }
        }
    }

    private func rebuildHotkeyManagerIfNeeded() {
        guard runtimeServicesStarted else { return }

        hotkeyManager?.unregister()
        hotkeyManager = nil

        let hotkeyManager = HotkeyManager(binding: settings.hotkeyBinding) { [weak self] in
            self?.togglePanel(nil)
        }
        self.hotkeyManager = hotkeyManager
        hotkeyManager.register()
    }

    private func installRuntimeServices(using sessionIndex: SessionIndex) {
        sessionCountTimer?.invalidate()
        sessionCountTimer = nil
        hotkeyManager?.unregister()
        hotkeyManager = nil
        indexer?.stop()
        indexer = nil
        searchPanelController?.hide()
        searchPanelController = nil

        sessionFileLocator.reset()
        let panelController = SearchPanelController(
            sessionSourceResolution: sessionSourceResolution,
            sessionFileLocator: sessionFileLocator
        )
        panelController.applySettings(settings)
        panelController.sessionIndex = sessionIndex
        panelController.onSelect = { [weak self] result in
            self?.handleSelection(result)
        }
        panelController.onLaunchAction = { [weak self] command, directory in
            self?.launchSessionAction(command: command, directory: directory)
        }
        panelController.onSearchFailure = { [weak self] message in
            self?.presentFailure(title: "Index Unavailable", message: message)
        }
        panelController.onHistoryModeChanged = { [weak self] historyMode in
            guard let self else { return }
            self.applyHistoryMode(historyMode)
        }
        panelController.onOpenPreferences = { [weak self] in
            self?.openPreferences()
        }

        let hotkeyManager = HotkeyManager(binding: settings.hotkeyBinding) { [weak self] in
            self?.togglePanel(nil)
        }
        let indexer = Indexer(
            sessionIndex: sessionIndex,
            sourceResolution: sessionSourceResolution,
            sessionFileLocator: sessionFileLocator
        )

        self.sessionIndex = sessionIndex
        self.searchPanelController = panelController
        self.hotkeyManager = hotkeyManager
        self.indexer = indexer

        refreshStatusItemTitle()
        startSessionCountUpdates()
        hotkeyManager.register()
        indexer.start()
        runtimeServicesStarted = true
    }

    @objc private func switchToLight() {
        applySettings(AppSettings(
            hotkeyKeyCode: settings.hotkeyKeyCode,
            hotkeyModifiers: settings.hotkeyModifiers,
            theme: .light,
            historyMode: settings.historyMode,
            launchAtLogin: settings.launchAtLogin,
            onboardingCompleted: settings.onboardingCompleted,
            sessionSourceConfiguration: settings.sessionSourceConfiguration
        ))
        settingsStore.save(settings)
    }

    @objc private func switchToDark() {
        applySettings(AppSettings(
            hotkeyKeyCode: settings.hotkeyKeyCode,
            hotkeyModifiers: settings.hotkeyModifiers,
            theme: .dark,
            historyMode: settings.historyMode,
            launchAtLogin: settings.launchAtLogin,
            onboardingCompleted: settings.onboardingCompleted,
            sessionSourceConfiguration: settings.sessionSourceConfiguration
        ))
        settingsStore.save(settings)
    }

    @objc private func switchToAuto() {
        applySettings(AppSettings(
            hotkeyKeyCode: settings.hotkeyKeyCode,
            hotkeyModifiers: settings.hotkeyModifiers,
            theme: .system,
            historyMode: settings.historyMode,
            launchAtLogin: settings.launchAtLogin,
            onboardingCompleted: settings.onboardingCompleted,
            sessionSourceConfiguration: settings.sessionSourceConfiguration
        ))
        settingsStore.save(settings)
    }

    private func presentOnboarding() {
        guard onboardingWindowController == nil else {
            onboardingWindowController?.showOnboarding()
            return
        }

        let controller = OnboardingWindowController(
            settingsStore: settingsStore,
            launchAtLoginSupported: launchAtLoginManager.isSupportedRuntime
        ) { [weak self] in
            guard let self else { return }
            self.settings = self.settingsStore.load()
            self.applyAppearance(for: self.settings.theme)
            self.syncLaunchAtLogin()
            self.onboardingWindowController?.close()
            self.onboardingWindowController = nil
            self.startRuntimeServicesIfNeeded()
        }
        onboardingWindowController = controller
        controller.showOnboarding()
    }

    private func startRuntimeServicesIfNeeded() {
        guard runtimeBehavior.startsRuntimeServices, !runtimeServicesStarted else {
            return
        }

        do {
            let sessionIndex = try makeSessionIndex()
            installRuntimeServices(using: sessionIndex)
        } catch {
            RuntimeIssueStore.shared.record(component: "RuntimeServices", error: error)
            print("AppDelegate failed to initialize runtime services: \(error)")
            presentFailure(title: "Index Unavailable", message: makeIndexRecoveryMessage(error))
            refreshStatusItemTitle()
        }
    }

    var configuredHotkeyBinding: HotkeyBinding {
        settings.hotkeyBinding
    }

    var currentSessionSourceFingerprintForTesting: String {
        sessionSourceResolution.effectiveFingerprint
    }

    func applySettingsForTesting(_ newSettings: AppSettings) {
        _ = applySettings(newSettings)
    }

    func applyHistoryModeForTesting(_ historyMode: SearchHistoryMode) {
        applyHistoryMode(historyMode)
    }

    func setRuntimeServicesStartedForTesting(_ started: Bool) {
        runtimeServicesStarted = started
    }

    func waitForSourceSwitchForTesting() async {
        await sourceSwitchTask?.value
    }

    func performReindexForTesting() -> String {
        performReindex()
    }

    func waitForRecoveryReindexForTesting() async {
        await recoveryReindexTask?.value
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

        let newToolTip = makeStatusItemToolTip(count: count)
        guard statusItem?.button?.toolTip != newToolTip else { return }
        statusItem?.button?.toolTip = newToolTip
    }

    private func makeStatusItemToolTip(count: Int) -> String {
        VibeSpotBranding.liveSessionsToolTip(count: count)
    }

    static func routeSelection(
        _ result: SearchResult,
        launch: (String, String, @escaping @MainActor (String?) -> Void) -> Void = { command, directory, completion in
            TerminalLauncher.launch(command: command, directory: directory, completion: completion)
        },
        jump: (SearchResult, @escaping @MainActor (String?) -> Void) -> Void = { result, completion in
            WindowJumper.jumpToSession(result, completion: completion)
        }
        ,
        onFailure: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        let launchDirectory = normalizedLaunchDirectory(from: result.project)

        if result.status == "action" {
            let isCodexAction = result.tool == "codex" || result.sessionId == "new-codex"
            let command = isCodexAction ? "codex" : "claude"
            launch(command, launchDirectory) { failureMessage in
                guard let failureMessage else { return }
                onFailure("Could not start a new session: \(failureMessage)")
            }
            return
        }

        if result.status == "live" {
            jump(result) { failureMessage in
                guard let failureMessage else { return }
                onFailure("Could not return to the live session: \(failureMessage)")
            }
            return
        }

        let command: String
        if result.tool == "codex" {
            command = "codex resume \(result.sessionId)"
        } else {
            command = "claude --resume \(result.sessionId)"
        }
        launch(command, launchDirectory) { failureMessage in
            guard let failureMessage else { return }
            onFailure("Could not resume this session: \(failureMessage)")
        }
    }

    private static func normalizedLaunchDirectory(from project: String) -> String {
        let trimmed = project.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return FileManager.default.homeDirectoryForCurrentUser.path
        }
        return trimmed
    }

    private func makeSessionIndex() throws -> SessionIndex {
        if let sessionIndexFactoryOverride {
            return try sessionIndexFactoryOverride()
        }
        let dbURL = try Self.makeSessionIndexWorkspace()
            .activeDatabaseURL(for: sessionSourceResolution.effectiveFingerprint)
        return try SessionIndex(dbPath: dbURL.path)
    }

    nonisolated private static func defaultSourceSwitchHandler(
        targetResolution: SessionSourceResolution,
        onReady: @escaping @MainActor (SessionIndex) -> Void
    ) async throws {
        let coordinator = try SourceSwitchCoordinator(workspace: makeSessionIndexWorkspace())
        try await coordinator.switchToSource(targetResolution, onReady: onReady)
    }

    nonisolated private static func makeSessionIndexWorkspace() throws -> SessionIndexWorkspace {
        let fileManager = FileManager.default
        let runtimePaths = AppRuntimePaths(fileManager: fileManager)
        let indexesURL = try runtimePaths.indexesRootURL()
        let legacyDatabaseURL = try runtimePaths.legacyIndexDatabaseURL()
        return SessionIndexWorkspace(
            rootDirectoryURL: indexesURL,
            legacyDatabaseURL: legacyDatabaseURL,
            fileManager: fileManager
        )
    }

    private func handleSelection(_ result: SearchResult) {
        Self.routeSelection(result, onFailure: { [weak self] message in
            self?.presentActionFailure(message)
        })
    }

    private func launchSessionAction(command: String, directory: String) {
        TerminalLauncher.launch(command: command, directory: directory) { [weak self] failureMessage in
            guard let failureMessage else { return }
            self?.presentActionFailure("Could not start a new session: \(failureMessage)")
        }
    }

    private func presentActionFailure(_ message: String) {
        presentFailure(title: "Action Failed", message: message)
    }

    private func presentFailure(title: String, message: String) {
        failurePresenter(title, message)
    }

    private static func defaultFailurePresenter(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func makeIndexRecoveryMessage(_ error: Error) -> String {
        let detail = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.isEmpty {
            return "VibeSpot could not open the local index. Open Preferences and click Reindex sessions to rebuild it."
        }
        return "VibeSpot could not open the local index. Open Preferences and click Reindex sessions to rebuild it. Details: \(detail)"
    }

    private func makeUserVisibleErrorMessage(action: String, error: Error) -> String {
        let detail = (error as NSError).localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard detail.isEmpty == false else {
            return "Could not \(action)."
        }
        return "Could not \(action): \(detail)"
    }
}
