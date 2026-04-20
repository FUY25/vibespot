# Performance And Preferences Refinement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rescue Preferences usability, stop the highest-cost unnecessary refresh/reindex paths, and make Flare behave like a Spotlight-style tool: history is event-driven, live state stays fresh, and source switching no longer destroys the active index.

**Architecture:** Treat this as one runtime refinement, not isolated UI cleanup. Split settings application into lightweight immediate updates versus staged source switching; give each source combination its own index workspace; move indexing off the main actor; and replace timer-driven full searches with event-driven history refresh plus a lightweight visible-live tick. Unify session-file lookup behind one shared locator and make transcript ingestion append-only so JSONL growth no longer forces full transcript rewrites on every change.

**Tech Stack:** Swift 6, AppKit, SQLite (WAL), `WKWebView`, Swift Testing (`@Test` / `@Suite`), existing Flare parsers/indexers/watchers.

---

## Scope Note

This plan intentionally combines Preferences rescue and performance work because the blocking problems all converge in the same runtime seams:

- `AppDelegate` decides whether a change is lightweight or destructive.
- `PreferencesWindowController` currently triggers heavyweight side effects directly.
- `SearchPanelController` currently mixes history search refresh and live state refresh.
- `Indexer` currently mixes file watching, live polling, metadata refresh, and full transcript ingestion on the main actor.

Splitting those seams is the actual fix.

## File Map

| File | What changes |
| --- | --- |
| `Sources/VibeLight/Settings/SessionSourceConfiguration.swift` | Replace the single global source mode with per-tool source preferences and richer resolved status/fingerprint types. |
| `Sources/VibeLight/Settings/AppSettings.swift` | Persist the new per-tool source configuration shape. |
| `Sources/VibeLight/Settings/SettingsStore.swift` | Keep Codable persistence, but add round-trip coverage for the new source model. |
| `Sources/VibeLight/App/AppSettingsChangeSet.swift` | New diff object that decides whether a settings change needs hotkey rebuild, panel refresh, or source switch. |
| `Sources/VibeLight/App/SourceSwitchCoordinator.swift` | New coordinator that builds a new source index in the background and swaps it in atomically. |
| `Sources/VibeLight/App/AppDelegate.swift` | Split lightweight settings application from staged source switching and wire the new runtime callbacks. |
| `Sources/VibeLight/Data/SessionIndexWorkspace.swift` | New helper for per-source active/staging SQLite paths in Application Support. |
| `Sources/VibeLight/Data/SessionFileLocator.swift` | New shared cached locator for `sessionId -> fileURL`, reused by the indexer and search preview. |
| `Sources/VibeLight/Data/SessionIndex.swift` | Add lightweight live-row refresh APIs, targeted metadata updates, and append-only file ingestion state. |
| `Sources/VibeLight/UI/PreferencesSourceDraft.swift` | New draft model for staged source edits inside Preferences. |
| `Sources/VibeLight/UI/PreferencesWindowController.swift` | Replace the current two-pane window with a smaller single-page form; only source edits are staged. |
| `Sources/VibeLight/UI/SearchPanelController.swift` | Remove the 500ms full-search timer, keep a visible-live lightweight tick, and cancel stale preview tasks. |
| `Sources/VibeLight/Watchers/FileWatcher.swift` | Stop dispatching file events on `.main`; use a utility queue. |
| `Sources/VibeLight/Watchers/Indexer.swift` | Move heavy work off the main actor, remove global codex reindex on metadata changes, and switch transcript ingestion to append-only. |
| `Sources/VibeLight/Watchers/IndexScanner.swift` | Reuse the same scanning/build paths for active index builds and staged source-switch builds. |
| `Sources/VibeLight/Watchers/IndexingHelpers.swift` | Keep helper functions focused on parsing/metadata transforms; drop duplicated file-lookup responsibilities. |
| `Sources/VibeLight/Parsers/ClaudeParser.swift` | Add append-only parsing entry points that can parse from a byte offset. |
| `Sources/VibeLight/Parsers/CodexParser.swift` | Add append-only parsing entry points that can parse from a byte offset. |
| `Tests/VibeLightTests/SettingsStoreTests.swift` | Add round-trip tests for independent Claude/Codex source settings. |
| `Tests/VibeLightTests/SessionSourceConfigurationTests.swift` | New tests for per-tool resolution, fallback reporting, and source fingerprints. |
| `Tests/VibeLightTests/PreferencesWindowControllerTests.swift` | Add tests for staged source Apply, warning states, and single-page rendering. |
| `Tests/VibeLightTests/AppSettingsChangeSetTests.swift` | New tests that lock in “history mode does not rebuild hotkeys/source runtime.” |
| `Tests/VibeLightTests/SessionIndexWorkspaceTests.swift` | New tests for stable per-source DB paths and staging/active separation. |
| `Tests/VibeLightTests/SourceSwitchCoordinatorTests.swift` | New tests for preserving the active index until the staged build succeeds. |
| `Tests/VibeLightTests/SearchPanelControllerRefreshTests.swift` | New tests for “history does not auto-research; live can tick lightly.” |
| `Tests/VibeLightTests/IndexerLiveRefreshTests.swift` | Extend current tests to cover live-only tick policy and no full codex reindex on metadata changes. |
| `Tests/VibeLightTests/SessionFileLocatorTests.swift` | New tests for shared file lookup caching and fallback behavior. |
| `Tests/VibeLightTests/SessionIndexTests.swift` | Add append-only transcript ingestion and targeted metadata update tests. |
| `Tests/VibeLightTests/ClaudeParserTests.swift` | Add offset-based parsing tests. |
| `Tests/VibeLightTests/CodexParserTests.swift` | Add offset-based parsing tests. |

---

### Task 1: Re-model source settings around independent Claude/Codex preferences

**Files:**
- Modify: `Sources/VibeLight/Settings/SessionSourceConfiguration.swift`
- Modify: `Sources/VibeLight/Settings/AppSettings.swift`
- Test: `Tests/VibeLightTests/SettingsStoreTests.swift`
- Create: `Tests/VibeLightTests/SessionSourceConfigurationTests.swift`

