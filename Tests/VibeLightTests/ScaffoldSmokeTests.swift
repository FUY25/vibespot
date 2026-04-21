import AppKit
import Carbon
import Testing
@testable import Flare

@MainActor
private func withRestoredSharedApplicationState<Result>(
    _ app: NSApplication,
    _ body: (NSApplication) -> Result
) -> Result {
    let originalActivationPolicy = app.activationPolicy()
    let originalDelegate = app.delegate

    defer {
        _ = app.setActivationPolicy(originalActivationPolicy)
        app.delegate = originalDelegate
    }

    return body(app)
}

@MainActor
@Test
func configuresMenuBarApplicationActivationPolicy() {
    let app = NSApplication.shared

    withRestoredSharedApplicationState(app) { app in
        _ = app.setActivationPolicy(.regular)

        let delegate = AppDelegate()
        configureApplication(app, delegate: delegate)

        #expect(app.activationPolicy() == .accessory)
        #expect(app.delegate === delegate)
    }
}

@MainActor
@Test
func createsMenuBarStatusItemLogoWhenLaunching() {
    let delegate = AppDelegate(startsRuntimeServices: false)

    defer {
        delegate.removeStatusItem()
    }

    #expect(delegate.statusItemTitle == nil)

    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

    #expect(delegate.statusItemImage != nil)
}

