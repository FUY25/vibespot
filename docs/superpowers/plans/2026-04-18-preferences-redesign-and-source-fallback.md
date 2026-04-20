# Preferences Redesign And Source Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a cleaner two-tab preferences window that fixes broken shortcut-sheet behavior, adds a search-history toggle, and supports Claude/Codex root-folder fallback overrides when auto-detection fails.

**Architecture:** Keep the window to `Settings` and `About`, but separate the work into three clear units: persisted settings, resolved session-source paths, and the AppKit preferences UI. Centralize source-path resolution so the indexer, search preview lookup, live-session registry, and Codex state database all read from the same derived paths instead of hardcoded `~/.claude` and `~/.codex` assumptions. Treat alignment as a feature requirement by driving the settings UI from shared layout metrics instead of one-off row sizing.

**Tech Stack:** Swift 6 / AppKit, Swift Testing (`@Test`), `UserDefaults`, `NSOpenPanel`, existing Flare indexing/runtime services.

---

## File Map

| File | What changes |
| --- | --- |
| `Sources/VibeLight/Settings/SessionSourceConfiguration.swift` | New per-tool source preference types (`auto` vs `custom`) and normalized custom-root helpers. |
| `Sources/VibeLight/Settings/SessionSourceLocator.swift` | New resolver for effective Claude/Codex paths and UI/runtime status reporting. |
| `Sources/VibeLight/Settings/AppSettings.swift` | Add Claude/Codex source preferences to persisted settings defaults and decoding. |
| `Sources/VibeLight/Settings/SettingsStore.swift` | No schema migration code needed beyond existing Codable persistence, but confirm new fields round-trip cleanly. |
| `Sources/VibeLight/App/AppDelegate.swift` | Build resolved session-source paths from settings, inject them into runtime services, and rebuild indexing when source preferences change. |
| `Sources/VibeLight/Watchers/Indexer.swift` | Replace home-relative path assumptions with resolved paths, add reset/rebuild behavior for source changes, and update static file lookup to use derived paths. |
| `Sources/VibeLight/Watchers/IndexScanner.swift` | Scan Claude/Codex sessions from resolved directories instead of fixed home-relative roots. |
| `Sources/VibeLight/Watchers/IndexingHelpers.swift` | Load Codex metadata from resolved derived paths. |
| `Sources/VibeLight/Data/LiveSessionRegistry.swift` | Use resolved Claude PID-session path and resolved Codex state DB path. |
| `Sources/VibeLight/Data/CodexStateDB.swift` | Add explicit initializer path usage to support custom Codex roots. |
| `Sources/VibeLight/Data/SessionIndex.swift` | Add a clear-and-rebuild entry point so old-root sessions do not survive source changes. |
| `Sources/VibeLight/UI/SearchPanelController.swift` | Use resolved session-source paths for transcript preview file lookup and keep history mode controlled by settings. |
| `Sources/VibeLight/UI/PreferencesWindowController.swift` | Final editorial-minimal two-tab layout, search-history toggle, data-source fallback UI, and strict row alignment metrics. |
| `Sources/VibeLight/UI/ShortcutCaptureWindowController.swift` | Keep the retained-sheet behavior and ensure button exits stay stable during the final layout pass. |
| `Sources/VibeLight/Onboarding/EnvironmentCheckService.swift` | Reuse session-source expectations for path checks so onboarding and preferences report the same defaults. |
| `Tests/VibeLightTests/SettingsStoreTests.swift` | Add round-trip tests for Claude/Codex source preferences. |
| `Tests/VibeLightTests/PreferencesWindowControllerTests.swift` | Add controller tests for history toggle behavior and data-source fallback visibility. |
| `Tests/VibeLightTests/SessionSourceLocatorTests.swift` | New tests for auto/custom path resolution and fallback-state reporting. |
| `Tests/VibeLightTests/ScaffoldSmokeTests.swift` | Extend smoke coverage if app settings application needs explicit restart/rebuild verification. |

---

### Task 1: Persist source fallback preferences in settings