- [ ] **Step 1: Write the failing tests for independent source settings and fallback reporting**

Add to `Tests/VibeLightTests/SettingsStoreTests.swift`:

```swift
@Test("persists independent Claude and Codex source settings")
func persistsIndependentClaudeAndCodexSourceSettings() {
    let suite = UserDefaults(suiteName: "SettingsStoreTests.independentSources.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)

    var settings = store.load()
    settings.sessionSourceConfiguration = SessionSourceConfiguration(
        claude: .init(mode: .custom, customRoot: "/tmp/claude"),
        codex: .init(mode: .automatic, customRoot: "")
    )
    store.save(settings)

    let reloaded = store.load()
    #expect(reloaded.sessionSourceConfiguration.claude.mode == .custom)
    #expect(reloaded.sessionSourceConfiguration.claude.customRoot == "/tmp/claude")
    #expect(reloaded.sessionSourceConfiguration.codex.mode == .automatic)
}
```

Create `Tests/VibeLightTests/SessionSourceConfigurationTests.swift`:

```swift
import Foundation
import Testing
@testable import Flare

@Suite("Session source configuration")
struct SessionSourceConfigurationTests {
    @Test("effective fingerprint changes only when effective roots change")
    func effectiveFingerprintChangesOnlyWhenEffectiveRootsChange() {
        let locator = SessionSourceLocator(homeDirectoryPath: "/Users/me")
        var settings = AppSettings.default

        let automatic = locator.resolve(for: settings)

        settings.sessionSourceConfiguration = SessionSourceConfiguration(
            claude: .init(mode: .custom, customRoot: "/missing-claude"),
            codex: .init(mode: .custom, customRoot: "/missing-codex")
        )
        let fallback = locator.resolve(for: settings)

        #expect(automatic.effectiveFingerprint == fallback.effectiveFingerprint)
    }

    @Test("reports unavailable source when custom is invalid and auto is missing")
    func reportsUnavailableSourceWhenNoFallbackExists() {
        let locator = SessionSourceLocator(homeDirectoryPath: "/tmp/does-not-exist-\(UUID().uuidString)")
        var settings = AppSettings.default
        settings.sessionSourceConfiguration = SessionSourceConfiguration(
            claude: .init(mode: .custom, customRoot: "/tmp/bad-claude"),
            codex: .init(mode: .custom, customRoot: "/tmp/bad-codex")
        )

        let resolution = locator.resolve(for: settings)
        #expect(resolution.claude.status == .unavailable)
        #expect(resolution.codex.status == .unavailable)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --filter SettingsStoreTests
swift test --filter SessionSourceConfigurationTests
```

Expected: FAIL because `SessionSourceConfiguration` is still a single shared mode and `SessionSourceResolution` does not yet expose per-tool status or `effectiveFingerprint`.

- [ ] **Step 3: Replace the current shared-mode model with per-tool source preferences**

Update `Sources/VibeLight/Settings/SessionSourceConfiguration.swift` to this shape:

```swift
import Foundation

enum SessionSourceMode: String, Codable, Sendable {
    case automatic
    case custom
}

struct ToolSessionSourceConfiguration: Codable, Equatable, Sendable {
    var mode: SessionSourceMode
    var customRoot: String
}

enum ResolvedToolSourceStatus: Equatable, Sendable {
    case automatic
    case custom
    case fallbackToAutomatic
    case unavailable
}

struct SessionSourceConfiguration: Codable, Equatable, Sendable {
    var claude: ToolSessionSourceConfiguration
    var codex: ToolSessionSourceConfiguration

    static let `default` = SessionSourceConfiguration(
        claude: .init(mode: .automatic, customRoot: ""),
        codex: .init(mode: .automatic, customRoot: "")
    )
}

struct ResolvedToolSource: Equatable, Sendable {
    let rootPath: String
    let sessionsPath: String
    let status: ResolvedToolSourceStatus
    let autoAvailable: Bool
}

struct SessionSourceResolution: Equatable, Sendable {
    let claude: ResolvedToolSource
    let codex: ResolvedToolSource
    let effectiveFingerprint: String

    var claudeProjectsPath: String { claude.rootPath + "/projects" }
    var claudeSessionsPath: String { claude.rootPath + "/sessions" }
    var codexSessionsPath: String { codex.rootPath + "/sessions" }
    var codexStatePath: String { codex.rootPath + "/state_5.sqlite" }
}
```

Add an `effectiveFingerprint` derived from the effective resolved roots, not from requested UI metadata:

```swift
private static func makeFingerprint(claudeRoot: String, codexRoot: String) -> String {
    "\(claudeRoot)\n\(codexRoot)"
}
```

- [ ] **Step 4: Update `AppSettings` to persist the new source shape**

Update `Sources/VibeLight/Settings/AppSettings.swift`:

```swift
struct AppSettings: Codable, Equatable, Sendable {
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32
    var theme: AppTheme
    var historyMode: SearchHistoryMode
    var launchAtLogin: Bool
    var onboardingCompleted: Bool
    var sessionSourceConfiguration: SessionSourceConfiguration

    static let `default` = AppSettings(
        hotkeyKeyCode: UInt32(kVK_Space),
        hotkeyModifiers: UInt32(cmdKey | shiftKey),
        theme: .system,
        historyMode: .liveAndHistory,
        launchAtLogin: true,
        onboardingCompleted: false,
        sessionSourceConfiguration: .default
    )
}
```

The key change is that the nested type now round-trips as:

```swift
self.sessionSourceConfiguration = try container.decodeIfPresent(
    SessionSourceConfiguration.self,
    forKey: .sessionSourceConfiguration
) ?? .default
```

- [ ] **Step 5: Re-run the settings and source-resolution tests**

Run:

```bash
swift test --filter SettingsStoreTests
swift test --filter SessionSourceConfigurationTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Settings/SessionSourceConfiguration.swift Sources/VibeLight/Settings/AppSettings.swift Tests/VibeLightTests/SettingsStoreTests.swift Tests/VibeLightTests/SessionSourceConfigurationTests.swift
git commit -m "refactor: separate Claude and Codex source settings"
```

