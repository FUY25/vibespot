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

    private func findPanel(in controller: SearchPanelController) -> NSPanel? {
        Mirror(reflecting: controller).children
            .first { $0.label == "panel" }?
            .value as? NSPanel
    }
}

@MainActor
private final class CallbackRecorder {
    var callCount = 0
}
