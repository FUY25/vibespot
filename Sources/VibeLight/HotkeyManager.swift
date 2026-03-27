import Carbon
import Cocoa

@MainActor
final class HotkeyManager {
    private var hotkeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var contextRef: Unmanaged<HotkeyContext>?
    private let onToggle: @MainActor @Sendable () -> Void

    private static let hotkeyID = EventHotKeyID(
        signature: OSType(0x564C_4854),
        id: 1
    )

    init(onToggle: @escaping @MainActor @Sendable () -> Void) {
        self.onToggle = onToggle
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

        handlerRef = installedHandler

        var registeredHotkey: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(cmdKey | shiftKey),
            Self.hotkeyID,
            GetApplicationEventTarget(),
            0,
            &registeredHotkey
        )

        guard registerStatus == noErr else {
            if let installedHandler {
                RemoveEventHandler(installedHandler)
                handlerRef = nil
            }
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