---

### Task 2: Replace the current Preferences window with a smaller single-page form and staged source Apply

**Files:**
- Create: `Sources/VibeLight/UI/PreferencesSourceDraft.swift`
- Modify: `Sources/VibeLight/UI/PreferencesWindowController.swift`
- Test: `Tests/VibeLightTests/PreferencesWindowControllerTests.swift`

- [ ] **Step 1: Write the failing Preferences tests**

Extend `Tests/VibeLightTests/PreferencesWindowControllerTests.swift`:

```swift
@Test("source edits stay local until Apply is clicked")
func sourceEditsStayLocalUntilApplyIsClicked() throws {
    let suite = UserDefaults(suiteName: "PreferencesWindowControllerTests.stagedSource.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    var appliedSettings: [AppSettings] = []

    let controller = PreferencesWindowController(
        settingsStore: store,
        launchAtLoginSupported: true,
        onApplySettings: { appliedSettings.append($0) },
        onReindex: {},
        onExportDiagnostics: {}
    )
    controller.showPreferences()

    let window = try #require(controller.window)
    let applyButton = try #require(findButton(titled: "Apply Source Changes", in: window.contentView))

    #expect(appliedSettings.isEmpty)
    #expect(applyButton.isEnabled == false)
}

@Test("source warning is visible when no valid fallback exists")
func sourceWarningIsVisibleWhenNoValidFallbackExists() throws {
    let controller = makeController()
    controller.showPreferences()

    let window = try #require(controller.window)
    #expect(findStaticText(containing: "current source stays active", in: window.contentView) != nil)
}
```

- [ ] **Step 2: Run the Preferences tests to verify they fail**

Run:

```bash
swift test --filter PreferencesWindowControllerTests
```

Expected: FAIL because the current window is still the two-pane version and source edits still save immediately.

- [ ] **Step 3: Add a dedicated staged source draft model**

Create `Sources/VibeLight/UI/PreferencesSourceDraft.swift`:

```swift
import Foundation

struct PreferencesSourceDraft: Equatable {
    var claude: ToolSessionSourceConfiguration
    var codex: ToolSessionSourceConfiguration

    init(settings: AppSettings) {
        self.claude = settings.sessionSourceConfiguration.claude
        self.codex = settings.sessionSourceConfiguration.codex
    }

    var isDirtyComparedToSettings: (AppSettings) -> Bool {
        { settings in
            SessionSourceConfiguration(claude: claude, codex: codex) != settings.sessionSourceConfiguration
        }
    }
}
```

- [ ] **Step 4: Flatten `PreferencesWindowController` into a smaller single-page form**

Replace the sidebar/about-pane composition with a single scrollable stack. The new body should look like:

```swift
private func rebuildContent() {
    for arrangedSubview in contentStack.arrangedSubviews {
        contentStack.removeArrangedSubview(arrangedSubview)
        arrangedSubview.removeFromSuperview()
    }

    let views = [
        makeHeaderCard(),
        makeSystemSettingsCard(),
        makeHistoryCard(),
        makeSourceCard(),
        makeAboutCard(),
    ]

    for view in views {
        contentStack.addArrangedSubview(view)
    }
}
```

The source card should use the draft model and only call `onApplySettings` when the user clicks the staged Apply button:

```swift
@objc private func applySourceChanges() {
    settings.sessionSourceConfiguration = SessionSourceConfiguration(
        claude: sourceDraft.claude,
        codex: sourceDraft.codex
    )
    saveSettings(status: "Source settings applied")
}
```

Theme, hotkey, and history mode should keep their current immediate-save behavior.

- [ ] **Step 5: Re-run the Preferences tests**

Run:

```bash
swift test --filter PreferencesWindowControllerTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/UI/PreferencesSourceDraft.swift Sources/VibeLight/UI/PreferencesWindowController.swift Tests/VibeLightTests/PreferencesWindowControllerTests.swift
git commit -m "refactor: stage source edits in single-page preferences"
```

---

### Task 3: Split lightweight settings application from expensive runtime changes

**Files:**
- Create: `Sources/VibeLight/App/AppSettingsChangeSet.swift`
- Modify: `Sources/VibeLight/App/AppDelegate.swift`
- Modify: `Sources/VibeLight/UI/SearchPanelController.swift`
- Create: `Tests/VibeLightTests/AppSettingsChangeSetTests.swift`

- [ ] **Step 1: Write the failing settings-diff tests**

Create `Tests/VibeLightTests/AppSettingsChangeSetTests.swift`:

```swift
import Testing
@testable import Flare

@Suite("App settings change set")
struct AppSettingsChangeSetTests {
    @Test("history mode change does not request hotkey rebuild or source switch")
    func historyModeChangeDoesNotRequestHotkeyRebuildOrSourceSwitch() {
        let old = AppSettings.default
        var new = old
        new.historyMode = .liveOnly

        let oldResolution = SessionSourceLocator().resolve(for: old)
        let newResolution = SessionSourceLocator().resolve(for: new)
        let changeSet = AppSettingsChangeSet(old: old, new: new, oldResolution: oldResolution, newResolution: newResolution)

        #expect(changeSet.historyModeChanged)
        #expect(changeSet.hotkeyChanged == false)
        #expect(changeSet.sourceFingerprintChanged == false)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --filter AppSettingsChangeSetTests
```

Expected: FAIL because `AppSettingsChangeSet` does not exist.

- [ ] **Step 3: Add a dedicated diff object and use it inside `AppDelegate`**

Create `Sources/VibeLight/App/AppSettingsChangeSet.swift`:

```swift
import Foundation

struct AppSettingsChangeSet: Equatable {
    let themeChanged: Bool
    let historyModeChanged: Bool
    let hotkeyChanged: Bool
    let sourceFingerprintChanged: Bool

    init(old: AppSettings, new: AppSettings, oldResolution: SessionSourceResolution, newResolution: SessionSourceResolution) {
        self.themeChanged = old.theme != new.theme
        self.historyModeChanged = old.historyMode != new.historyMode
        self.hotkeyChanged = old.hotkeyBinding != new.hotkeyBinding
        self.sourceFingerprintChanged = oldResolution.effectiveFingerprint != newResolution.effectiveFingerprint
    }
}
```

