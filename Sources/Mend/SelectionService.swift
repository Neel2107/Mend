import AppKit
import ApplicationServices
import Carbon

struct CapturedSelection {
    let text: String
    let focusedElement: AXUIElement?
    let application: NSRunningApplication?
    let clipboardSnapshot: ClipboardSnapshot
}

enum ReplacementMethod: String {
    case accessibility
    case paste
}

enum ReplacementResult: Equatable {
    case verified(ReplacementMethod)
    case unverified
}

enum MendError: LocalizedError {
    case noSelection
    case replacementFailed
    case invalidEndpoint
    case invalidResponse
    case emptyResponse
    case selectionChanged
    case replacementNotConfirmed
    case serviceError(String)

    var errorDescription: String? {
        switch self {
        case .noSelection: return "Select some text first"
        case .replacementFailed: return "Couldn’t replace the selected text"
        case .invalidEndpoint: return "The API endpoint is invalid"
        case .invalidResponse: return "The model returned an unreadable response"
        case .emptyResponse: return "The model returned no text"
        case .selectionChanged: return "The selection changed — try again"
        case .replacementNotConfirmed: return "Couldn’t confirm the replacement"
        case .serviceError(let message): return message
        }
    }
}

// MARK: - System boundaries

/// The Accessibility calls Mend makes, kept behind a protocol so the
/// capture and replacement flow can be exercised without a real app.
protocol AccessibilityProviding {
    func focusedElement() -> AXUIElement?
    func selectedText(of element: AXUIElement) -> String?
    func value(of element: AXUIElement) -> String?
    func setSelectedText(_ text: String, of element: AXUIElement) -> Bool
    /// The frame of the window holding the focused element, in Accessibility
    /// coordinates: origin at the top-left of the primary display, y downward.
    func focusedWindowFrame() -> CGRect?
}

extension AccessibilityProviding {
    func focusedWindowFrame() -> CGRect? { nil }
}

protocol KeyboardSending {
    func sendCommandKey(_ keyCode: UInt16)
}

protocol PasteboardProviding {
    var changeCount: Int { get }
    func string() -> String?
    func setString(_ string: String) -> Bool
    func snapshot() -> ClipboardSnapshot
    func restore(_ snapshot: ClipboardSnapshot)
}

struct SystemAccessibility: AccessibilityProviding {
    func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &value
        )
        guard status == .success, let value else { return nil }
        return (value as! AXUIElement)
    }

    func selectedText(of element: AXUIElement) -> String? {
        attribute(kAXSelectedTextAttribute, of: element)
    }

    func value(of element: AXUIElement) -> String? {
        attribute(kAXValueAttribute, of: element)
    }

    func setSelectedText(_ text: String, of element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        ) == .success
    }

    func focusedWindowFrame() -> CGRect? {
        guard let element = focusedElement() else { return nil }
        var windowValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXWindowAttribute as CFString, &windowValue)
        guard status == .success, let windowValue else { return nil }
        let window = windowValue as! AXUIElement

        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = axValue(kAXPositionAttribute, of: window),
              let dimensions = axValue(kAXSizeAttribute, of: window),
              AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(dimensions, .cgSize, &size) else {
            return nil
        }
        return CGRect(origin: origin, size: size)
    }

    private func attribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard status == .success else { return nil }
        return value as? String
    }

    private func axValue(_ name: String, of element: AXUIElement) -> AXValue? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard status == .success, let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return (value as! AXValue)
    }
}

