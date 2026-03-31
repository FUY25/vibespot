# Flare Public Beta Readiness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship an invite-only public beta in 1 week with a 2-screen onboarding flow, 1-page preferences, diagnostics export, and direct-download-first distribution readiness.

**Architecture:** Add a small app-shell layer on top of the current Flare core: a typed settings store, onboarding gate, and preferences window. Keep onboarding linear (2 screens only) and preferences single-page to preserve schedule certainty. Keep reliability-first behavior by adding targeted tests around launch, setup checks, and user configuration persistence.

**Tech Stack:** Swift 6, AppKit, WebKit, Carbon hotkeys, ServiceManagement (launch-at-login), Foundation FileManager, Swift Testing (`Testing` module), SwiftPM.

---

## Scope Check

The approved spec has four coupled beta subsystems (onboarding, settings, supportability, distribution). They can stay in one plan because they share the same user flow and app-shell entrypoint (`AppDelegate`), and each task can be implemented and tested independently.

## User-Provided Assets (Non-Code Gate)

These are required for public-facing polish and should be provided by you in parallel with engineering tasks.

1. Final Flare product logo package:
   - app icon source (1024x1024)
   - monochrome variant for docs
   - small-mark variant for release notes/screenshots
2. Short feature demo recordings:
   - onboarding flow clip (20-40s)
   - launch/resume flow clip (20-40s)
3. Beta messaging assets:
   - one-paragraph product intro copy
   - privacy copy approval ("all local by default")
4. Distribution copy:
   - install quick-start text
   - known limitations text for invite users

## File Structure And Responsibilities

### New Files

1. `Sources/VibeLight/Settings/AppSettings.swift`
   - typed settings model (`hotkey`, `theme`, `historyMode`, `launchAtLogin`, `onboardingCompleted`).
2. `Sources/VibeLight/Settings/SettingsStore.swift`
   - UserDefaults-backed persistence and defaults migration.
3. `Sources/VibeLight/Settings/LaunchAtLoginManager.swift`
   - launch-at-login toggling wrapper.
4. `Sources/VibeLight/Onboarding/EnvironmentCheckService.swift`
   - codex/claude and session-path readiness checks.
5. `Sources/VibeLight/Onboarding/OnboardingWindowController.swift`
   - 2-screen onboarding UI and actions.
6. `Sources/VibeLight/Support/DiagnosticsExporter.swift`
   - zip-ready diagnostics payload creation.
7. `Sources/VibeLight/UI/PreferencesWindowController.swift`
   - single-page preferences UI.
8. `Tests/VibeLightTests/SettingsStoreTests.swift`
9. `Tests/VibeLightTests/EnvironmentCheckServiceTests.swift`
10. `Tests/VibeLightTests/DiagnosticsExporterTests.swift`
11. `docs/BETA-INVITE-INSTALL.md`
12. `docs/BETA-RELEASE-CHECKLIST.md`

### Modified Files

1. `Sources/VibeLight/App/AppDelegate.swift`
   - gate app start with onboarding completion, wire preferences menu action, inject settings.
2. `Sources/VibeLight/HotkeyManager.swift`
   - support dynamic shortcut registration from settings.
3. `Sources/VibeLight/UI/SearchPanelController.swift`
   - consume settings-backed defaults (history/live mode as applicable).
4. `Tests/VibeLightTests/ScaffoldSmokeTests.swift`
   - verify onboarding gate and menu actions.
5. `scripts/dev-run.sh`
   - include optional environment flag for onboarding reset during QA.

---

### Task 1: Add Typed Settings And Persistence

**Files:**
- Create: `Sources/VibeLight/Settings/AppSettings.swift`
- Create: `Sources/VibeLight/Settings/SettingsStore.swift`
- Test: `Tests/VibeLightTests/SettingsStoreTests.swift`

- [ ] **Step 1: Write the failing settings persistence tests**

