import Carbon
import AppKit
import Foundation

struct GlobalShortcut: Codable, Hashable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let `default` = GlobalShortcut(
        keyCode: UInt32(kVK_ANSI_G),
        modifiers: UInt32(controlKey | optionKey),
        keyLabel: "G"
    )

    /// Plain ⌘C and ⌘V cannot be shortcuts: Mend sends them itself to copy
    /// the selection and paste the result, and a hotkey on either would
    /// swallow that keystroke and cancel the run in progress.
    var isReservedForMend: Bool {
        modifiers == UInt32(cmdKey)
            && (keyCode == UInt32(kVK_ANSI_C) || keyCode == UInt32(kVK_ANSI_V))
    }

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

/// One Carbon handler serves every hotkey. Carbon treats `noErr` as "handled,
/// stop here", so a handler per hotkey would swallow presses meant for the
/// others; a single handler that dispatches by id avoids that entirely.
private let mendHotKeyHandler: EventHandlerUPP = { _, event, _ in
    guard let event else { return OSStatus(eventNotHandledErr) }

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
        return OSStatus(eventNotHandledErr)
    }

    return HotKeyManager.dispatch(id: hotKeyID.id) ? noErr : OSStatus(eventNotHandledErr)
}

final class HotKeyManager {
    static let signature: OSType = 0x4D454E44 // MEND

    private static var nextID: UInt32 = 1
    /// Weak so the registry never keeps a manager alive; deinit removes the entry.
    private struct WeakManager { weak var manager: HotKeyManager? }
    private static var registry: [UInt32: WeakManager] = [:]
    private static var sharedHandlerRef: EventHandlerRef?

    let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    private let action: () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1

        guard Self.installSharedHandlerIfNeeded() else { return nil }

        let identifier = EventHotKeyID(signature: Self.signature, id: id)
        let registrationStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard registrationStatus == noErr else {
            Self.removeSharedHandlerIfUnused()
            return nil
        }

        Self.registry[id] = WeakManager(manager: self)
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        Self.registry[id] = nil
        Self.removeSharedHandlerIfUnused()
    }

    /// Runs the action for `id`. Returns false when no live manager owns it.
    fileprivate static func dispatch(id: UInt32) -> Bool {
        guard let manager = registry[id]?.manager else { return false }
        manager.action()
        return true
    }

    private static func installSharedHandlerIfNeeded() -> Bool {
        if sharedHandlerRef != nil { return true }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            mendHotKeyHandler,
            1,
            &eventType,
            nil,
            &sharedHandlerRef
        )
        return status == noErr
    }

    private static func removeSharedHandlerIfUnused() {
        guard registry.isEmpty, let handler = sharedHandlerRef else { return }
        RemoveEventHandler(handler)
        sharedHandlerRef = nil
    }
}
