import AppKit
import Testing
@testable import Flare

@MainActor
@Suite("Search panel keyboard shortcuts")
struct SearchPanelControllerKeyboardTests {
    @Test("command comma opens preferences from the search panel")
    func commandCommaOpensPreferencesFromSearchPanel() throws {
        let controller = SearchPanelController()
        let recorder = CallbackRecorder()
        controller.onOpenPreferences = {
            recorder.callCount += 1
        }

        controller.show()
        defer { controller.hide() }

        let panel = try #require(findPanel(in: controller))
        let event = try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: ",",
                charactersIgnoringModifiers: ",",
                isARepeat: false,
                keyCode: 43
            )
        )

        panel.keyDown(with: event)

        #expect(recorder.callCount == 1)
    }

    @Test("typing before webview focus is ready buffers the initial query")
    func typingBeforeWebViewFocusIsReadyBuffersInitialQuery() throws {
        let controller = SearchPanelController()
        var scripts: [String] = []
        controller.installJavaScriptEvaluatorForTesting { script, completion in
            scripts.append(script)
            completion?(nil, nil)
        }
        controller.setWebViewReadyForTesting(false)
        controller.show()
        defer { controller.hide() }

        let panel = try #require(findPanel(in: controller))

        panel.keyDown(with: try #require(makeKeyEvent(characters: "h", keyCode: 4, windowNumber: panel.windowNumber)))
        panel.keyDown(with: try #require(makeKeyEvent(characters: "i", keyCode: 34, windowNumber: panel.windowNumber)))

        #expect(!scripts.contains(where: { $0.contains("setSearchQueryAndFocus(") }))

        controller.setWebViewReadyForTesting(true)
        controller.flushPendingWebViewStateForTesting()

        #expect(scripts.contains(where: { $0.contains("setSearchQueryAndFocus('hi')") }))
    }

    private func findPanel(in controller: SearchPanelController) -> NSPanel? {
        Mirror(reflecting: controller).children
            .first { $0.label == "panel" }?
            .value as? NSPanel
    }

    private func makeKeyEvent(characters: String, keyCode: UInt16, windowNumber: Int) -> NSEvent? {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: windowNumber,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )
    }
}

@MainActor
private final class CallbackRecorder {
    var callCount = 0
}