Update `AppDelegate.applySettings(_:)` so it uses the diff instead of always rebuilding hotkeys:

```swift
private func applySettings(_ newSettings: AppSettings) {
    let newResolution = sessionSourceLocator.resolve(for: newSettings)
    let changeSet = AppSettingsChangeSet(
        old: settings,
        new: newSettings,
        oldResolution: sessionSourceResolution,
        newResolution: newResolution
    )

    settings = newSettings

    if changeSet.themeChanged {
        applyAppearance(for: newSettings.theme)
    }
    if changeSet.historyModeChanged {
        searchPanelController?.applySettings(newSettings)
    }
    if changeSet.hotkeyChanged {
        rebuildHotkeyManagerIfNeeded()
    }
    if changeSet.sourceFingerprintChanged {
        beginSourceSwitch(to: newResolution)
    }
}
```

- [ ] **Step 4: Route `Tab` history-mode toggles through a lightweight setter**

Add to `AppDelegate.swift`:

```swift
private func setHistoryMode(_ historyMode: SearchHistoryMode) {
    guard settings.historyMode != historyMode else { return }
    var updated = settings
    updated.historyMode = historyMode
    settingsStore.save(updated)
    applySettings(updated)
}
```

Then replace the current `panelController.onHistoryModeChanged` closure with:

```swift
panelController.onHistoryModeChanged = { [weak self] historyMode in
    self?.setHistoryMode(historyMode)
}
```

- [ ] **Step 5: Re-run the diff and existing search-panel mode tests**

Run:

```bash
swift test --filter AppSettingsChangeSetTests
swift test --filter SearchPanelControllerPreviewTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/App/AppSettingsChangeSet.swift Sources/VibeLight/App/AppDelegate.swift Sources/VibeLight/UI/SearchPanelController.swift Tests/VibeLightTests/AppSettingsChangeSetTests.swift
git commit -m "refactor: separate lightweight settings from source switching"
```

---

### Task 4: Give each effective source combination its own index workspace and switch atomically

**Files:**
- Create: `Sources/VibeLight/Data/SessionIndexWorkspace.swift`
- Create: `Sources/VibeLight/App/SourceSwitchCoordinator.swift`
- Modify: `Sources/VibeLight/App/AppDelegate.swift`
- Modify: `Sources/VibeLight/Watchers/IndexScanner.swift`
- Create: `Tests/VibeLightTests/SessionIndexWorkspaceTests.swift`
- Create: `Tests/VibeLightTests/SourceSwitchCoordinatorTests.swift`

- [ ] **Step 1: Write the failing workspace and coordinator tests**

Create `Tests/VibeLightTests/SessionIndexWorkspaceTests.swift`:

```swift
import Foundation
import Testing
@testable import Flare

@Test("workspace uses separate active and staging DBs per source fingerprint")
func workspaceUsesSeparateActiveAndStagingDBsPerSourceFingerprint() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let workspace = SessionIndexWorkspace(rootURL: root)

    let active = workspace.activeDBURL(for: "claude-a\ncodex-a")
    let staging = workspace.stagingDBURL(for: "claude-a\ncodex-a")
    let other = workspace.activeDBURL(for: "claude-b\ncodex-b")

    #expect(active != staging)
    #expect(active != other)
}
```

Create `Tests/VibeLightTests/SourceSwitchCoordinatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Flare

@Test("coordinator keeps current DB active until staged build succeeds")
func coordinatorKeepsCurrentDBActiveUntilStagedBuildSucceeds() async throws {
    final class FakeBuilder: SourceIndexBuilding {
        var events: [String] = []

        func buildIndex(at dbPath: String, for resolution: SessionSourceResolution) throws {
            events.append("build")
            FileManager.default.createFile(atPath: dbPath, contents: Data(), attributes: nil)
        }
    }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let workspace = SessionIndexWorkspace(rootURL: root)
    let builder = FakeBuilder()
    let coordinator = SourceSwitchCoordinator(workspace: workspace, builder: builder)
    let resolution = SessionSourceResolution(
        claude: .init(rootPath: "/tmp/claude", sessionsPath: "/tmp/claude/sessions", status: .automatic, autoAvailable: true),
        codex: .init(rootPath: "/tmp/codex", sessionsPath: "/tmp/codex/sessions", status: .automatic, autoAvailable: true),
        effectiveFingerprint: "claude\ncodex"
    )

    var didSwap = false
    coordinator.buildAndSwap(to: resolution) { _ in
        didSwap = true
    }

    try await Task.sleep(for: .milliseconds(100))
    #expect(builder.events == ["build"])
    #expect(didSwap)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --filter SessionIndexWorkspaceTests
swift test --filter SourceSwitchCoordinatorTests
```

Expected: FAIL because neither helper exists.

- [ ] **Step 3: Add a source-aware index workspace**

Create `Sources/VibeLight/Data/SessionIndexWorkspace.swift`:

```swift
import Foundation

struct SessionIndexWorkspace {
    let rootURL: URL

    func activeDBURL(for fingerprint: String) -> URL {
        dbDirectory(for: fingerprint).appendingPathComponent("active.sqlite3")
    }

    func stagingDBURL(for fingerprint: String) -> URL {
        dbDirectory(for: fingerprint).appendingPathComponent("staging.sqlite3")
    }

    func promoteStagingDB(for fingerprint: String) throws -> URL {
        let fileManager = FileManager.default
        let active = activeDBURL(for: fingerprint)
        let staging = stagingDBURL(for: fingerprint)
        try fileManager.createDirectory(at: dbDirectory(for: fingerprint), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: active.path) {
            try fileManager.removeItem(at: active)
        }
        try fileManager.moveItem(at: staging, to: active)
        return active
    }

    private func dbDirectory(for fingerprint: String) -> URL {
        let safeName = String(fingerprint.hashValue, radix: 16)
        return rootURL.appendingPathComponent("indexes/\(safeName)", isDirectory: true)
    }
}
```