@MainActor
@Test
func appDelegateUsesConfiguredHotkeyBinding() {
    let suite = UserDefaults(suiteName: "AppDelegate.hotkey.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    var settings = store.load()
    settings.hotkeyKeyCode = UInt32(kVK_ANSI_K)
    settings.hotkeyModifiers = UInt32(cmdKey | optionKey)
    store.save(settings)

    let delegate = AppDelegate(startsRuntimeServices: false, settingsStore: store)
    #expect(delegate.configuredHotkeyBinding == HotkeyBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | optionKey)))
}

@MainActor
@Test
func appContextMenuContainsPreferencesAction() {
    let delegate = AppDelegate(startsRuntimeServices: false)
    let menu = delegate.makeContextMenuForTesting()

    #expect(menu.items.contains { $0.title == "Preferences…" })
}

@MainActor
@Test
func appContextMenuUsesVibeSpotQuitBranding() {
    let delegate = AppDelegate(startsRuntimeServices: false)
    let menu = delegate.makeContextMenuForTesting()

    #expect(menu.items.contains { $0.title == "Quit VibeSpot" })
    #expect(menu.items.contains { $0.title == "Quit Flare" } == false)
}

@MainActor
@Test
func appDelegateOpensPreferencesWindow() {
    let delegate = AppDelegate(startsRuntimeServices: false)

    delegate.openPreferences()

    #expect(delegate.isPreferencesVisible)
}

@MainActor
@Test
func appDelegateAppliesLaunchAtLoginSettingOnLaunch() {
    final class LaunchAtLoginSpy: LaunchAtLoginManaging {
        var enabledValues: [Bool] = []
        var isSupportedRuntime: Bool = true
        func setEnabled(_ enabled: Bool) throws {
            enabledValues.append(enabled)
        }
    }

    let suite = UserDefaults(suiteName: "AppDelegate.launchAtLogin.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    var settings = store.load()
    settings.launchAtLogin = false
    store.save(settings)

    let spy = LaunchAtLoginSpy()
    let delegate = AppDelegate(
        startsRuntimeServices: false,
        settingsStore: store,
        launchAtLoginManager: spy
    )
    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

    #expect(spy.enabledValues == [false])
}

@MainActor
@Test
func appDelegateSurfacesLaunchAtLoginApplyFailuresInPreferences() throws {
    struct LaunchFailure: LocalizedError {
        var errorDescription: String? { "ServiceManagement rejected the request." }
    }

    final class LaunchAtLoginFailingSpy: LaunchAtLoginManaging {
        var isSupportedRuntime: Bool = true
        func setEnabled(_ enabled: Bool) throws {
            throw LaunchFailure()
        }
    }

    let suite = UserDefaults(suiteName: "AppDelegate.launchAtLoginFailure.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    var initialSettings = store.load()
    initialSettings.launchAtLogin = false
    store.save(initialSettings)
    let delegate = AppDelegate(
        startsRuntimeServices: false,
        settingsStore: store,
        launchAtLoginManager: LaunchAtLoginFailingSpy()
    )
    delegate.openPreferences()
    let window = try #require(delegate.preferencesWindowForTesting)

    let toggle = try #require(findSwitch(in: window.contentView))
    toggle.performClick(nil)

    #expect(delegate.preferencesStatusMessageForTesting?.localizedCaseInsensitiveContains("launch at login") == true)
    #expect(delegate.preferencesStatusMessageForTesting?.localizedCaseInsensitiveContains("rejected") == true)
}

@MainActor
@Test
func appShowsOnboardingWhenNotCompleted() {
    let suite = UserDefaults(suiteName: "AppDelegate.onboarding.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    var settings = store.load()
    settings.onboardingCompleted = false
    store.save(settings)

    let delegate = AppDelegate(startsRuntimeServices: false, settingsStore: store)
    defer {
        delegate.removeStatusItem()
    }

    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

    #expect(delegate.isOnboardingVisible)
}

@MainActor
@Test
func appDelegatePresentsRecoveryGuidanceWhenIndexStartupFails() {
    struct IndexFailure: LocalizedError {
        var errorDescription: String? { "database disk image is malformed" }
    }

    var presentedTitle: String?
    var presentedMessage: String?
    let suite = UserDefaults(suiteName: "AppDelegate.indexStartupFailure.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    var settings = store.load()
    settings.onboardingCompleted = true
    store.save(settings)
    let delegate = AppDelegate(
        startsRuntimeServices: true,
        settingsStore: store,
        sessionIndexFactory: {
            throw IndexFailure()
        },
        failurePresenter: { title, message in
            presentedTitle = title
            presentedMessage = message
        }
    )
    defer {
        delegate.removeStatusItem()
    }

    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))

    #expect(presentedTitle == "Index Unavailable")
    #expect(presentedMessage?.localizedCaseInsensitiveContains("reindex sessions") == true)
    #expect(presentedMessage?.localizedCaseInsensitiveContains("malformed") == true)
}

@MainActor
@Test
func appDelegateCanRecoverFromIndexStartupFailureByReindexing() async throws {
    struct IndexFailure: LocalizedError {
        var errorDescription: String? { "database disk image is malformed" }
    }

    let suite = UserDefaults(suiteName: "AppDelegate.indexStartupRecovery.\(UUID().uuidString)")!
    let store = SettingsStore(defaults: suite)
    var settings = store.load()
    settings.onboardingCompleted = true
    store.save(settings)

    let dbPath = FileManager.default.temporaryDirectory
        .appendingPathComponent("index-startup-recovery-\(UUID().uuidString).sqlite3")
        .path

    let delegate = AppDelegate(
        startsRuntimeServices: true,
        settingsStore: store,
        sourceSwitchHandler: { _, onReady in
            let readyIndex = try SessionIndex(dbPath: dbPath)
            let now = Date(timeIntervalSince1970: 1_700_000_000)
            try readyIndex.upsertSession(
                id: "recovered-session",
                tool: "codex",
                title: "Recovered Session",
                project: "/tmp/recovered",
                projectName: "recovered",
                gitBranch: "main",
                status: "closed",
                startedAt: now,
                pid: nil,
                lastActivityAt: now
            )
            await onReady(readyIndex)
        },
        sessionIndexFactory: {
            throw IndexFailure()
        }
    )
    defer {
        delegate.removeStatusItem()
        try? FileManager.default.removeItem(atPath: dbPath)
    }

    delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
    #expect(delegate.runtimeServicesStartedForTesting == false)

    #expect(delegate.performReindexForTesting() == "Reindex started")
    await delegate.waitForRecoveryReindexForTesting()

    #expect(delegate.runtimeServicesStartedForTesting)
    #expect(delegate.hasIndexerForTesting)
}

@MainActor
@Test
func restoresSharedApplicationStateAfterConfigurationCheck() {
    let app = NSApplication.shared
    let originalActivationPolicy = app.activationPolicy()
    let originalDelegate = app.delegate

    withRestoredSharedApplicationState(app) { app in
        _ = app.setActivationPolicy(.regular)
        app.delegate = nil

        let delegate = AppDelegate()
        configureApplication(app, delegate: delegate)

        #expect(app.activationPolicy() == .accessory)
        #expect(app.delegate === delegate)
    }

    #expect(app.activationPolicy() == originalActivationPolicy)
    #expect(app.delegate === originalDelegate)
}

@MainActor
private func findSwitch(in view: NSView?) -> NSSwitch? {
    guard let view else { return nil }
    if let toggle = view as? NSSwitch {
        return toggle
    }

    for subview in view.subviews {
        if let toggle = findSwitch(in: subview) {
            return toggle
        }
    }

    return nil
}