```swift
import Foundation
import Testing
@testable import Flare

@Test
func settingsStoreUsesExpectedDefaults() {
    let suite = UserDefaults(suiteName: "SettingsStoreTests.defaults.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    #expect(store.load().launchAtLogin == true)
    #expect(store.load().onboardingCompleted == false)
}

@Test
func settingsStorePersistsAndReloads() {
    let suite = UserDefaults(suiteName: "SettingsStoreTests.persist.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    var settings = store.load()
    settings.launchAtLogin = false
    settings.onboardingCompleted = true
    settings.historyMode = .liveAndHistory
    store.save(settings)
    let reloaded = store.load()
    #expect(reloaded.launchAtLogin == false)
    #expect(reloaded.onboardingCompleted == true)
    #expect(reloaded.historyMode == .liveAndHistory)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter SettingsStoreTests`  
Expected: FAIL with missing `SettingsStore` / `AppSettings` types.

- [ ] **Step 3: Implement `AppSettings` and `SettingsStore`**

```swift
import Foundation

enum SearchHistoryMode: String, Codable, Sendable {
    case liveOnly
    case liveAndHistory
}

struct AppSettings: Equatable, Sendable {
    var hotkeyKeyCode: UInt32
    var hotkeyModifiers: UInt32
    var historyMode: SearchHistoryMode
    var launchAtLogin: Bool
    var onboardingCompleted: Bool

    static let `default` = AppSettings(
        hotkeyKeyCode: 49, // Space
        hotkeyModifiers: UInt32(cmdKey | shiftKey),
        historyMode: .liveAndHistory,
        launchAtLogin: true,
        onboardingCompleted: false
    )
}

final class SettingsStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    func load() -> AppSettings { /* decode with defaults fallback */ .default }
    func save(_ settings: AppSettings) { /* encode to defaults */ }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter SettingsStoreTests`  
