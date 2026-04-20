import AppKit
import Testing
@testable import Flare

private struct LocalMockProcessRunner: ProcessRunning {
    let paths: [String: String]

    func which(_ command: String) async -> String? {
        paths[command]
    }
}

private struct MockTerminalAutomationChecker: TerminalAutomationChecking {
    let result: TerminalAutomationCheckResult

    func runCheck() async -> TerminalAutomationCheckResult {
        result
    }
}

@MainActor
@Suite("Onboarding window")
struct OnboardingWindowControllerTests {
    @Test("window title and first card follow the detected language")
    func windowTitleAndFirstCardFollowDetectedLanguage() throws {
        let suite = UserDefaults(suiteName: "OnboardingWindowControllerTests.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        let controller = OnboardingWindowController(
            settingsStore: store,
            environmentCheckService: EnvironmentCheckService(
                fileManager: .default,
                processRunner: LocalMockProcessRunner(paths: [:]),
                homeDirectoryPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            ),
            terminalAutomationChecker: MockTerminalAutomationChecker(
                result: TerminalAutomationCheckResult(status: .unknown)
            ),
            preferredLanguageCodeProvider: { "zh-Hans" },
            onFinish: {}
        )

        let window = try #require(controller.window)
        #expect(window.title == "欢迎使用 VibeSpot")

        let state = controller.makeViewStateForTesting()
        #expect(state.cardIndex == 0)
        #expect(state.cardCount == 8)
        #expect(state.cardID == "quickActivation")
        #expect(state.sentence.contains("快捷键"))
    }

    @Test("card flow advances through the new ordered onboarding sequence")
    func cardFlowAdvancesThroughOrderedSequence() {
        let suite = UserDefaults(suiteName: "OnboardingWindowControllerTests.flow.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        let controller = OnboardingWindowController(
            settingsStore: store,
            environmentCheckService: EnvironmentCheckService(
                fileManager: .default,
                processRunner: LocalMockProcessRunner(paths: [:]),
                homeDirectoryPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            ),
            terminalAutomationChecker: MockTerminalAutomationChecker(
                result: TerminalAutomationCheckResult(status: .unknown)
            ),
            preferredLanguageCodeProvider: { "en-US" },
            onFinish: {}
        )

        #expect(controller.currentCard == .quickActivation)
        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        #expect(controller.currentCard == .shortcutSetup)

        let shortcutState = controller.makeViewStateForTesting()
        #expect(shortcutState.sentence.contains("Cmd+Shift+Space"))

        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        let searchState = controller.makeViewStateForTesting()
        #expect(controller.currentCard == .searchSessions)
        #expect(searchState.sentence.contains("Tab"))
        #expect(searchState.sentence.contains("Enter"))

        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        let newSessionState = controller.makeViewStateForTesting()
        #expect(controller.currentCard == .startNewSession)
        #expect(newSessionState.sentence.contains("new claude"))
        #expect(newSessionState.sentence.contains("new codex"))

        controller.onboardingBridgeDidRequestBack(OnboardingBridge())
        #expect(controller.currentCard == .checkAccess)
    }

    @Test("final card uses the VibeSpot start action")
    func finalCardUsesVibeSpotStartAction() {
        let suite = UserDefaults(suiteName: "OnboardingWindowControllerTests.final.\(UUID().uuidString)")!
        let store = SettingsStore(defaults: suite)
        let controller = OnboardingWindowController(
            settingsStore: store,
            environmentCheckService: EnvironmentCheckService(
                fileManager: .default,
                processRunner: LocalMockProcessRunner(paths: [:]),
                homeDirectoryPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            ),
            terminalAutomationChecker: MockTerminalAutomationChecker(
                result: TerminalAutomationCheckResult(status: .unknown)
            ),
            preferredLanguageCodeProvider: { "en-US" },
            onFinish: {}
        )

        for _ in 0..<7 {
            controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        }

        let state = controller.makeViewStateForTesting()
        #expect(controller.currentCard == .quickSetup)
        #expect(state.cardID == "quickSetup")
        #expect(state.primaryActionTitle == "Start Using VibeSpot")
    }
}
