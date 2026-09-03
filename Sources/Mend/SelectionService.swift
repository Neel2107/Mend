import AppKit
import ApplicationServices
import Carbon

struct CapturedSelection {
    let text: String
    let focusedElement: AXUIElement?
    let application: NSRunningApplication?
    let clipboardSnapshot: ClipboardSnapshot
}

enum ReplacementResult: Equatable {
    case verified
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

final class SelectionService {
    func captureSelection() async throws -> CapturedSelection {
        let application = NSWorkspace.shared.frontmostApplication
        let snapshot = ClipboardSnapshot.capture()

        if let element = focusedElement(),
           let text = selectedText(from: element),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return CapturedSelection(
                text: text,
                focusedElement: element,
                application: application,
                clipboardSnapshot: snapshot
            )
        }

        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        sendCommandKey(keyCode: UInt16(kVK_ANSI_C))
        defer { snapshot.restore() }

        for _ in 0..<8 {
            try await Task.sleep(nanoseconds: 40_000_000)
            if pasteboard.changeCount != previousChangeCount,
               let text = pasteboard.string(forType: .string),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return CapturedSelection(
                    text: text,
                    focusedElement: focusedElement(),
                    application: application,
                    clipboardSnapshot: snapshot
                )
            }
        }

        throw MendError.noSelection
    }

    func replaceSelection(_ text: String, in selection: CapturedSelection) async throws -> ReplacementResult {
        guard selection.application?.isActive == true else {
            throw MendError.selectionChanged
        }

        let currentElement = focusedElement()
        if let expectedElement = selection.focusedElement,
           let currentElement,
           !CFEqual(expectedElement, currentElement) {
            throw MendError.selectionChanged
        }

        let valueBefore = currentElement.flatMap(textValue(from:))
        let selectedBefore = currentElement.flatMap(selectedText(from:))

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        defer { selection.clipboardSnapshot.restore() }
        guard pasteboard.setString(text, forType: .string) else {
            throw MendError.replacementFailed
        }

        sendCommandKey(keyCode: UInt16(kVK_ANSI_V))
        try await Task.sleep(nanoseconds: 320_000_000)

        let elementAfter = focusedElement()
        let valueAfter = elementAfter.flatMap(textValue(from:))
        let selectedAfter = elementAfter.flatMap(selectedText(from:))

        if let valueBefore, let valueAfter, valueBefore != valueAfter {
            return .verified
        }

        if let selectedBefore, let selectedAfter, selectedBefore != selectedAfter {
            return .verified
        }

        if selectedBefore == selection.text && selectedAfter == selection.text {
            throw MendError.replacementNotConfirmed
        }

        return .unverified
    }

    private func focusedElement() -> AXUIElement? {
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

    private func selectedText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        )
        guard status == .success else { return nil }
        return value as? String
    }

    private func textValue(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        )
        guard status == .success else { return nil }
        return value as? String
    }

    private func sendCommandKey(keyCode: UInt16) {
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