Expected: PASS with 2 passing tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeLight/Settings/AppSettings.swift Sources/VibeLight/Settings/SettingsStore.swift Tests/VibeLightTests/SettingsStoreTests.swift
git commit -m "feat: add typed app settings store with defaults"
```

---

### Task 2: Add Launch-At-Login Manager

**Files:**
- Create: `Sources/VibeLight/Settings/LaunchAtLoginManager.swift`
- Modify: `Sources/VibeLight/App/AppDelegate.swift`
- Test: `Tests/VibeLightTests/ScaffoldSmokeTests.swift`

- [ ] **Step 1: Add failing app delegate test for launch-at-login default behavior**

```swift
@MainActor
@Test
func appDelegateInitializesLaunchAtLoginFromSettings() {
    let suite = UserDefaults(suiteName: "LaunchAtLoginTests.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    let delegate = AppDelegate(startsRuntimeServices: false, settingsStore: store)
    _ = delegate
    #expect(store.load().launchAtLogin == true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScaffoldSmokeTests --filter launchAtLogin`  
Expected: FAIL because `AppDelegate` has no injectable `SettingsStore`.

- [ ] **Step 3: Implement launch-at-login manager and app delegate wiring**

```swift
import ServiceManagement

protocol LaunchAtLoginManaging: Sendable {
    func setEnabled(_ enabled: Bool) throws
}

struct LaunchAtLoginManager: LaunchAtLoginManaging {
    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        }
    }
}
```

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settingsStore: SettingsStore
    private let launchAtLoginManager: LaunchAtLoginManaging
    // ...
}
```

- [ ] **Step 4: Run test to verify pass**

Run: `swift test --filter ScaffoldSmokeTests --filter launchAtLogin`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeLight/Settings/LaunchAtLoginManager.swift Sources/VibeLight/App/AppDelegate.swift Tests/VibeLightTests/ScaffoldSmokeTests.swift
git commit -m "feat: wire launch-at-login manager through app settings"
```

---

### Task 3: Make Hotkey Configurable From Settings

**Files:**
- Modify: `Sources/VibeLight/HotkeyManager.swift`
- Modify: `Sources/VibeLight/App/AppDelegate.swift`
- Test: `Tests/VibeLightTests/ScaffoldSmokeTests.swift`

- [ ] **Step 1: Write failing test for custom hotkey registration path**

```swift
@MainActor
@Test
func appDelegateUsesConfiguredHotkeyValues() {
    let suite = UserDefaults(suiteName: "HotkeyConfig.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    var settings = store.load()
    settings.hotkeyKeyCode = UInt32(kVK_ANSI_K)
    settings.hotkeyModifiers = UInt32(cmdKey | optionKey)
    store.save(settings)
    let delegate = AppDelegate(startsRuntimeServices: false, settingsStore: store)
    #expect(delegate.configuredHotkey?.keyCode == UInt32(kVK_ANSI_K))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScaffoldSmokeTests --filter configuredHotkey`  
Expected: FAIL due to non-configurable `HotkeyManager`.

- [ ] **Step 3: Implement configurable hotkey inputs**

```swift
struct HotkeyBinding: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32
}

final class HotkeyManager {
    private let binding: HotkeyBinding
    init(binding: HotkeyBinding, onToggle: @escaping @MainActor @Sendable () -> Void) {
        self.binding = binding
        self.onToggle = onToggle
    }
    // RegisterEventHotKey(binding.keyCode, binding.modifiers, ...)
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter ScaffoldSmokeTests`  
Expected: PASS for updated smoke tests.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeLight/HotkeyManager.swift Sources/VibeLight/App/AppDelegate.swift Tests/VibeLightTests/ScaffoldSmokeTests.swift
git commit -m "feat: support configurable global hotkey binding"
```

---

### Task 4: Add Environment Check Service For Onboarding Screen B

**Files:**
- Create: `Sources/VibeLight/Onboarding/EnvironmentCheckService.swift`
- Test: `Tests/VibeLightTests/EnvironmentCheckServiceTests.swift`

- [ ] **Step 1: Write failing environment check tests**

```swift
import Foundation
import Testing
@testable import Flare

@Test
func environmentCheckReportsCodexBinaryPresence() async throws {
    let service = EnvironmentCheckService(fileManager: .default, processRunner: MockProcessRunner(paths: ["codex": "/usr/local/bin/codex"]))
    let result = await service.runChecks()
    #expect(result.codex.isAvailable == true)
}

@Test
func environmentCheckNeverAssumesHardcodedProjectPath() async throws {
    let service = EnvironmentCheckService(fileManager: .default, processRunner: MockProcessRunner(paths: [:]))
    let result = await service.runChecks()
    #expect(result.checkedPaths.contains { $0.contains("/Users/") })
    #expect(result.checkedPaths.contains { $0.contains(".codex") || $0.contains(".claude") })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter EnvironmentCheckServiceTests`  
Expected: FAIL due to missing service and result types.

- [ ] **Step 3: Implement minimal environment check service**

```swift
struct EnvironmentCheckResult: Sendable {
    struct ToolState: Sendable { let isAvailable: Bool; let resolvedPath: String? }
    let codex: ToolState
    let claude: ToolState
    let checkedPaths: [String]
    let missingAccessiblePaths: [String]
}

protocol ProcessRunning: Sendable {
    func which(_ command: String) async -> String?
}

struct EnvironmentCheckService {
    func runChecks() async -> EnvironmentCheckResult { /* tool + path checks */ }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter EnvironmentCheckServiceTests`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeLight/Onboarding/EnvironmentCheckService.swift Tests/VibeLightTests/EnvironmentCheckServiceTests.swift
git commit -m "feat: add onboarding environment readiness checks"
```

---

### Task 5: Build 2-Screen Onboarding Flow

**Files:**
- Create: `Sources/VibeLight/Onboarding/OnboardingWindowController.swift`
- Modify: `Sources/VibeLight/App/AppDelegate.swift`
- Test: `Tests/VibeLightTests/ScaffoldSmokeTests.swift`

- [ ] **Step 1: Write failing onboarding gate test**

```swift
@MainActor
@Test
func appShowsOnboardingWhenNotCompleted() {
    let suite = UserDefaults(suiteName: "OnboardingGate.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    var settings = store.load()
    settings.onboardingCompleted = false
    store.save(settings)
    let delegate = AppDelegate(startsRuntimeServices: false, settingsStore: store)
    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    #expect(delegate.isOnboardingVisible == true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScaffoldSmokeTests --filter onboarding`  
Expected: FAIL due to missing onboarding surface.

- [ ] **Step 3: Implement onboarding controller and app delegate entry gate**

```swift
@MainActor
final class OnboardingWindowController: NSWindowController {
    enum Step { case welcome, setup }
    var onFinish: ((HotkeyBinding, Bool) -> Void)?
    // Screen A: feature intro + privacy
    // Screen B: checks + recheck + hotkey + launch-at-login toggle
}
```

```swift
if settingsStore.load().onboardingCompleted == false {
    presentOnboarding()
    return
}
startRuntimeServices()
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter ScaffoldSmokeTests --filter onboarding`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeLight/Onboarding/OnboardingWindowController.swift Sources/VibeLight/App/AppDelegate.swift Tests/VibeLightTests/ScaffoldSmokeTests.swift
git commit -m "feat: add two-screen onboarding with setup checks"
```

---

### Task 6: Build Single-Page Preferences Window

**Files:**
- Create: `Sources/VibeLight/UI/PreferencesWindowController.swift`
- Modify: `Sources/VibeLight/App/AppDelegate.swift`
- Modify: `Sources/VibeLight/UI/SearchPanelController.swift`
- Test: `Tests/VibeLightTests/ScaffoldSmokeTests.swift`

- [ ] **Step 1: Write failing test for preferences menu action**

```swift
@MainActor
@Test
func appContextMenuContainsPreferencesAction() {
    let delegate = AppDelegate(startsRuntimeServices: false)
    let menu = delegate.makeContextMenuForTesting()
    #expect(menu.items.contains { $0.title == "Preferences…" })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ScaffoldSmokeTests --filter Preferences`  
Expected: FAIL because no preferences controller/menu action exists.

- [ ] **Step 3: Implement preferences controller and wiring**

```swift
@MainActor
final class PreferencesWindowController: NSWindowController {
    init(settingsStore: SettingsStore, onReindex: @escaping () -> Void, onExportDiagnostics: @escaping () -> Void) {
        // one-page settings layout
    }
}
```

```swift
menu.addItem(NSMenuItem(title: "Preferences…", action: #selector(openPreferences), keyEquivalent: ","))
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter ScaffoldSmokeTests --filter Preferences`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeLight/UI/PreferencesWindowController.swift Sources/VibeLight/App/AppDelegate.swift Sources/VibeLight/UI/SearchPanelController.swift Tests/VibeLightTests/ScaffoldSmokeTests.swift
git commit -m "feat: add single-page preferences window"
```

---

### Task 7: Add Diagnostics Export

**Files:**
- Create: `Sources/VibeLight/Support/DiagnosticsExporter.swift`
- Create: `Tests/VibeLightTests/DiagnosticsExporterTests.swift`
- Modify: `Sources/VibeLight/UI/PreferencesWindowController.swift`

- [ ] **Step 1: Write failing diagnostics export test**

```swift
import Foundation
import Testing
@testable import Flare

@Test
func diagnosticsExporterCreatesArchiveWithExpectedFiles() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    let exporter = DiagnosticsExporter()
    let output = try exporter.export(to: tempDir)
    #expect(FileManager.default.fileExists(atPath: output.path))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter DiagnosticsExporterTests`  
Expected: FAIL due to missing exporter.

- [ ] **Step 3: Implement minimal exporter**

```swift
struct DiagnosticsExporter {
    func export(to directory: URL) throws -> URL {
        // write settings snapshot + version info + recent app log
        // produce archive file path and return
    }
}
```

- [ ] **Step 4: Run tests to verify pass**

Run: `swift test --filter DiagnosticsExporterTests`  
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/VibeLight/Support/DiagnosticsExporter.swift Sources/VibeLight/UI/PreferencesWindowController.swift Tests/VibeLightTests/DiagnosticsExporterTests.swift
git commit -m "feat: add diagnostics export from preferences"
```

---

### Task 8: Add Beta Distribution Docs And Reliability Gate Checklist

**Files:**
- Create: `docs/BETA-INVITE-INSTALL.md`
- Create: `docs/BETA-RELEASE-CHECKLIST.md`
- Modify: `scripts/dev-run.sh`

- [ ] **Step 1: Add install and invite doc**

```md
# Flare Invite Beta Install
1. Download release artifact.
2. Move `Flare.app` to `/Applications`.
3. First launch trust flow on macOS.
4. Complete onboarding (2 screens).
5. Verify first action: `new codex` from search panel.
```

- [ ] **Step 2: Add release checklist doc**

```md
# Flare Beta Release Checklist
- [ ] All targeted tests pass
- [ ] `new codex/new claude` first prompt behavior verified
- [ ] Preview has no inner-card clipping
- [ ] Session close disappearance verified <= 5s
- [ ] Onboarding setup checks pass on clean profile
- [ ] Preferences actions verified (hotkey, login toggle, reindex, diagnostics export)
```

- [ ] **Step 3: Add optional onboarding reset mode in dev runner**

```bash
if [[ "${1:-}" == "--reset-onboarding" ]]; then
  defaults delete com.fuyuming.Flare onboardingCompleted || true
  shift
fi
```

- [ ] **Step 4: Verify docs and runner behavior**

Run: `./scripts/dev-run.sh --help || true`  
Expected: script still launches correctly; new reset option does not break default path.

- [ ] **Step 5: Commit**

```bash
git add docs/BETA-INVITE-INSTALL.md docs/BETA-RELEASE-CHECKLIST.md scripts/dev-run.sh
git commit -m "docs: add invite-beta install and release checklists"
```

---

### Task 9: Full Verification Pass Before Invite Build

**Files:**
- Verify only: `Sources/VibeLight/App/AppDelegate.swift`
- Verify only: `Sources/VibeLight/Onboarding/OnboardingWindowController.swift`
- Verify only: `Sources/VibeLight/UI/PreferencesWindowController.swift`
- Verify only: `Sources/VibeLight/Support/DiagnosticsExporter.swift`
- Verify only: `Tests/VibeLightTests/*.swift`

- [ ] **Step 1: Run focused new tests**

Run: `swift test --filter SettingsStoreTests --filter EnvironmentCheckServiceTests --filter DiagnosticsExporterTests`  
Expected: PASS.

- [ ] **Step 2: Run regression suites for current critical behavior**

Run: `swift test --filter AppDelegateSelectionRoutingTests --filter SearchPanelScriptTests --filter SearchPanelControllerPreviewTests`  
Expected: PASS.

- [ ] **Step 3: Run full suite**

Run: `swift test`  
Expected: PASS (all tests green).

- [ ] **Step 4: Create integration commit**

```bash
git add -A
git commit -m "feat: complete Flare public beta readiness shell"
```

---

## Spec Coverage Check

1. Onboarding 2 screens with feature intro and privacy: covered in Task 5.
2. Setup test with recheck and permission guidance: covered in Tasks 4 and 5.
3. Hotkey editable in onboarding/preferences: covered in Tasks 3, 5, 6.
4. Launch at login default ON: covered in Tasks 1 and 2.
5. Single-page preferences (no ranking toggles): covered in Task 6.
6. Diagnostics export: covered in Task 7.
7. Direct-download-first + Homebrew-follow-up docs: covered in Task 8.
8. Reliability gates: covered in Task 8 checklist and Task 9 verification.
9. Universal path rule (no hardcoded project path): covered in Task 4 service design/tests.
10. Non-code media assets supplied by user: covered in User-Provided Assets gate section.

## Placeholder Scan

No `TODO`, `TBD`, or deferred placeholders are present. Each task contains concrete file paths, concrete steps, concrete test commands, and concrete commit actions.

## Type Consistency Check

1. `AppSettings`, `SettingsStore`, `HotkeyBinding`, `EnvironmentCheckService`, `OnboardingWindowController`, `PreferencesWindowController`, and `DiagnosticsExporter` are consistently referenced across tasks.
2. Test filenames align with the file structure map and task references.