- [ ] **Step 4: Add a source-switch coordinator that builds first and swaps second**

Create `Sources/VibeLight/App/SourceSwitchCoordinator.swift`:

```swift
import Foundation

protocol SourceIndexBuilding {
    func buildIndex(at dbPath: String, for resolution: SessionSourceResolution) throws
}

final class SourceSwitchCoordinator {
    private let workspace: SessionIndexWorkspace
    private let builder: SourceIndexBuilding

    init(workspace: SessionIndexWorkspace, builder: SourceIndexBuilding) {
        self.workspace = workspace
        self.builder = builder
    }

    func buildAndSwap(
        to resolution: SessionSourceResolution,
        swap: @escaping @MainActor (SessionIndex) -> Void
    ) {
        Task.detached(priority: .utility) {
            let stagingURL = self.workspace.stagingDBURL(for: resolution.effectiveFingerprint)
            try self.builder.buildIndex(at: stagingURL.path, for: resolution)
            let activeURL = try self.workspace.promoteStagingDB(for: resolution.effectiveFingerprint)
            let index = try SessionIndex(dbPath: activeURL.path)
            await swap(index)
        }
    }
}
```

Update `AppDelegate` so `beginSourceSwitch(to:)` preserves the active runtime until the coordinator hands back a ready `SessionIndex`.

- [ ] **Step 5: Re-run the workspace and coordinator tests**

Run:

```bash
swift test --filter SessionIndexWorkspaceTests
swift test --filter SourceSwitchCoordinatorTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Data/SessionIndexWorkspace.swift Sources/VibeLight/App/SourceSwitchCoordinator.swift Sources/VibeLight/App/AppDelegate.swift Sources/VibeLight/Watchers/IndexScanner.swift Tests/VibeLightTests/SessionIndexWorkspaceTests.swift Tests/VibeLightTests/SourceSwitchCoordinatorTests.swift
git commit -m "feat: switch source indexes atomically"
```

---

### Task 5: Remove timer-driven history re-search and keep only a lightweight visible-live tick

**Files:**
- Modify: `Sources/VibeLight/UI/SearchPanelController.swift`
- Modify: `Sources/VibeLight/Data/SessionIndex.swift`
- Modify: `Sources/VibeLight/App/AppDelegate.swift`
- Create: `Tests/VibeLightTests/SearchPanelControllerRefreshTests.swift`

- [ ] **Step 1: Write the failing refresh-policy tests**

Create `Tests/VibeLightTests/SearchPanelControllerRefreshTests.swift`:

```swift
import Foundation
import Testing
@testable import Flare

@Suite("Search panel refresh policy")
struct SearchPanelControllerRefreshTests {
    @Test("history queries do not arm visible live refresh")
    func historyQueriesDoNotArmVisibleLiveRefresh() {
        let results = [
            SearchResult(
                sessionId: "closed-1",
                tool: "claude",
                title: "Closed",
                project: "/tmp",
                projectName: "tmp",
                gitBranch: "",
                status: "closed",
                startedAt: .distantPast,
                pid: nil,
                tokenCount: 0,
                lastActivityAt: .distantPast,
                activityPreview: nil,
                activityStatus: .closed,
                snippet: nil
            )
        ]

        #expect(SearchPanelController.shouldArmVisibleLiveRefresh(query: "auth bug", results: results) == false)
    }

    @Test("live results can arm visible live refresh")
    func liveResultsCanArmVisibleLiveRefresh() {
        let results = [
            SearchResult(
                sessionId: "live-1",
                tool: "claude",
                title: "Live",
                project: "/tmp",
                projectName: "tmp",
                gitBranch: "",
                status: "live",
                startedAt: .distantPast,
                pid: 42,
                tokenCount: 0,
                lastActivityAt: .distantPast,
                activityPreview: nil,
                activityStatus: .working,
                snippet: nil
            )
        ]

        #expect(SearchPanelController.shouldArmVisibleLiveRefresh(query: "", results: results))
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --filter SearchPanelControllerRefreshTests
```

Expected: FAIL because the helper does not exist and the panel still uses the 500ms full-search timer.

- [ ] **Step 3: Replace the visible refresh timer with a live-only helper**

Update `Sources/VibeLight/UI/SearchPanelController.swift`:

```swift
static func shouldArmVisibleLiveRefresh(query: String, results: [SearchResult]) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty || results.contains(where: { $0.status == "live" }) else {
        return false
    }
    return results.contains { $0.status == "live" }
}
```

Then replace the current full-search timer path with a lightweight row refresh path:

```swift
private func refreshVisibleLiveRows() {
    let liveIDs = results.filter { $0.status == "live" }.map(\.sessionId)
    guard !liveIDs.isEmpty, let sessionIndex else { return }
    let refreshed = (try? sessionIndex.results(sessionIDs: liveIDs)) ?? []
    mergeLiveRows(refreshed)
}
```

- [ ] **Step 4: Add a lightweight `results(sessionIDs:)` API to `SessionIndex`**

Update `Sources/VibeLight/Data/SessionIndex.swift` with:

```swift
func results(sessionIDs: [String]) throws -> [SearchResult] {
    guard !sessionIDs.isEmpty else { return [] }
    let placeholders = sessionIDs.indices.map { _ in "?" }.joined(separator: ",")
    let sql = """
        SELECT
            id, tool, title, project, project_name, git_branch, status, started_at, pid,
            token_count, last_activity_at, last_file_mod, last_entry_type, activity_preview,
            activity_preview_kind, NULL AS snippet, health_status, health_detail,
            effective_model, context_window_tokens, context_used_estimate, context_percent_estimate,
            context_confidence, context_source, last_context_sample_at, last_user_prompt
        FROM sessions
        WHERE id IN (\(placeholders))
    """
    return try db.query(sql, bind: { statement in
        for (offset, id) in sessionIDs.enumerated() {
            try statement.bind(index: Int32(offset + 1), text: id)
        }
    }, map: mapRow)
}
```

This API exists to refresh visible live rows without rerunning transcript FTS for history queries.

