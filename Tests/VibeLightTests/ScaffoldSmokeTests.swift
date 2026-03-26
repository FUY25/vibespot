import AppKit
import Testing
@testable import VibeLight

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

@Test
func scaffoldCompiles() {
    #expect(Bool(true))
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
