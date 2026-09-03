import AppKit
import ApplicationServices
import Carbon
@testable import Mend
import Testing

/// A fake text field: what Accessibility reports, and how it reacts to input.
private final class FakeAccessibility: AccessibilityProviding {
    let element: AXUIElement? = AXUIElementCreateApplication(getpid())
    var value: String?
    var selected: String?
    var acceptsWrites = true
    var appliesWrites = true

    func focusedElement() -> AXUIElement? { element }
    func selectedText(of element: AXUIElement) -> String? { selected }
    func value(of element: AXUIElement) -> String? { value }

    func setSelectedText(_ text: String, of element: AXUIElement) -> Bool {
        guard acceptsWrites else { return false }
        if appliesWrites { replaceSelection(with: text) }
        return true
    }

    func replaceSelection(with text: String) {
        if let value, let selected, let range = value.range(of: selected) {
            self.value = value.replacingCharacters(in: range, with: text)
        }
        selected = ""
    }
}

private final class FakeKeyboard: KeyboardSending {
    var keys: [UInt16] = []
    var onKey: ((UInt16) -> Void)?

    func sendCommandKey(_ keyCode: UInt16) {
        keys.append(keyCode)
        onKey?(keyCode)
    }
}

private final class FakePasteboard: PasteboardProviding {
    var contents: String?
    private(set) var changeCount = 0
    private(set) var restoreCount = 0

    init(contents: String?) {
        self.contents = contents
    }

    func string() -> String? { contents }

    func setString(_ string: String) -> Bool {
        contents = string
        changeCount += 1
        return true
    }

    func snapshot() -> ClipboardSnapshot {
        ClipboardSnapshot(items: contents.map { [.init(values: [.string: Data($0.utf8)])] } ?? [])
    }

    func restore(_ snapshot: ClipboardSnapshot) {
        restoreCount += 1
        contents = snapshot.items.first?.values[.string].flatMap { String(data: $0, encoding: .utf8) }
    }
}

private final class Harness {
    let accessibility = FakeAccessibility()
    let keyboard = FakeKeyboard()
    let pasteboard: FakePasteboard
    private(set) var sleeps = 0
    var onSleep: ((Int) -> Void)?

    init(clipboard: String? = "old clipboard") {
        pasteboard = FakePasteboard(contents: clipboard)
    }

    func makeService(replacementAttempts: Int = 5) -> SelectionService {
        SelectionService(
            accessibility: accessibility,
            keyboard: keyboard,
            pasteboard: pasteboard,
            timing: .init(pollInterval: 1, captureAttempts: 4, replacementAttempts: replacementAttempts, blindPasteGrace: 1),
            frontmostApplication: { nil },
            isApplicationActive: { _ in true },
            sleep: { [unowned self] _ in
                self.sleeps += 1
                self.onSleep?(self.sleeps)
            }
        )
    }

    func selection(_ text: String, element: AXUIElement? = nil) -> CapturedSelection {
        CapturedSelection(
            text: text,
            focusedElement: element ?? accessibility.element,
            application: nil,
            clipboardSnapshot: pasteboard.snapshot()
        )
    }
}

@Suite("Selection capture")
struct SelectionCaptureTests {
    @Test("Selected text comes from Accessibility without touching the clipboard")
    func testCaptureThroughAccessibility() async throws {
        let harness = Harness()
        harness.accessibility.value = "I have send it."
        harness.accessibility.selected = "have send"

        let selection = try await harness.makeService().captureSelection()

        #expect(selection.text == "have send")
        #expect(harness.keyboard.keys.isEmpty)
        #expect(harness.pasteboard.contents == "old clipboard")
    }

    @Test("Without Accessibility text, ⌘C is sent and the clipboard is restored")
    func testCaptureThroughCopy() async throws {
        let harness = Harness()
        harness.keyboard.onKey = { key in
            if key == UInt16(kVK_ANSI_C) { _ = harness.pasteboard.setString("copied words") }
        }

        let selection = try await harness.makeService().captureSelection()

        #expect(selection.text == "copied words")
        #expect(harness.keyboard.keys == [UInt16(kVK_ANSI_C)])
        #expect(harness.pasteboard.contents == "old clipboard")
        #expect(harness.pasteboard.restoreCount == 1)
    }