- [ ] **Step 5: Re-run the panel refresh and existing preview-mode tests**

Run:

```bash
swift test --filter SearchPanelControllerRefreshTests
swift test --filter SearchPanelControllerPreviewTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/UI/SearchPanelController.swift Sources/VibeLight/Data/SessionIndex.swift Sources/VibeLight/App/AppDelegate.swift Tests/VibeLightTests/SearchPanelControllerRefreshTests.swift
git commit -m "perf: split visible live refresh from history search"
```

---

### Task 6: Move file watching and change handling off the main actor, and stop full codex reindex on metadata changes

**Files:**
- Modify: `Sources/VibeLight/Watchers/FileWatcher.swift`
- Modify: `Sources/VibeLight/Watchers/Indexer.swift`
- Modify: `Sources/VibeLight/Data/SessionIndex.swift`
- Modify: `Tests/VibeLightTests/IndexerLiveRefreshTests.swift`

- [ ] **Step 1: Write the failing metadata-refresh tests**

Extend `Tests/VibeLightTests/IndexerLiveRefreshTests.swift`:

```swift
@Test("codex metadata files do not force full transcript reindex")
func codexMetadataFilesDoNotForceFullTranscriptReindex() {
    let changedPaths = [
        "/Users/me/.codex/session_index.jsonl",
        "/Users/me/.codex/state_5.sqlite",
    ]

    #expect(Indexer.shouldForceFullCodexReindex(forChangedPaths: changedPaths) == false)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --filter IndexerLiveRefreshTests
```

Expected: FAIL because the current indexer still treats codex metadata changes as full reindex triggers.

- [ ] **Step 3: Move the watcher queue and indexer work onto a utility queue**

Update `Sources/VibeLight/Watchers/FileWatcher.swift` so the stream uses a utility queue:

```swift
private let callbackQueue = DispatchQueue(label: "Flare.FileWatcher", qos: .utility)

init(paths: [String], onChange: @escaping ([String]) -> Void) {
    self.paths = paths
    self.onChange = onChange
}

func start() {
    var context = FSEventStreamContext(
        version: 0,
        info: Unmanaged.passUnretained(self).toOpaque(),
        retain: nil,
        release: nil,
        copyDescription: nil
    )
    let callback = fileWatcherCallback
    guard let stream = FSEventStreamCreate(
        kCFAllocatorDefault,
        callback,
        &context,
        paths as CFArray,
        FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
        0.2,
        UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
    ) else { return }
    FSEventStreamSetDispatchQueue(stream, callbackQueue)
}
```

Update `Sources/VibeLight/Watchers/Indexer.swift` so heavy work is enqueued instead of running on the main actor:

```swift
private let workQueue = DispatchQueue(label: "Flare.Indexer", qos: .utility)

private func enqueue(_ operation: @escaping @Sendable () -> Void) {
    workQueue.async(execute: operation)
}
```

- [ ] **Step 4: Replace full codex reindex with targeted metadata updates**

Add targeted update APIs to `SessionIndex.swift`:

```swift
func updateGitBranch(sessionId: String, gitBranch: String) throws {
    try runStatement("UPDATE sessions SET git_branch = ?1 WHERE id = ?2") { statement in
        try statement.bind(index: 1, text: gitBranch)
        try statement.bind(index: 2, text: sessionId)
    }
}

func codexSessionIDs() throws -> [String] {
    try db.query("SELECT id FROM sessions WHERE tool = 'codex'") { statement in
        String(cString: sqlite3_column_text(statement, 0))
    }
}
```

Then change the codex metadata handling path in `Indexer.swift` from:

```swift
if needsCodexReindex {
    codexTitleMap = IndexingHelpers.loadCodexTitleMap(codexRootPath: sourceResolution.codexRootPath)
    reindexAllCodexSessionFiles()
}
```

to:

```swift
if codexTitleMapChanged {
    refreshCodexTitles()
}
if codexStateChanged {
    refreshCodexGitBranches()
}
```

Also remove `titleSweepTimer`; titles should now update incrementally on:

- source file reindex
- `session_index.jsonl` change
- Claude `sessions-index.json` change
- live-session prompt/title refresh

- [ ] **Step 5: Re-run indexer tests**

Run:

```bash
swift test --filter IndexerLiveRefreshTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Watchers/FileWatcher.swift Sources/VibeLight/Watchers/Indexer.swift Sources/VibeLight/Data/SessionIndex.swift Tests/VibeLightTests/IndexerLiveRefreshTests.swift
git commit -m "perf: move indexing off main and make codex metadata refresh targeted"
```

---

### Task 7: Unify session-file lookup and cancel stale preview work

**Files:**
- Create: `Sources/VibeLight/Data/SessionFileLocator.swift`
- Modify: `Sources/VibeLight/UI/SearchPanelController.swift`
- Modify: `Sources/VibeLight/Watchers/Indexer.swift`
- Create: `Tests/VibeLightTests/SessionFileLocatorTests.swift`

- [ ] **Step 1: Write the failing file-locator tests**

Create `Tests/VibeLightTests/SessionFileLocatorTests.swift`:

```swift
import Foundation
import Testing
@testable import Flare

@Test("locator reuses cached file URLs by session id")
func locatorReusesCachedFileURLsBySessionID() async throws {
    let locator = SessionFileLocator()
    let url = URL(fileURLWithPath: "/tmp/s-1.jsonl")

    await locator.record(sessionID: "s-1", fileURL: url)
    let cached = await locator.cachedFileURL(sessionID: "s-1")

    #expect(cached == url)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --filter SessionFileLocatorTests
```

Expected: FAIL because `SessionFileLocator` does not exist.

- [ ] **Step 3: Add a shared cached file locator**

Create `Sources/VibeLight/Data/SessionFileLocator.swift`:

```swift
import Foundation

actor SessionFileLocator {
    private var cache: [String: URL] = [:]

    func record(sessionID: String, fileURL: URL) {
        cache[sessionID] = fileURL
    }

    func cachedFileURL(sessionID: String) -> URL? {
        cache[sessionID]
    }
}
```

