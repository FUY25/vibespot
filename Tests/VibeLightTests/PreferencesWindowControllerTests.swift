import AppKit
import Testing
@testable import Flare

@MainActor
@Suite("Preferences window")
struct PreferencesWindowControllerTests {
    @Test("source draft tracks whether source settings changed")
    func sourceDraftTracksWhetherSourceSettingsChanged() {
        var settings = AppSettings.default
        settings.sessionSourceConfiguration = SessionSourceConfiguration(
            claude: ToolSessionSourceConfiguration(mode: .automatic, customRoot: ""),
            codex: ToolSessionSourceConfiguration(mode: .custom, customRoot: "/tmp/codex-root")
        )

        var draft = PreferencesSourceDraft(settings: settings)
        #expect(draft.isDirty(comparedTo: settings) == false)

        draft.claude.mode = .custom
        draft.claude.customRoot = "/tmp/claude-root"
        #expect(draft.isDirty(comparedTo: settings))
    }

    @Test("shortcut sheet can be cancelled and closes cleanly")
    func shortcutSheetCanBeCancelledAndClosesCleanly() throws {
        let controller = makeController()
        controller.showPreferences()

        let window = try #require(controller.window)
        let changeButton = try #require(findButton(titled: "Change Shortcut", in: window.contentView))
        changeButton.performClick(nil)

        let sheet = try #require(window.attachedSheet)
        let cancelButton = try #require(findButton(titled: "Cancel", in: sheet.contentView))
        cancelButton.performClick(nil)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        #expect(window.attachedSheet == nil)
    }

    @Test("source edits stay local until apply is clicked")
    func sourceEditsStayLocalUntilApplyIsClicked() throws {
        let claudeRoot = try makeClaudeRoot()
        let codexRoot = try makeCodexRoot()
        let applyRecorder = ApplyRecorder()
        let controller = makeController(onApply: applyRecorder.record)
        controller.showPreferences()

        let window = try #require(controller.window)
        let applyButton = try #require(findButton(titled: "Apply", in: window.contentView))
        #expect(applyButton.isEnabled == false)

        controller.updateSourceDraftForTesting { draft in
            draft.claude.mode = .custom
            draft.claude.customRoot = claudeRoot
            draft.codex.mode = .custom
            draft.codex.customRoot = codexRoot
        }

        #expect(applyRecorder.appliedSettings.isEmpty)
        #expect(applyButton.isEnabled)

        let persistedBeforeApply = controller.settingsStoreForTesting.load()
        #expect(persistedBeforeApply.sessionSourceConfiguration == .default)

        applyButton.performClick(nil)

        #expect(applyRecorder.appliedSettings.count == 1)
        let appliedSettings = try #require(applyRecorder.appliedSettings.last)
        #expect(appliedSettings.sessionSourceConfiguration.claude.mode == .custom)
        #expect(appliedSettings.sessionSourceConfiguration.claude.customRoot == claudeRoot)
        #expect(appliedSettings.sessionSourceConfiguration.codex.mode == .custom)
        #expect(appliedSettings.sessionSourceConfiguration.codex.customRoot == codexRoot)
        #expect(controller.settingsStoreForTesting.load() == appliedSettings)
        #expect(applyButton.isEnabled == false)
    }

    @Test("shows invalid source warning when no fallback exists and current source stays active")
    func showsInvalidSourceWarningWhenNoFallbackExistsAndCurrentSourceStaysActive() throws {
        let claudeRoot = try makeClaudeRoot()
        let codexRoot = try makeCodexRoot()
        let applyRecorder = ApplyRecorder()
        let missingHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("preferences-home-\(UUID().uuidString)", isDirectory: true)
            .path

        var settings = AppSettings.default
        settings.sessionSourceConfiguration = SessionSourceConfiguration(
            claude: ToolSessionSourceConfiguration(mode: .custom, customRoot: claudeRoot),
            codex: ToolSessionSourceConfiguration(mode: .custom, customRoot: codexRoot)
        )

        let controller = makeController(
            initialSettings: settings,
            sessionSourceLocator: SessionSourceLocator(homeDirectoryPath: missingHome),
            onApply: applyRecorder.record
        )
        controller.showPreferences()

        let window = try #require(controller.window)
        controller.updateSourceDraftForTesting { draft in
            draft.claude.mode = .custom
            draft.claude.customRoot = "/tmp/missing-claude-\(UUID().uuidString)"
        }

        let warningLabel = try #require(findStaticText(containing: "stays active", in: window.contentView))
        #expect(warningLabel.stringValue.localizedCaseInsensitiveContains("apply"))
        #expect(applyRecorder.appliedSettings.isEmpty)
        #expect(controller.settingsStoreForTesting.load().sessionSourceConfiguration == settings.sessionSourceConfiguration)
    }