**Files:**
- Create: `Sources/VibeLight/Settings/SessionSourceConfiguration.swift`
- Modify: `Sources/VibeLight/Settings/AppSettings.swift`
- Test: `Tests/VibeLightTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write the failing settings round-trip test**

Add to `Tests/VibeLightTests/SettingsStoreTests.swift`:

```swift
@Test("persists custom Claude and Codex source roots")
func persistsCustomClaudeAndCodexSourceRoots() {
    let suite = UserDefaults(suiteName: "SettingsStoreTests.sources.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)

    var settings = store.load()
    settings.historyMode = .liveOnly
    settings.claudeSource = .custom("~/Library/Application Support/AltClaude")
    settings.codexSource = .custom("~/Library/Application Support/AltCodex")
    store.save(settings)

    let reloaded = store.load()
    #expect(reloaded.historyMode == .liveOnly)
    #expect(reloaded.claudeSource == .custom("~/Library/Application Support/AltClaude"))
    #expect(reloaded.codexSource == .custom("~/Library/Application Support/AltCodex"))
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter persistsCustomClaudeAndCodexSourceRoots`

Expected: FAIL because `AppSettings` does not yet have `claudeSource` or `codexSource`.

- [ ] **Step 3: Add source preference types**

Create `Sources/VibeLight/Settings/SessionSourceConfiguration.swift`:

```swift
import Foundation

enum SessionSourceMode: String, Codable, Sendable {
    case auto
    case custom
}

struct ToolSessionSourcePreference: Codable, Equatable, Sendable {
    var mode: SessionSourceMode
    var customRootPath: String

    static let automatic = ToolSessionSourcePreference(mode: .auto, customRootPath: "")

    static func custom(_ path: String) -> ToolSessionSourcePreference {
        ToolSessionSourcePreference(mode: .custom, customRootPath: path)
    }

    var normalizedCustomRootPath: String? {
        let trimmed = customRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return (trimmed as NSString).expandingTildeInPath
    }
}
```

- [ ] **Step 4: Extend `AppSettings` with source preferences**

Update `Sources/VibeLight/Settings/AppSettings.swift`:

```swift
struct AppSettings: Codable, Equatable, Sendable {
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32
    var theme: AppTheme
    var historyMode: SearchHistoryMode
    var launchAtLogin: Bool
    var onboardingCompleted: Bool
    var claudeSource: ToolSessionSourcePreference
    var codexSource: ToolSessionSourcePreference

    static let `default` = AppSettings(
        hotkeyKeyCode: UInt32(kVK_Space),
        hotkeyModifiers: UInt32(cmdKey | shiftKey),
        theme: .system,
        historyMode: .liveAndHistory,
        launchAtLogin: true,
        onboardingCompleted: false,
        claudeSource: .automatic,
        codexSource: .automatic
    )
}
```

Add the two fields to `CodingKeys`, the memberwise init, and the custom `init(from:)` fallback logic:

```swift
self.claudeSource = try container.decodeIfPresent(ToolSessionSourcePreference.self, forKey: .claudeSource)
    ?? Self.default.claudeSource
self.codexSource = try container.decodeIfPresent(ToolSessionSourcePreference.self, forKey: .codexSource)
    ?? Self.default.codexSource
```

- [ ] **Step 5: Re-run settings tests**

Run: `swift test --filter SettingsStoreTests`

Expected: PASS for existing settings tests and the new source-preference round-trip test.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Settings/SessionSourceConfiguration.swift Sources/VibeLight/Settings/AppSettings.swift Tests/VibeLightTests/SettingsStoreTests.swift
git commit -m "feat: persist Claude and Codex source fallback preferences"
```

---

### Task 2: Centralize auto/custom source resolution

**Files:**
- Create: `Sources/VibeLight/Settings/SessionSourceLocator.swift`
- Create: `Tests/VibeLightTests/SessionSourceLocatorTests.swift`
- Modify: `Sources/VibeLight/Onboarding/EnvironmentCheckService.swift`

- [ ] **Step 1: Write the failing resolver tests**

Create `Tests/VibeLightTests/SessionSourceLocatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Flare

@Suite("Session source locator")
struct SessionSourceLocatorTests {
    @Test("uses auto roots when default directories exist")
    func usesAutoRootsWhenDefaultDirectoriesExist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude/projects"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".claude/sessions"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".codex/sessions"), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: root.appendingPathComponent(".codex/session_index.jsonl").path, contents: Data())
        FileManager.default.createFile(atPath: root.appendingPathComponent(".codex/state_5.sqlite").path, contents: Data())

        let locator = SessionSourceLocator(fileManager: .default, homeDirectoryPath: root.path)
        let resolution = locator.resolve(settings: .default)

        #expect(resolution.claude.mode == .auto)
        #expect(resolution.codex.mode == .auto)
        #expect(resolution.claudeProjectsPath.hasSuffix("/.claude/projects"))
        #expect(resolution.codexSessionsPath.hasSuffix("/.codex/sessions"))
    }

    @Test("marks auto roots as needing fallback when directories are missing")
    func marksAutoRootsAsNeedingFallbackWhenDirectoriesAreMissing() {
        let locator = SessionSourceLocator(fileManager: .default, homeDirectoryPath: "/tmp/does-not-exist-\(UUID().uuidString)")
        let resolution = locator.resolve(settings: .default)

        #expect(resolution.claude.shouldPromptForManualSelection)
        #expect(resolution.codex.shouldPromptForManualSelection)
    }
}
```

- [ ] **Step 2: Run the resolver tests to verify they fail**

Run: `swift test --filter SessionSourceLocatorTests`

Expected: FAIL because `SessionSourceLocator` does not exist.

- [ ] **Step 3: Implement `SessionSourceLocator`**

Create `Sources/VibeLight/Settings/SessionSourceLocator.swift`:

```swift
import Foundation

struct ResolvedToolSessionSource: Equatable, Sendable {
    let mode: SessionSourceMode
    let rootPath: String
    let statusText: String
    let isReachable: Bool
    let shouldPromptForManualSelection: Bool
}

struct SessionSourceResolution: Equatable, Sendable {
    let claude: ResolvedToolSessionSource
    let codex: ResolvedToolSessionSource
    let claudeProjectsPath: String
    let claudeSessionsPath: String
    let codexSessionsPath: String
    let codexSessionIndexPath: String
    let codexStateDBPath: String
}

struct SessionSourceLocator: Sendable {
    let fileManager: FileManager
    let homeDirectoryPath: String

    init(
        fileManager: FileManager = .default,
        homeDirectoryPath: String = FileManager.default.homeDirectoryForCurrentUser.path
    ) {
        self.fileManager = fileManager
        self.homeDirectoryPath = homeDirectoryPath
    }

    func resolve(settings: AppSettings) -> SessionSourceResolution {
        let autoClaudeRoot = homeDirectoryPath + "/.claude"
        let autoCodexRoot = homeDirectoryPath + "/.codex"

        let claudeRoot = settings.claudeSource.mode == .custom
            ? (settings.claudeSource.normalizedCustomRootPath ?? autoClaudeRoot)
            : autoClaudeRoot
        let codexRoot = settings.codexSource.mode == .custom
            ? (settings.codexSource.normalizedCustomRootPath ?? autoCodexRoot)
            : autoCodexRoot

        let claudeProjectsPath = claudeRoot + "/projects"
        let claudeSessionsPath = claudeRoot + "/sessions"
        let codexSessionsPath = codexRoot + "/sessions"
        let codexSessionIndexPath = codexRoot + "/session_index.jsonl"
        let codexStateDBPath = codexRoot + "/state_5.sqlite"

        let claudeReachable = fileManager.fileExists(atPath: claudeProjectsPath) || fileManager.fileExists(atPath: claudeSessionsPath)
        let codexReachable = fileManager.fileExists(atPath: codexSessionsPath)

        return SessionSourceResolution(
            claude: ResolvedToolSessionSource(
                mode: settings.claudeSource.mode,
                rootPath: claudeRoot,
                statusText: claudeReachable ? (settings.claudeSource.mode == .auto ? "Auto" : "Custom") : "Not Found",
                isReachable: claudeReachable,
                shouldPromptForManualSelection: !claudeReachable
            ),
            codex: ResolvedToolSessionSource(
                mode: settings.codexSource.mode,
                rootPath: codexRoot,
                statusText: codexReachable ? (settings.codexSource.mode == .auto ? "Auto" : "Custom") : "Not Found",
                isReachable: codexReachable,
                shouldPromptForManualSelection: !codexReachable
            ),
            claudeProjectsPath: claudeProjectsPath,
            claudeSessionsPath: claudeSessionsPath,
            codexSessionsPath: codexSessionsPath,
            codexSessionIndexPath: codexSessionIndexPath,
            codexStateDBPath: codexStateDBPath
        )
    }
}
```

- [ ] **Step 4: Keep onboarding path checks consistent**

Update `Sources/VibeLight/Onboarding/EnvironmentCheckService.swift` to derive expected roots through the same defaults:

```swift
let locator = SessionSourceLocator(fileManager: fileManager, homeDirectoryPath: homeDirectoryPath)
let resolution = locator.resolve(settings: .default)
let checkedPaths = [
    resolution.claude.rootPath,
    resolution.codex.rootPath,
]
```

- [ ] **Step 5: Re-run the resolver and onboarding-adjacent tests**

Run: `swift test --filter SessionSourceLocatorTests --filter EnvironmentCheckServiceTests`

Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Settings/SessionSourceLocator.swift Sources/VibeLight/Onboarding/EnvironmentCheckService.swift Tests/VibeLightTests/SessionSourceLocatorTests.swift
git commit -m "feat: centralize Claude and Codex source path resolution"
```

---

### Task 3: Rewire runtime indexing and preview lookup to use resolved paths

**Files:**
- Modify: `Sources/VibeLight/App/AppDelegate.swift`
- Modify: `Sources/VibeLight/Watchers/Indexer.swift`
- Modify: `Sources/VibeLight/Watchers/IndexScanner.swift`
- Modify: `Sources/VibeLight/Watchers/IndexingHelpers.swift`
- Modify: `Sources/VibeLight/Data/LiveSessionRegistry.swift`
- Modify: `Sources/VibeLight/Data/CodexStateDB.swift`
- Modify: `Sources/VibeLight/Data/SessionIndex.swift`
- Modify: `Sources/VibeLight/UI/SearchPanelController.swift`

- [ ] **Step 1: Write the failing stale-source reset test**

Add to `Tests/VibeLightTests/SessionIndexTests.swift`:

```swift
@Test("clears indexed sessions before rebuilding from a new source root")
func clearsIndexedSessionsBeforeRebuildingFromANewSourceRoot() throws {
    let dbPath = FileManager.default.temporaryDirectory.appendingPathComponent("source-reset-\(UUID().uuidString).sqlite3").path
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let index = try SessionIndex(dbPath: dbPath)
    let now = Date()

    try index.upsertSession(
        id: "old-root-session",
        tool: "claude",
        title: "Old Root",
        project: "/tmp/old",
        projectName: "old",
        gitBranch: "",
        status: "closed",
        startedAt: now,
        pid: nil,
        lastActivityAt: now
    )

    try index.clearAllIndexedSessions()

    let results = try index.search(query: "", includeHistory: true)
    #expect(results.isEmpty)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter clearsIndexedSessionsBeforeRebuildingFromANewSourceRoot`

Expected: FAIL because `clearAllIndexedSessions()` does not exist.

- [ ] **Step 3: Add a session-index reset hook**

Update `Sources/VibeLight/Data/SessionIndex.swift`:

```swift
func clearAllIndexedSessions() throws {
    try db.execute("DELETE FROM transcripts")
    try db.execute("DELETE FROM sessions")
}
```

- [ ] **Step 4: Thread `SessionSourceResolution` through runtime services**

Use one explicit runtime resolution instead of home-directory guessing:

```swift
let sourceResolution = SessionSourceLocator(homeDirectoryPath: FileManager.default.homeDirectoryForCurrentUser.path)
    .resolve(settings: settings)

let panelController = SearchPanelController(sessionSourceResolution: sourceResolution)
let indexer = Indexer(sessionIndex: sessionIndex, sessionSourceResolution: sourceResolution)
```

Update the relevant initializers and stored properties:

```swift
final class Indexer {
    private let sessionSourceResolution: SessionSourceResolution

    init(sessionIndex: SessionIndex, sessionSourceResolution: SessionSourceResolution) {
        self.sessionIndex = sessionIndex
        self.sessionSourceResolution = sessionSourceResolution
    }
}
```

```swift
@MainActor
final class SearchPanelController: NSObject {
    private var sessionSourceResolution: SessionSourceResolution
}
```

- [ ] **Step 5: Replace hardcoded paths in scanning and lookup**

Use resolved paths in the existing scan and lookup code:

```swift
// IndexScanner
let projectsPath = sessionSourceResolution.claudeProjectsPath
let sessionsPath = sessionSourceResolution.codexSessionsPath
let codexGitBranchMap = CodexStateDB(path: sessionSourceResolution.codexStateDBPath).gitBranchMap()
codexTitleMap = IndexingHelpers.loadCodexTitleMap(indexPath: sessionSourceResolution.codexSessionIndexPath)
```

```swift
// LiveSessionRegistry
static func scan(resolution: SessionSourceResolution) -> [LiveSession] {
    scanClaudeSessions(pidSessionsPath: resolution.claudeSessionsPath)
    + scanCodexSessions(codexStateDBPath: resolution.codexStateDBPath)
}
```

```swift
// Indexer static lookup
nonisolated static func findSessionFileStatic(sessionId: String, resolution: SessionSourceResolution) -> URL? {
    let fm = FileManager.default
    let claudeProjectsPath = resolution.claudeProjectsPath
    let codexRoot = URL(fileURLWithPath: resolution.codexSessionsPath, isDirectory: true)

    if let projectDirs = try? fm.contentsOfDirectory(atPath: claudeProjectsPath) {
        for projectDir in projectDirs {
            let path = "\(claudeProjectsPath)/\(projectDir)/\(sessionId).jsonl"
            if fm.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
    }

    if let enumerator = fm.enumerator(
        at: codexRoot,
        includingPropertiesForKeys: [.isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) {
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "jsonl" {
            let candidateIDs = [
                fileURL.deletingPathExtension().lastPathComponent,
                IndexingHelpers.codexSessionIDFromPath(fileURL.path),
            ].compactMap { $0 }
            if candidateIDs.contains(sessionId) {
                return fileURL
            }
        }
    }

    return nil
}
```

Then in `SearchPanelController`, replace the duplicated `findSessionFile` implementation with a call to `Indexer.findSessionFileStatic(sessionId:resolution:)`.

- [ ] **Step 6: Rebuild cleanly when source preferences change**

In `Sources/VibeLight/App/AppDelegate.swift`, compare previous and new source preferences in `applySettings(_:)`:

```swift
let oldSourcePair = (settings.claudeSource, settings.codexSource)
settings = newSettings

if oldSourcePair != (newSettings.claudeSource, newSettings.codexSource) {
    let resolution = SessionSourceLocator().resolve(settings: newSettings)
    try? sessionIndex?.clearAllIndexedSessions()
    indexer?.stop()
    indexer = Indexer(sessionIndex: sessionIndex!, sessionSourceResolution: resolution)
    searchPanelController?.updateSessionSourceResolution(resolution)
    indexer?.start()
}
```

- [ ] **Step 7: Run the integration-focused tests**

Run: `swift test --filter SessionIndexTests --filter AppDelegateSelectionRoutingTests --filter SearchPanelScriptTests`

Expected: PASS

- [ ] **Step 8: Commit**

```bash
git add Sources/VibeLight/App/AppDelegate.swift Sources/VibeLight/Watchers/Indexer.swift Sources/VibeLight/Watchers/IndexScanner.swift Sources/VibeLight/Watchers/IndexingHelpers.swift Sources/VibeLight/Data/LiveSessionRegistry.swift Sources/VibeLight/Data/CodexStateDB.swift Sources/VibeLight/Data/SessionIndex.swift Sources/VibeLight/UI/SearchPanelController.swift Tests/VibeLightTests/SessionIndexTests.swift
git commit -m "feat: use resolved session source paths across runtime services"
```

---

### Task 4: Redesign the preferences window and add settings controls

**Files:**
- Modify: `Sources/VibeLight/UI/PreferencesWindowController.swift`
- Modify: `Sources/VibeLight/UI/ShortcutCaptureWindowController.swift`
- Test: `Tests/VibeLightTests/PreferencesWindowControllerTests.swift`

- [ ] **Step 1: Add failing controller tests for the new settings rows**

Extend `Tests/VibeLightTests/PreferencesWindowControllerTests.swift`:

```swift
@Test("settings tab shows search history toggle and data source controls")
func settingsTabShowsSearchHistoryToggleAndDataSourceControls() throws {
    let controller = makeController()
    controller.showPreferences()

    let window = try #require(controller.window)
    #expect(findButton(titled: "Change Shortcut", in: window.contentView) != nil)
    #expect(findStaticText(containing: "Search history", in: window.contentView) != nil)
    #expect(findStaticText(containing: "Data Sources", in: window.contentView) != nil)
}
```

- [ ] **Step 2: Run the controller tests to verify they fail**

Run: `swift test --filter PreferencesWindowControllerTests`

Expected: FAIL because the window does not yet show the new rows and footer text.

- [ ] **Step 3: Introduce shared layout metrics so alignment is explicit**

At the top of `PreferencesWindowController.swift`, replace ad hoc sizing with a small metric set:

```swift
private let windowWidth: CGFloat = 720
private let sidebarWidth: CGFloat = 172
private let contentColumnWidth: CGFloat = 500
private let rowWidth: CGFloat = 468
private let sectionCornerRadius: CGFloat = 8
private let rowMinHeight: CGFloat = 48
private let sectionSpacing: CGFloat = 14
private let contentInset: CGFloat = 24
```

Every row builder should use the same label/control layout:

```swift
row.widthAnchor.constraint(equalToConstant: rowWidth)
row.heightAnchor.constraint(greaterThanOrEqualToConstant: rowMinHeight)
textStack.leadingAnchor.constraint(equalTo: row.leadingAnchor)
control.trailingAnchor.constraint(equalTo: row.trailingAnchor)
textStack.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -14)
```

- [ ] **Step 4: Finalize the editorial-minimal visual treatment**

Update the section and header styling:

```swift
private func makeHeader(for pane: PreferencesPane) -> NSView {
    let title = NSTextField(labelWithString: pane.title)
    title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

    let subtitle = NSTextField(wrappingLabelWithString: pane == .settings
        ? "Controls for behavior, history, shortcuts, and source paths."
        : "Version and environment details.")
    subtitle.font = NSFont.systemFont(ofSize: 12, weight: .regular)
    subtitle.textColor = .secondaryLabelColor

    let stack = NSStackView(views: [title, subtitle])
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    return stack
}
```

Use subtle grouped sections instead of large glossy cards:

```swift
card.layer?.cornerRadius = sectionCornerRadius
card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.55).cgColor
card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.08).cgColor
```

Do not reintroduce `Main Settings`, oversized hero copy, or large decorative blocks.

- [ ] **Step 5: Add the search-history toggle with footnote**

Add a new row in `makeSettingsPane()`:

```swift
makeToggleRow(
    title: "Search history",
    subtitle: "Include closed sessions in search results.",
    footnote: "After searching, press Tab in the panel to switch modes quickly.",
    toggle: historyModeToggle
)
```

Back it with existing `historyMode`:

```swift
@objc private func historyModeChanged() {
    settings.historyMode = historyModeToggle.state == .on ? .liveAndHistory : .liveOnly
    saveSettings(status: "Search history updated")
}
```

- [ ] **Step 6: Add the data-source fallback controls**

Render one compact row per tool:

```swift
makeDataSourceRow(
    title: "Claude",
    status: sourceResolution.claude.statusText,
    path: sourceResolution.claude.rootPath,
    showsCustomControls: sourceResolution.claude.shouldPromptForManualSelection || settings.claudeSource.mode == .custom,
    chooseAction: #selector(chooseClaudeRootAction),
    resetAction: #selector(resetClaudeRootAction)
)
```

Use `NSOpenPanel` for directory picking:

```swift
private func chooseRootFolder() -> String? {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.canCreateDirectories = false
    panel.allowsMultipleSelection = false
    return panel.runModal() == .OK ? panel.url?.path : nil
}
```

When the user picks a folder:

```swift
if let path = chooseRootFolder() {
    settings.claudeSource = .custom(path)
    if sessionSourceLocator.resolve(settings: settings).claude.isReachable {
        saveSettings(status: "Claude source updated")
    } else {
        statusLabel.stringValue = "Claude source is missing expected session folders"
    }
}
```

- [ ] **Step 7: Keep all button exits stable**

Do not regress the shortcut sheet fix. Keep the retained controller reference and the explicit `endSheet` close path:

```swift
shortcutCaptureWindowController = controller
controller.presentSheet(for: window) { [weak self] in
    self?.shortcutCaptureWindowController = nil
}
```

- [ ] **Step 8: Re-run the preferences tests**

Run: `swift test --filter PreferencesWindowControllerTests --filter ScaffoldSmokeTests`

Expected: PASS

- [ ] **Step 9: Commit**

```bash
git add Sources/VibeLight/UI/PreferencesWindowController.swift Sources/VibeLight/UI/ShortcutCaptureWindowController.swift Tests/VibeLightTests/PreferencesWindowControllerTests.swift
git commit -m "feat: redesign preferences window and add source fallback controls"
```

---

### Task 5: Surface source status in About and verify end-to-end behavior

**Files:**
- Modify: `Sources/VibeLight/UI/PreferencesWindowController.swift`
- Modify: `Sources/VibeLight/App/AppDelegate.swift`
- Modify: `Tests/VibeLightTests/PreferencesWindowControllerTests.swift`
- Modify: `Tests/VibeLightTests/ScaffoldSmokeTests.swift`

- [ ] **Step 1: Add a failing smoke check for About status content**

Add to `Tests/VibeLightTests/PreferencesWindowControllerTests.swift`:

```swift
@Test("about tab shows source status summary")
func aboutTabShowsSourceStatusSummary() throws {
    let controller = makeController()
    controller.showPreferences()

    let window = try #require(controller.window)
    let aboutButton = try #require(findButton(titled: "About", in: window.contentView))
    aboutButton.performClick(nil)

    #expect(findStaticText(containing: "Claude", in: window.contentView) != nil)
    #expect(findStaticText(containing: "Codex", in: window.contentView) != nil)
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter aboutTabShowsSourceStatusSummary`

Expected: FAIL if the About pane still only shows generic version/build details.

- [ ] **Step 3: Add source summary rows to About**

Use the same resolver already available in preferences:

```swift
makeValueRow(title: "Claude Source", value: "\(sourceResolution.claude.statusText) • \(sourceResolution.claude.rootPath)")
makeValueRow(title: "Codex Source", value: "\(sourceResolution.codex.statusText) • \(sourceResolution.codex.rootPath)")
```

- [ ] **Step 4: Verify runtime rebuild on source change**

Add a focused smoke assertion in `Tests/VibeLightTests/ScaffoldSmokeTests.swift` or a new AppDelegate-focused test file that verifies settings application can accept updated source preferences without crashing:

```swift
@MainActor
@Test
func appDelegateAcceptsCustomSourceSettings() {
    let suite = UserDefaults(suiteName: "AppDelegate.customSources.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    var settings = store.load()
    settings.claudeSource = .custom("/tmp/claude-custom")
    settings.codexSource = .custom("/tmp/codex-custom")
    store.save(settings)

    let delegate = AppDelegate(startsRuntimeServices: false, settingsStore: store)
    delegate.openPreferences()

    #expect(delegate.isPreferencesVisible)
}
```

- [ ] **Step 5: Run the final targeted verification suite**

Run: `swift test --filter SettingsStoreTests --filter SessionSourceLocatorTests --filter PreferencesWindowControllerTests --filter ScaffoldSmokeTests`

Expected: PASS

- [ ] **Step 6: Manual QA**

Run:

```bash
swift run Flare
```

Verify manually:

- `Settings` and `About` are the only tabs.
- All buttons work.
- `Cancel` exits the shortcut sheet cleanly.
- The `Search history` toggle persists and updates behavior.
- `Data Sources` shows `Auto` when default roots exist.
- Choosing a bad custom root shows a compact error state instead of silently saving.
- Choosing a valid custom root reindexes from the new location.
- The window feels flatter, tighter, and aligned:
  - row baselines line up
  - section widths match
  - control edges line up
  - no oversized header or card treatment remains

- [ ] **Step 7: Commit**

```bash
git add Sources/VibeLight/UI/PreferencesWindowController.swift Sources/VibeLight/App/AppDelegate.swift Tests/VibeLightTests/PreferencesWindowControllerTests.swift Tests/VibeLightTests/ScaffoldSmokeTests.swift
git commit -m "feat: add source status summary and verify preferences rebuild flow"
```