Inject the locator into both `Indexer` and `SearchPanelController`, and remove their duplicated filesystem-scanning helpers.

- [ ] **Step 4: Cancel stale preview tasks in `SearchPanelController`**

Update `Sources/VibeLight/UI/SearchPanelController.swift`:

```swift
private var previewTask: Task<Void, Never>?

func webBridge(_ bridge: WebBridge, didRequestPreview sessionId: String) {
    previewTask?.cancel()
    previewTask = Task.detached(priority: .utility) { [weak self] in
        guard !Task.isCancelled else { return }
        guard
            let self,
            let fileURL = await self.sessionFileLocator.fileURL(
                sessionID: sessionId,
                sourceResolution: self.sessionSourceResolution
            ),
            let liveResult = await MainActor.run(body: { self.results.first(where: { $0.sessionId == sessionId }) })
        else {
            return
        }

        let preview = TranscriptTailReader.read(fileURL: fileURL)
        let merged = Self.mergePreviewState(transcriptPreview: preview, with: liveResult)
        let json = Self.previewPayloadToJSONString(
            preview: merged,
            sessionId: sessionId,
            lastActivityAt: liveResult.lastActivityAt
        )

        guard !Task.isCancelled else { return }
        await MainActor.run {
            guard self.isWebViewReady else { return }
            let escaped = self.escapeForSingleQuotedJavaScriptString(json)
            self.webView.evaluateJavaScript("updatePreview('\(escaped)')", completionHandler: nil)
        }
    }
}
```

- [ ] **Step 5: Re-run locator and preview tests**

Run:

```bash
swift test --filter SessionFileLocatorTests
swift test --filter SearchPanelControllerPreviewTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Data/SessionFileLocator.swift Sources/VibeLight/UI/SearchPanelController.swift Sources/VibeLight/Watchers/Indexer.swift Tests/VibeLightTests/SessionFileLocatorTests.swift Tests/VibeLightTests/SearchPanelControllerPreviewTests.swift
git commit -m "perf: share session file lookup and cancel stale previews"
```

---

### Task 8: Make transcript ingestion append-only with fallback to full rebuild only on truncation

**Files:**
- Modify: `Sources/VibeLight/Data/SessionIndex.swift`
- Modify: `Sources/VibeLight/Parsers/ClaudeParser.swift`
- Modify: `Sources/VibeLight/Parsers/CodexParser.swift`
- Modify: `Sources/VibeLight/Watchers/Indexer.swift`
- Modify: `Tests/VibeLightTests/SessionIndexTests.swift`
- Modify: `Tests/VibeLightTests/ClaudeParserTests.swift`
- Modify: `Tests/VibeLightTests/CodexParserTests.swift`

- [ ] **Step 1: Write the failing append-only ingestion tests**

Add to `Tests/VibeLightTests/SessionIndexTests.swift`:

```swift
@Test
func testAppendingTranscriptEntriesDoesNotRewriteExistingRows() throws {
    let (index, dbPath) = try makeTestIndex()
    defer { try? FileManager.default.removeItem(atPath: dbPath) }

    let now = Date()
    try index.appendTranscripts(sessionId: "s1", entries: [
        ("user", "first", now),
        ("assistant", "second", now.addingTimeInterval(1)),
    ])
    try index.appendTranscripts(sessionId: "s1", entries: [
        ("user", "third", now.addingTimeInterval(2)),
    ])

    #expect(try transcriptRowCount(dbPath: dbPath, sessionId: "s1") == 3)
}
```

Add parser-offset tests to `Tests/VibeLightTests/ClaudeParserTests.swift` and `Tests/VibeLightTests/CodexParserTests.swift`:

```swift
@Test("parses only appended records from byte offset")
func parsesOnlyAppendedRecordsFromByteOffset() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent("session.jsonl")

    let original = """
    {"type":"user","message":{"content":[{"type":"text","text":"first"}]}}
    """
    try original.write(to: url, atomically: true, encoding: .utf8)
    let originalLength = UInt64(try Data(contentsOf: url).count)

    let appended = original + "\n" + #"{"type":"assistant","message":{"content":[{"type":"text","text":"second"}]}}"#
    try appended.write(to: url, atomically: true, encoding: .utf8)

    let parsed = try ClaudeParser.parseSessionFile(url: url, startingAtOffset: originalLength)
    #expect(parsed.messages.count == 1)
}
```

- [ ] **Step 2: Run the parser and index tests to verify they fail**

Run:

```bash
swift test --filter SessionIndexTests
swift test --filter ClaudeParserTests
swift test --filter CodexParserTests
```

Expected: FAIL because append-only APIs and offset-based parser entry points do not exist.

- [ ] **Step 3: Add file-ingestion state and append-only transcript APIs**

Extend `SessionIndex.swift` with a new table:

```swift
CREATE TABLE IF NOT EXISTS indexed_files (
    session_id TEXT PRIMARY KEY,
    file_path TEXT NOT NULL,
    last_offset INTEGER NOT NULL,
    last_size INTEGER NOT NULL,
    last_mtime REAL
)
```

Add the new APIs:

```swift
struct IndexedFileState: Equatable {
    let sessionId: String
    let filePath: String
    let lastOffset: UInt64
    let lastSize: UInt64
    let lastMtime: Date?
}

func indexedFileState(sessionId: String) throws -> IndexedFileState? {
    let rows = try db.query(
        "SELECT session_id, file_path, last_offset, last_size, last_mtime FROM indexed_files WHERE session_id = ?1",
        bind: { try $0.bind(index: 1, text: sessionId) }
    ) { statement in
        IndexedFileState(
            sessionId: String(cString: sqlite3_column_text(statement, 0)),
            filePath: String(cString: sqlite3_column_text(statement, 1)),
            lastOffset: UInt64(sqlite3_column_int64(statement, 2)),
            lastSize: UInt64(sqlite3_column_int64(statement, 3)),
            lastMtime: sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil
                : Date(timeIntervalSince1970: sqlite3_column_double(statement, 4))
        )
    }
    return rows.first
}

func upsertIndexedFileState(_ state: IndexedFileState) throws {
    try runStatement("""
        INSERT INTO indexed_files (session_id, file_path, last_offset, last_size, last_mtime)
        VALUES (?1, ?2, ?3, ?4, ?5)
        ON CONFLICT(session_id) DO UPDATE SET
            file_path = excluded.file_path,
            last_offset = excluded.last_offset,
            last_size = excluded.last_size,
            last_mtime = excluded.last_mtime
    """) { statement in
        try statement.bind(index: 1, text: state.sessionId)
        try statement.bind(index: 2, text: state.filePath)
        try statement.bind(index: 3, int: Int64(state.lastOffset))
        try statement.bind(index: 4, int: Int64(state.lastSize))
        if let lastMtime = state.lastMtime {
            try statement.bind(index: 5, double: lastMtime.timeIntervalSince1970)
        } else {
            try statement.bindNull(index: 5)
        }
    }
}

func appendTranscripts(sessionId: String, entries: [(role: String, content: String, timestamp: Date)]) throws {
    let sql = "INSERT INTO transcripts (session_id, role, content, timestamp_str) VALUES (?1, ?2, ?3, ?4)"
    try db.transaction {
        for entry in entries {
            try runStatement(sql) { statement in
                try statement.bind(index: 1, text: sessionId)
                try statement.bind(index: 2, text: entry.role)
                try statement.bind(index: 3, text: entry.content)
                try statement.bind(index: 4, text: makeTimestampString(from: entry.timestamp))
            }
        }
    }
}
```

- [ ] **Step 4: Add offset-based parser entry points and wire `Indexer` to use them**

Add parser result shapes:

```swift
struct IncrementalParseResult {
    let messages: [ParsedMessage]
    let nextOffset: UInt64
    let requiresFullRebuild: Bool
}
```

Expose:

```swift
static func parseSessionFile(url: URL, startingAtOffset: UInt64) throws -> IncrementalParseResult
```

Then change `Indexer` so it does:

```swift
if fileShrank || fileWasRewritten {
    rebuildIndexedSessionFile(path: path, sessionId: sessionId, tool: tool)
} else {
    let incremental = try ClaudeParser.parseSessionFile(url: fileURL, startingAtOffset: state.lastOffset)
    let newEntries = incremental.messages.map {
        (role: $0.role, content: IndexingHelpers.searchableContent(from: $0), timestamp: $0.timestamp)
    }
    try sessionIndex.appendTranscripts(sessionId: sessionId, entries: newEntries)
    try sessionIndex.upsertIndexedFileState(
        IndexedFileState(
            sessionId: sessionId,
            filePath: path,
            lastOffset: incremental.nextOffset,
            lastSize: UInt64((try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?.uint64Value ?? 0),
            lastMtime: IndexingHelpers.fileMtime(at: path)
        )
    )
}
```

- [ ] **Step 5: Re-run parser and index tests**

Run:

```bash
swift test --filter SessionIndexTests
swift test --filter ClaudeParserTests
swift test --filter CodexParserTests
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Sources/VibeLight/Data/SessionIndex.swift Sources/VibeLight/Parsers/ClaudeParser.swift Sources/VibeLight/Parsers/CodexParser.swift Sources/VibeLight/Watchers/Indexer.swift Tests/VibeLightTests/SessionIndexTests.swift Tests/VibeLightTests/ClaudeParserTests.swift Tests/VibeLightTests/CodexParserTests.swift
git commit -m "perf: make transcript ingestion append-only"
```

---

### Task 9: Run the full regression pass and manual smoke checks

**Files:**
- No code changes expected

- [ ] **Step 1: Run the focused regression suite**

Run:

```bash
swift test --filter SettingsStoreTests
swift test --filter SessionSourceConfigurationTests
swift test --filter PreferencesWindowControllerTests
swift test --filter AppSettingsChangeSetTests
swift test --filter SessionIndexWorkspaceTests
swift test --filter SourceSwitchCoordinatorTests
swift test --filter SearchPanelControllerRefreshTests
swift test --filter SearchPanelControllerPreviewTests
swift test --filter IndexerLiveRefreshTests
swift test --filter SessionFileLocatorTests
swift test --filter SessionIndexTests
swift test --filter ClaudeParserTests
swift test --filter CodexParserTests
```

Expected: PASS.

- [ ] **Step 2: Run the full test suite**

Run:

```bash
swift test
```

Expected: PASS.

- [ ] **Step 3: Manual smoke the runtime behaviors**

Run:

```bash
swift run Flare
```

Verify manually:

- Preferences opens immediately and renders as a single-page window.
- Theme/history/hotkey still save immediately.
- Editing Claude/Codex source fields does not touch runtime until `Apply Source Changes`.
- Invalid source with no fallback shows a warning and leaves current results intact.
- Switching source keeps the old search results until the new index is ready.
- Empty-query live view still animates and updates.
- Non-empty history query no longer “breathes” or re-searches on a timer.
- Hover/dwell preview still works and does not lag when moving selection quickly.

- [ ] **Step 4: Capture post-change measurements**

Run:

```bash
ACTIVE_DB="$(find "$HOME/Library/Application Support/Flare/indexes" -name active.sqlite3 -print | head -n 1)"
printf '%s\n' "$ACTIVE_DB"
sqlite3 "$ACTIVE_DB" "select count(*) from sessions;"
sqlite3 "$ACTIVE_DB" "select count(*) from transcripts;"
```

Expected: counts look sane for the active source, and no destructive clear/rebuild happened during normal preferences editing.

---

## Execution Notes

- Land Tasks 1-4 before Tasks 5-8. Preferences rescue and source-switch safety reduce the risk of doing the deeper performance work on an unstable runtime seam.
- Do not implement Task 8 before Task 6. Append-only ingestion is much easier to reason about once the indexer no longer performs full codex rebuilds from metadata-only changes.
- Keep `history` and `live` refresh paths distinct all the way through review. Any change that makes transcript FTS run on a timer again is a regression.

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-18-performance-and-preferences-refinement.md`.

Two execution options:

**1. Subagent-Driven (recommended)** - I dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
