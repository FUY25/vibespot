import AppKit
import Carbon

struct HotkeyBinding: Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    static let `default` = HotkeyBinding(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(cmdKey | shiftKey)
    )

    init?(event: NSEvent) {
        let modifierFlags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let carbonModifiers = Self.carbonModifiers(from: modifierFlags)
        guard carbonModifiers != 0 else { return nil }

        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers
        )
    }

    var displayString: String {
        let parts = modifierDisplayParts + [Self.keyDisplayString(for: keyCode)]
        return parts.joined(separator: "+")
    }

    private var modifierDisplayParts: [String] {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Cmd") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("Control") }
        return parts
    }

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        return modifiers
    }

    private static func keyDisplayString(for keyCode: UInt32) -> String {
        if let label = keyLabels[keyCode] {
            return label
        }
        return String(keyCode)
    }

    private static let keyLabels: [UInt32: String] = [
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Return): "Return",
        UInt32(kVK_Tab): "Tab",
        UInt32(kVK_Delete): "Delete",
        UInt32(kVK_Escape): "Escape",
        UInt32(kVK_LeftArrow): "Left",
        UInt32(kVK_RightArrow): "Right",
        UInt32(kVK_UpArrow): "Up",
        UInt32(kVK_DownArrow): "Down",
        UInt32(kVK_ANSI_A): "A",
        UInt32(kVK_ANSI_B): "B",
        UInt32(kVK_ANSI_C): "C",
        UInt32(kVK_ANSI_D): "D",
        UInt32(kVK_ANSI_E): "E",
        UInt32(kVK_ANSI_F): "F",
        UInt32(kVK_ANSI_G): "G",
        UInt32(kVK_ANSI_H): "H",
        UInt32(kVK_ANSI_I): "I",
        UInt32(kVK_ANSI_J): "J",
        UInt32(kVK_ANSI_K): "K",
        UInt32(kVK_ANSI_L): "L",
        UInt32(kVK_ANSI_M): "M",
        UInt32(kVK_ANSI_N): "N",
        UInt32(kVK_ANSI_O): "O",
        UInt32(kVK_ANSI_P): "P",
        UInt32(kVK_ANSI_Q): "Q",
        UInt32(kVK_ANSI_R): "R",
        UInt32(kVK_ANSI_S): "S",
        UInt32(kVK_ANSI_T): "T",
        UInt32(kVK_ANSI_U): "U",
        UInt32(kVK_ANSI_V): "V",
        UInt32(kVK_ANSI_W): "W",
        UInt32(kVK_ANSI_X): "X",
        UInt32(kVK_ANSI_Y): "Y",
        UInt32(kVK_ANSI_Z): "Z",
        UInt32(kVK_ANSI_0): "0",
        UInt32(kVK_ANSI_1): "1",
        UInt32(kVK_ANSI_2): "2",
        UInt32(kVK_ANSI_3): "3",
        UInt32(kVK_ANSI_4): "4",
        UInt32(kVK_ANSI_5): "5",
        UInt32(kVK_ANSI_6): "6",
        UInt32(kVK_ANSI_7): "7",
        UInt32(kVK_ANSI_8): "8",
        UInt32(kVK_ANSI_9): "9",
    ]
}

@MainActor
final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var contextRef: Unmanaged<HotkeyContext>?
    private let binding: HotkeyBinding
    private let onToggle: @MainActor @Sendable () -> Void

    private static let hotkeyID = EventHotKeyID(
        signature: OSType(0x564C_4854),
        id: 1
    )

    init(binding: HotkeyBinding = .default, onToggle: @escaping @MainActor @Sendable () -> Void) {
        self.binding = binding
        self.onToggle = onToggle
    }

    deinit {
        MainActor.assumeIsolated {
            unregister()
        }
    }

    func register() {
        guard hotkeyRef == nil, handlerRef == nil else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let context = Unmanaged.passRetained(HotkeyContext(manager: self))
        contextRef = context

        var installedHandler: EventHandlerRef?
        let installStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, refcon -> OSStatus in
                guard let refcon else {
                    return OSStatus(eventNotHandledErr)
                }

                var pressedID = EventHotKeyID()
                let parameterStatus = GetEventParameter(
                    event,
                    UInt32(kEventParamDirectObject),
                    UInt32(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )

                guard parameterStatus == noErr,
                      pressedID.signature == HotkeyManager.hotkeyID.signature,
                      pressedID.id == HotkeyManager.hotkeyID.id
                else {
                    return OSStatus(eventNotHandledErr)
                }

                let context = Unmanaged<HotkeyContext>.fromOpaque(refcon).takeUnretainedValue()
                Task { @MainActor in
                    context.manager?.onToggle()
                }

                return noErr
            },
            1,
            &eventType,
            UnsafeMutableRawPointer(context.toOpaque()),
            &installedHandler
        )

        guard installStatus == noErr else {
            contextRef?.release()
            contextRef = nil
            return
        }

        guard let installedHandler else {
            contextRef?.release()
            contextRef = nil
            return
        }

        handlerRef = installedHandler

        var registeredHotkey: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            binding.keyCode,
            binding.modifiers,
            Self.hotkeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotkey
        )

        guard registerStatus == noErr else {
            RemoveEventHandler(installedHandler)
            handlerRef = nil
            contextRef?.release()
            contextRef = nil
            return
        }

        hotkeyRef = registeredHotkey
    }

    func unregister() {
        if let hotkeyRef {
            UnregisterEventHotKey(hotkeyRef)
            self.hotkeyRef = nil
        }

        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }

        if let contextRef {
            contextRef.release()
            self.contextRef = nil
        }
    }
}

private final class HotkeyContext {
    weak var manager: HotkeyManager?

    init(manager: HotkeyManager) {
        self.manager = manager
    }
}
