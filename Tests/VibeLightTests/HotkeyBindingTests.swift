import AppKit
import Carbon
import Testing
@testable import Flare

@Suite("Hotkey binding")
struct HotkeyBindingTests {
    @Test("formats the default shortcut for display")
    func formatsTheDefaultShortcutForDisplay() {
        #expect(HotkeyBinding.default.displayString == "Cmd+Shift+Space")
    }

    @Test("formats letter shortcuts for display")
    func formatsLetterShortcutsForDisplay() {
        let binding = HotkeyBinding(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: UInt32(cmdKey | optionKey)
        )

        #expect(binding.displayString == "Cmd+Option+K")
    }

    @Test("builds a binding from an AppKit key event")
    func buildsBindingFromKeyEvent() throws {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: false,
            keyCode: UInt16(kVK_Space)
        )

        let binding = HotkeyBinding(event: try #require(event))
        #expect(binding == .default)
    }
}
