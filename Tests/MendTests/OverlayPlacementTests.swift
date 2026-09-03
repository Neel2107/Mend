import AppKit
@testable import Mend
import Testing

@Suite("Overlay placement")
struct OverlayPlacementTests {
    private let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
    private let width: CGFloat = 210
    private let height: CGFloat = 42

    @Test("Without a window the capsule sits in the screen corner")
    func testScreenCorner() {
        let frame = OverlayController.panelFrame(width: width, height: height, anchor: nil, within: screen)

        #expect(frame.maxX == 1440 - OverlayDesign.trailingMargin)
        #expect(frame.minY == OverlayDesign.bottomMargin)
        #expect(frame.size == NSSize(width: width, height: height))
    }

    @Test("A window on screen gets the capsule in its own corner")
    func testWindowCorner() {
        let window = NSRect(x: 100, y: 200, width: 800, height: 500)

        let frame = OverlayController.panelFrame(width: width, height: height, anchor: window, within: screen)

        #expect(frame.maxX == 900 - OverlayDesign.trailingMargin)
        #expect(frame.minY == 200 + OverlayDesign.bottomMargin)
    }

    @Test("A window hanging off the screen keeps the capsule visible")
    func testWindowPartlyOffScreen() {
        let window = NSRect(x: 900, y: -100, width: 800, height: 500)

        let frame = OverlayController.panelFrame(width: width, height: height, anchor: window, within: screen)

        #expect(frame.maxX == 1440 - OverlayDesign.trailingMargin)
        #expect(frame.minY == OverlayDesign.bottomMargin)
    }

    @Test("A small window falls back to the screen corner")
    func testSmallWindow() {
        let popover = NSRect(x: 600, y: 400, width: 300, height: 120)

        let frame = OverlayController.panelFrame(width: width, height: height, anchor: popover, within: screen)

        #expect(frame.maxX == 1440 - OverlayDesign.trailingMargin)
        #expect(frame.minY == OverlayDesign.bottomMargin)
    }

    @Test("A wide error capsule that would not fit the window uses the screen")
    func testWideCapsuleInNarrowWindow() {
        let window = NSRect(x: 100, y: 100, width: 400, height: 300)

        let frame = OverlayController.panelFrame(width: 500, height: height, anchor: window, within: screen)

        #expect(frame.maxX == 1440 - OverlayDesign.trailingMargin)
    }

    @Test("Accessibility frames flip only their vertical axis")
    func testCoordinateConversion() {
        let axFrame = CGRect(x: 100, y: 50, width: 800, height: 600)

        let frame = SelectionService.appKitRect(from: axFrame, primaryScreenHeight: 900)

        #expect(frame == NSRect(x: 100, y: 250, width: 800, height: 600))
    }
}
