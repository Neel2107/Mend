import Carbon
import AppKit
import Foundation

struct GlobalShortcut: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let `default` = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_G),
        modifiers: UInt32(controlKey | optionKey),
        keyLabel: "G"
    )

    var displayString: String {
        var value = ""
        if modifiers & UInt32(controlKey) != 0 { value += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { value += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { value += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { value += "⌘" }
        return value + keyLabel
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let hasPrimaryModifier = flags.contains(.command)
            || flags.contains(.control)
            || flags.contains(.option)
        guard hasPrimaryModifier || Self.allowsStandaloneUse(event.keyCode) else {
            return nil
        }

        var carbonModifiers: UInt32 = 0
        if flags.contains(.command) { carbonModifiers |= UInt32(cmdKey) }
        if flags.contains(.control) { carbonModifiers |= UInt32(controlKey) }
        if flags.contains(.option) { carbonModifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { carbonModifiers |= UInt32(shiftKey) }

        let label = Self.label(for: event)
        guard !label.isEmpty else { return nil }

        self.init(
            keyCode: UInt32(event.keyCode),
            modifiers: carbonModifiers,
            keyLabel: label
        )
    }

    private static func label(for event: NSEvent) -> String {
        let specialKeys: [UInt16: String] = [
            UInt16(kVK_Return): "↩",
            UInt16(kVK_Tab): "⇥",
            UInt16(kVK_Space): "Space",
            UInt16(kVK_Delete): "⌫",
            UInt16(kVK_ForwardDelete): "⌦",
            UInt16(kVK_LeftArrow): "←",
            UInt16(kVK_RightArrow): "→",
            UInt16(kVK_UpArrow): "↑",
            UInt16(kVK_DownArrow): "↓",
            UInt16(kVK_Home): "Home",
            UInt16(kVK_End): "End",
            UInt16(kVK_PageUp): "PgUp",
            UInt16(kVK_PageDown): "PgDn",
            UInt16(kVK_F1): "F1",
            UInt16(kVK_F2): "F2",
            UInt16(kVK_F3): "F3",
            UInt16(kVK_F4): "F4",
            UInt16(kVK_F5): "F5",
            UInt16(kVK_F6): "F6",
            UInt16(kVK_F7): "F7",
            UInt16(kVK_F8): "F8",
            UInt16(kVK_F9): "F9",
            UInt16(kVK_F10): "F10",
            UInt16(kVK_F11): "F11",
            UInt16(kVK_F12): "F12",
            UInt16(kVK_F13): "F13",
            UInt16(kVK_F14): "F14",
            UInt16(kVK_F15): "F15",
            UInt16(kVK_F16): "F16",
            UInt16(kVK_F17): "F17",
            UInt16(kVK_F18): "F18",
            UInt16(kVK_F19): "F19",
            UInt16(kVK_F20): "F20",
        ]

        if let specialKey = specialKeys[event.keyCode] {
            return specialKey
        }

        return event.charactersIgnoringModifiers?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased() ?? ""
    }

    private static func allowsStandaloneUse(_ keyCode: UInt16) -> Bool {
        let standaloneKeys: Set<UInt16> = [
            UInt16(kVK_Home),
            UInt16(kVK_End),
            UInt16(kVK_PageUp),
            UInt16(kVK_PageDown),
            UInt16(kVK_F1),
            UInt16(kVK_F2),
            UInt16(kVK_F3),
            UInt16(kVK_F4),
            UInt16(kVK_F5),
            UInt16(kVK_F6),
            UInt16(kVK_F7),
            UInt16(kVK_F8),
            UInt16(kVK_F9),
            UInt16(kVK_F10),
            UInt16(kVK_F11),
            UInt16(kVK_F12),
            UInt16(kVK_F13),
            UInt16(kVK_F14),
            UInt16(kVK_F15),
            UInt16(kVK_F16),
            UInt16(kVK_F17),
            UInt16(kVK_F18),
            UInt16(kVK_F19),
            UInt16(kVK_F20),
        ]
        return standaloneKeys.contains(keyCode)
    }
}

private let mendHotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else { return noErr }

    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    guard status == noErr, hotKeyID.signature == HotKeyManager.signature else {
        return status
    }

    let manager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
    manager.invoke()
    return noErr
}

final class HotKeyManager {
    static let signature: OSType = 0x4D454E44 // MEND

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            mendHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandlerRef
        )

        guard handlerStatus == noErr else { return nil }

        let identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registrationStatus == noErr else {
            if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    fileprivate func invoke() {
        action()
    }
}