    @Test("applying invalid custom source with automatic fallback persists automatic state")
    func applyingInvalidCustomSourceWithAutomaticFallbackPersistsAutomaticState() throws {
        let applyRecorder = ApplyRecorder()
        let autoHome = try makeAutomaticHome()
        let controller = makeController(
            sessionSourceLocator: SessionSourceLocator(homeDirectoryPath: autoHome),
            onApply: applyRecorder.record
        )
        controller.showPreferences()

        let window = try #require(controller.window)
        let applyButton = try #require(findButton(titled: "Apply", in: window.contentView))

        controller.updateSourceDraftForTesting { draft in
            draft.claude.mode = .custom
            draft.claude.customRoot = "/tmp/missing-claude-\(UUID().uuidString)"
        }

        let fallbackLabel = try #require(findStaticText(containing: "fallback", in: window.contentView))
        #expect(fallbackLabel.stringValue.localizedCaseInsensitiveContains("automatic"))
        #expect(applyButton.isEnabled)

        applyButton.performClick(nil)

        let appliedSettings = try #require(applyRecorder.appliedSettings.last)
        #expect(appliedSettings.sessionSourceConfiguration.claude.mode == .automatic)
        #expect(appliedSettings.sessionSourceConfiguration.claude.customRoot.isEmpty)
        #expect(appliedSettings.sessionSourceConfiguration.codex == AppSettings.default.sessionSourceConfiguration.codex)

        let persistedSettings = controller.settingsStoreForTesting.load()
        #expect(persistedSettings.sessionSourceConfiguration == appliedSettings.sessionSourceConfiguration)

        let statusLabel = try #require(findStaticText(containing: "fallback", in: window.contentView))
        #expect(statusLabel.stringValue.localizedCaseInsensitiveContains("applied"))
    }

    @Test("single page preferences shows build info without sidebar tabs")
    func singlePagePreferencesShowsBuildInfoWithoutSidebarTabs() throws {
        let controller = makeController()
        controller.showPreferences()

        let window = try #require(controller.window)
        #expect(findStaticText(containing: "Version", in: window.contentView) != nil)
        #expect(findStaticText(containing: "Build", in: window.contentView) != nil)
        #expect(findButton(titled: "About", in: window.contentView) == nil)
        #expect(findButton(titled: "Settings", in: window.contentView) == nil)
    }

    private func makeController(
        initialSettings: AppSettings = .default,
        sessionSourceLocator: SessionSourceLocator = SessionSourceLocator(),
        onApply: @escaping @MainActor @Sendable (AppSettings) -> Void = { _ in }
    ) -> PreferencesWindowController {
        let suiteName = "PreferencesWindowControllerTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)
        let store = SettingsStore(defaults: suite)
        store.save(initialSettings)
        return PreferencesWindowController(
            settingsStore: store,
            launchAtLoginSupported: true,
            sessionSourceLocator: sessionSourceLocator,
            onApplySettings: onApply,
            onReindex: {},
            onExportDiagnostics: {}
        )
    }

    private func makeClaudeRoot() throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "preferences-claude-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sessions", isDirectory: true),
            withIntermediateDirectories: true
        )
        return root.path
    }

    private func makeCodexRoot() throws -> String {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "preferences-codex-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("sessions", isDirectory: true),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: root.appendingPathComponent("state_5.sqlite").path,
            contents: Data(),
            attributes: nil
        )
        return root.path
    }

    private func makeAutomaticHome() throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(
            "preferences-auto-home-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

        let claudeRoot = home.appendingPathComponent(".claude", isDirectory: true)
        try FileManager.default.createDirectory(at: claudeRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: claudeRoot.appendingPathComponent("projects", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: claudeRoot.appendingPathComponent("sessions", isDirectory: true),
            withIntermediateDirectories: true
        )

        let codexRoot = home.appendingPathComponent(".codex", isDirectory: true)
        try FileManager.default.createDirectory(at: codexRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: codexRoot.appendingPathComponent("sessions", isDirectory: true),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: codexRoot.appendingPathComponent("state_5.sqlite").path,
            contents: Data(),
            attributes: nil
        )

        return home.path
    }

    private func findButton(titled title: String, in view: NSView?) -> NSButton? {
        guard let view else { return nil }
        if let button = view as? NSButton, button.title == title {
            return button
        }

        for subview in view.subviews {
            if let button = findButton(titled: title, in: subview) {
                return button
            }
        }

        return nil
    }

    private func findStaticText(containing text: String, in view: NSView?) -> NSTextField? {
        guard let view else { return nil }
        if let label = view as? NSTextField, label.stringValue.localizedCaseInsensitiveContains(text) {
            return label
        }

        for subview in view.subviews {
            if let label = findStaticText(containing: text, in: subview) {
                return label
            }
        }

        return nil
    }
}

@MainActor
private final class ApplyRecorder {
    private(set) var appliedSettings: [AppSettings] = []

    func record(_ settings: AppSettings) {
        appliedSettings.append(settings)
    }
}
