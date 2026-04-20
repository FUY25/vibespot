import AppKit
import Testing
@testable import Flare

@MainActor
@Suite("Onboarding window")
struct OnboardingWindowControllerTests {
    @Test("window title uses VibeSpot branding")
    func windowTitleUsesVibeSpotBranding() throws {
        let suite = UserDefaults(suiteName: "OnboardingWindowControllerTests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        let controller = OnboardingWindowController(settingsStore: store, onFinish: {})

        let window = try #require(controller.window)
        #expect(window.title == "Welcome to VibeSpot")
    }
}