struct SystemKeyboard: KeyboardSending {
    func sendCommandKey(_ keyCode: UInt16) {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

struct SystemPasteboard: PasteboardProviding {
    var changeCount: Int { NSPasteboard.general.changeCount }

    func string() -> String? {
        NSPasteboard.general.string(forType: .string)
    }

    func setString(_ string: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(string, forType: .string)
    }

    func snapshot() -> ClipboardSnapshot {
        ClipboardSnapshot.capture()
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        snapshot.restore()
    }
}

// MARK: - Service

final class SelectionService {
    struct Timing {
        /// Delay between checks while waiting on the target app.
        var pollInterval: UInt64 = 40_000_000
        /// How many polls to wait for ⌘C to land on the pasteboard.
        var captureAttempts = 8
        /// How many polls to wait for ⌘V to change the focused element.
        var replacementAttempts = 30
        /// How long to leave the pasteboard alone when the target app
        /// exposes nothing through Accessibility and the paste cannot be observed.
        var blindPasteGrace: UInt64 = 400_000_000
    }

    private let accessibility: any AccessibilityProviding
    private let keyboard: any KeyboardSending
    private let pasteboard: any PasteboardProviding
    private let timing: Timing
    private let frontmostApplication: () -> NSRunningApplication?
    private let isApplicationActive: (NSRunningApplication) -> Bool
    private let sleep: (UInt64) async throws -> Void

    init(
        accessibility: any AccessibilityProviding = SystemAccessibility(),
        keyboard: any KeyboardSending = SystemKeyboard(),
        pasteboard: any PasteboardProviding = SystemPasteboard(),
        timing: Timing = Timing(),
        frontmostApplication: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication },
        isApplicationActive: @escaping (NSRunningApplication) -> Bool = { $0.isActive },
        sleep: @escaping (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }
    ) {
        self.accessibility = accessibility
        self.keyboard = keyboard
        self.pasteboard = pasteboard
        self.timing = timing
        self.frontmostApplication = frontmostApplication
        self.isApplicationActive = isApplicationActive
        self.sleep = sleep
    }

    /// Where the text being edited lives, in AppKit screen coordinates.
    func focusedWindowFrame() -> NSRect? {
        guard let frame = accessibility.focusedWindowFrame(),
              let primaryScreen = NSScreen.screens.first else { return nil }
        return Self.appKitRect(from: frame, primaryScreenHeight: primaryScreen.frame.height)
    }

    /// Accessibility measures from the top-left of the primary display and
    /// AppKit from its bottom-left, so only the vertical axis flips.
    static func appKitRect(from accessibilityRect: CGRect, primaryScreenHeight: CGFloat) -> NSRect {
        NSRect(
            x: accessibilityRect.minX,
            y: primaryScreenHeight - accessibilityRect.maxY,
            width: accessibilityRect.width,
            height: accessibilityRect.height
        )
    }

    func captureSelection() async throws -> CapturedSelection {
        let application = frontmostApplication()
        let snapshot = pasteboard.snapshot()

        if let element = accessibility.focusedElement(),
           let text = accessibility.selectedText(of: element),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CapturedSelection(
                text: text,
                focusedElement: element,
                application: application,
                clipboardSnapshot: snapshot
            )
        }

        let previousChangeCount = pasteboard.changeCount
        keyboard.sendCommandKey(UInt16(kVK_ANSI_C))
        defer { pasteboard.restore(snapshot) }

        for _ in 0..<timing.captureAttempts {
            try await sleep(timing.pollInterval)
            if pasteboard.changeCount != previousChangeCount,
               let text = pasteboard.string(),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CapturedSelection(
                    text: text,
                    focusedElement: accessibility.focusedElement(),
                    application: application,
                    clipboardSnapshot: snapshot
                )
            }
        }

        throw MendError.noSelection
    }

    func replaceSelection(_ text: String, in selection: CapturedSelection) async throws -> ReplacementResult {
        if let application = selection.application, !isApplicationActive(application) {
            throw MendError.selectionChanged
        }

        let currentElement = accessibility.focusedElement()
        if let expectedElement = selection.focusedElement,
           let currentElement,
           !CFEqual(expectedElement, currentElement) {
            throw MendError.selectionChanged
        }

        let valueBefore = currentElement.flatMap(accessibility.value(of:))
        let selectedBefore = currentElement.flatMap(accessibility.selectedText(of:))

        // Write through Accessibility when the result can be verified. This
        // needs no clipboard, has no timing window, and survives remapped ⌘V.
        // Some apps report success without changing anything, so the element
        // is read back and the paste fallback only runs when it is untouched.
        if let currentElement,
           let valueBefore,
           selectedBefore == selection.text,
           accessibility.setSelectedText(text, of: currentElement),
           let valueAfter = accessibility.value(of: currentElement),
           valueAfter != valueBefore {
            return .verified(.accessibility)
        }

        guard pasteboard.setString(text) else {
            throw MendError.replacementFailed
        }
        defer { pasteboard.restore(selection.clipboardSnapshot) }

        keyboard.sendCommandKey(UInt16(kVK_ANSI_V))

        // The pasteboard must hold the replacement until the target app has
        // read it, so wait for evidence of the paste before restoring it.
        guard valueBefore != nil || selectedBefore != nil else {
            try await sleep(timing.blindPasteGrace)
            return .unverified
        }

        for _ in 0..<timing.replacementAttempts {
            try await sleep(timing.pollInterval)
            let element = currentElement ?? accessibility.focusedElement()
            let valueAfter = element.flatMap(accessibility.value(of:))
            let selectedAfter = element.flatMap(accessibility.selectedText(of:))

            if let valueBefore, let valueAfter, valueBefore != valueAfter {
                return .verified(.paste)
            }
            if let selectedBefore, let selectedAfter, selectedBefore != selectedAfter {
                return .verified(.paste)
            }
        }

        let element = currentElement ?? accessibility.focusedElement()
        let selectedAfter = element.flatMap(accessibility.selectedText(of:))
        if selectedBefore == selection.text, selectedAfter == selection.text {
            throw MendError.replacementNotConfirmed
        }

        return .unverified
    }
}

// MARK: - Clipboard

struct ClipboardSnapshot {
    struct Item {
        let values: [NSPasteboard.PasteboardType: Data]
    }

    let items: [Item]

    static func capture() -> ClipboardSnapshot {
        let capturedItems = (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var values: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    values[type] = data
                }
            }
            return Item(values: values)
        }
        return ClipboardSnapshot(items: capturedItems)
    }

    func restore() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let restoredItems = items.map { captured -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in captured.values {
                item.setData(data, forType: type)
            }
            return item
        }
        if !restoredItems.isEmpty {
            pasteboard.writeObjects(restoredItems)
        }
    }
}
