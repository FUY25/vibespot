import Cocoa
import Carbon

@MainActor
final class HotkeyManager {
    private final class CallbackContext {
        weak var manager: HotkeyManager?

        init(manager: HotkeyManager) {
            self.manager = manager
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var callbackContext: Unmanaged<CallbackContext>?
    private let onToggle: @MainActor @Sendable () -> Void

    init(onToggle: @escaping @MainActor @Sendable () -> Void) {
        self.onToggle = onToggle
    }

    func register() {
        guard eventTap == nil else { return }

        let eventMask = CGEventMask(1) << CGEventMask(CGEventType.keyDown.rawValue)
        let context = Unmanaged.passRetained(CallbackContext(manager: self))
        callbackContext = context

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: Self.eventTapCallback,
            userInfo: UnsafeMutableRawPointer(context.toOpaque())
        ) else {
            context.release()
            callbackContext = nil
            print("HotkeyManager: Accessibility permission is required for the hotkey.")
            return
        }

        eventTap = tap

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            unregister()
            return
        }

        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func unregister() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }

        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

        if let context = callbackContext {
            context.release()
            callbackContext = nil
        }
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon = refcon else {
            return Unmanaged.passUnretained(event)
        }

        let context = Unmanaged<CallbackContext>.fromOpaque(refcon).takeUnretainedValue()
        guard let manager = context.manager else {
            return Unmanaged.passUnretained(event)
        }

        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        let spaceKey = CGKeyCode(kVK_Space)
        let isAutoRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let requiredModifiers: CGEventFlags = [.maskCommand, .maskShift]
        let relevantModifiers: CGEventFlags = [
            .maskAlphaShift,
            .maskShift,
            .maskControl,
            .maskAlternate,
            .maskCommand,
            .maskHelp,
            .maskSecondaryFn,
            .maskNumericPad,
        ]
        let pressedModifiers = flags.intersection(relevantModifiers)

        let isMatch = keyCode == spaceKey && !isAutoRepeat && pressedModifiers == requiredModifiers
        guard isMatch else {
            return Unmanaged.passUnretained(event)
        }

        Task { @MainActor in
            manager.onToggle()
        }

        return nil
    }
}