    @Test("Nothing selected reports an error instead of hanging")
    func testNoSelection() async {
        let harness = Harness()

        await #expect {
            try await harness.makeService().captureSelection()
        } throws: { error in
            guard case MendError.noSelection = error else { return false }
            return true
        }
        #expect(harness.pasteboard.contents == "old clipboard")
    }
}

@Suite("Selection replacement")
struct SelectionReplacementTests {
    @Test("A verifiable element is written through Accessibility, with no paste")
    func testAccessibilityWrite() async throws {
        let harness = Harness()
        harness.accessibility.value = "I have send it."
        harness.accessibility.selected = "have send"
        let service = harness.makeService()

        let result = try await service.replaceSelection("sent", in: harness.selection("have send"))

        #expect(result == .verified(.accessibility))
        #expect(harness.accessibility.value == "I sent it.")
        #expect(harness.keyboard.keys.isEmpty)
        #expect(harness.pasteboard.contents == "old clipboard")
        #expect(harness.pasteboard.restoreCount == 0)
    }

    @Test("A write the app ignores falls back to paste, and the clipboard waits for the paste")
    func testPasteFallbackWaitsForTheApp() async throws {
        let harness = Harness()
        harness.accessibility.value = "I have send it."
        harness.accessibility.selected = "have send"
        harness.accessibility.appliesWrites = false
        var pasteRequested = false
        harness.keyboard.onKey = { key in
            if key == UInt16(kVK_ANSI_V) { pasteRequested = true }
        }
        var clipboardDuringPaste: String?
        harness.onSleep = { count in
            // The app handles ⌘V on the third poll and reads the pasteboard then.
            guard pasteRequested, count == 3 else { return }
            clipboardDuringPaste = harness.pasteboard.contents
            harness.accessibility.replaceSelection(with: harness.pasteboard.contents ?? "")
        }
        let service = harness.makeService()

        let result = try await service.replaceSelection("sent", in: harness.selection("have send"))

        #expect(result == .verified(.paste))
        #expect(harness.keyboard.keys == [UInt16(kVK_ANSI_V)])
        #expect(clipboardDuringPaste == "sent")
        #expect(harness.accessibility.value == "I sent it.")
        #expect(harness.pasteboard.contents == "old clipboard")
        #expect(harness.pasteboard.restoreCount == 1)
    }

    @Test("A paste that never lands is reported, not claimed")
    func testUnconfirmedPaste() async {
        let harness = Harness()
        harness.accessibility.value = "I have send it."
        harness.accessibility.selected = "have send"
        harness.accessibility.acceptsWrites = false
        let service = harness.makeService(replacementAttempts: 3)

        await #expect {
            try await service.replaceSelection("sent", in: harness.selection("have send"))
        } throws: { error in
            guard case MendError.replacementNotConfirmed = error else { return false }
            return true
        }
        #expect(harness.sleeps == 3)
        #expect(harness.pasteboard.contents == "old clipboard")
    }

    @Test("An app with no Accessibility text gets a blind paste")
    func testBlindPaste() async throws {
        let harness = Harness()
        let service = harness.makeService()

        let result = try await service.replaceSelection("sent", in: harness.selection("have send"))

        #expect(result == .unverified)
        #expect(harness.keyboard.keys == [UInt16(kVK_ANSI_V)])
        #expect(harness.sleeps == 1)
        #expect(harness.pasteboard.contents == "old clipboard")
    }

    @Test("Focus moving to another element aborts before anything is written")
    func testFocusChanged() async {
        let harness = Harness()
        harness.accessibility.value = "I have send it."
        harness.accessibility.selected = "have send"
        let service = harness.makeService()
        let elsewhere = AXUIElementCreateSystemWide()

        await #expect {
            try await service.replaceSelection("sent", in: harness.selection("have send", element: elsewhere))
        } throws: { error in
            guard case MendError.selectionChanged = error else { return false }
            return true
        }
        #expect(harness.accessibility.value == "I have send it.")
        #expect(harness.keyboard.keys.isEmpty)
    }
}
