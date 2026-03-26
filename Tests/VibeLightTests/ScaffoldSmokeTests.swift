import AppKit
import Testing
@testable import VibeLight

@Test
func scaffoldCompiles() {
    #expect(Bool(true))
}

@MainActor
@Test
func configuresMenuBarApplicationActivationPolicy() {
    let app = NSApplication.shared
    _ = app.setActivationPolicy(.regular)

    let delegate = AppDelegate()

    configureApplication(app, delegate: delegate)

    #expect(app.activationPolicy() == .accessory)
    #expect(app.delegate === delegate)
}
