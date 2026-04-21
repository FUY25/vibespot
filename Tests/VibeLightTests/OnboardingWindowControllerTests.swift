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
        #expect(window.titleVisibility == .hidden)
        #expect(window.isMovableByWindowBackground)
        #expect(controller.hasDragRegionForTesting)
        #expect(window.standardWindowButton(.closeButton)?.isHidden == true)
        #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == true)
        #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)

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
        #expect(shortcutState.sentence == "Default: Cmd+Shift+Space. Change it if you want.")

        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        let searchState = controller.makeViewStateForTesting()
        #expect(controller.currentCard == .searchSessions)
        #expect(searchState.sentence.contains("Fuzzy-search"))
        #expect(searchState.sentence.contains("old"))

        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        let newSessionState = controller.makeViewStateForTesting()
        #expect(controller.currentCard == .startNewSession)
        #expect(newSessionState.sentence.contains("type new"))

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

    @Test("onboarding uses concise action-driven english copy")
    func onboardingUsesConciseActionDrivenEnglishCopy() {
        let suite = UserDefaults(suiteName: "OnboardingWindowControllerTests.concise.\(UUID().uuidString)")!
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

        #expect(controller.makeViewStateForTesting().sentence == "Anytime, anywhere. Press your shortcut to see live sessions and recent messages.")
        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        #expect(controller.makeViewStateForTesting().sentence == "Default: Cmd+Shift+Space. Change it if you want.")
        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        #expect(controller.makeViewStateForTesting().sentence == "Pick a session. Press Enter to jump back in.")
        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        #expect(controller.makeViewStateForTesting().sentence == "Fuzzy-search by keyword to find the right window or reopen an old session fast.")
    }

    @Test("shortcut change flow retains the capture controller until it closes")
    func shortcutChangeFlowRetainsTheCaptureControllerUntilItCloses() throws {
        let suite = UserDefaults(suiteName: "OnboardingWindowControllerTests.shortcutSheet.\(UUID().uuidString)")!
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

        controller.showOnboarding()
        controller.onboardingBridgeDidRequestNext(OnboardingBridge())
        controller.onboardingBridgeDidRequestShortcutChange(OnboardingBridge())

        #expect(controller.hasShortcutCaptureSheetForTesting)

        let captureController = try #require(controller.shortcutCaptureWindowControllerForTesting)
        captureController.closeSheetForTesting()

        #expect(controller.hasShortcutCaptureSheetForTesting == false)
    }

    @Test("window height stays fixed across card resize requests")
    func windowHeightStaysFixedAcrossResizeRequests() throws {
        let suite = UserDefaults(suiteName: "OnboardingWindowControllerTests.fixedHeight.\(UUID().uuidString)")!
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

        let window = try #require(controller.window)
        let initialHeight = window.frame.height

        controller.onboardingBridge(OnboardingBridge(), didRequestResize: 420)
        #expect(window.frame.height == initialHeight)

        controller.onboardingBridge(OnboardingBridge(), didRequestResize: 680)
        #expect(window.frame.height == initialHeight)
    }

    @Test("chinese onboarding flow keeps localized copy through all eight cards")
    func chineseOnboardingFlowKeepsLocalizedCopyThroughAllEightCards() {
        let suite = UserDefaults(suiteName: "OnboardingWindowControllerTests.zhFlow.\(UUID().uuidString)")!
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

        for index in 0..<8 {
            let state = controller.makeViewStateForTesting()
            #expect(state.languageCode == "zh-Hans")
            #expect(state.progressLabel == "\(index + 1) / 8")
            #expect(state.sentence.isEmpty == false)
            if index < 7 {
                controller.onboardingBridgeDidRequestNext(OnboardingBridge())
            } else {
                #expect(state.primaryActionTitle == "开始使用 VibeSpot")
                #expect(state.backLabel == "上一步")
            }
        }
    }
}
