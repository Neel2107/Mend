import AppKit
@testable import Mend
import Testing

@MainActor
@Suite("Overlay presentation")
struct OverlayControllerTests {
    @Test("A hidden overlay commits its new state before appearing")
    func testHiddenOverlayCommitsNewStateBeforeItIsRevealed() {
        let previousTerminalStates: [OverlayState] = [
            .success("Fixed"),
            .failure("Previous error"),
        ]

        for previousState in previousTerminalStates {
            let model = OverlayModel()
            model.state = previousState
            let panel = RecordingOverlayPanel(state: { model.state })
            let controller = OverlayController(model: model, panel: panel)

            controller.show(.working("Fixing grammar…"))

            #expect(panel.events == [.setFrame(animated: false), .prepare, .show])
            #expect(panel.stateWhenShown == .working("Fixing grammar…"))
        }
    }

    @Test("A visible overlay keeps smooth animated state changes")
    func testVisibleOverlayAnimatesWithoutPreparingItAgain() {
        let model = OverlayModel()
        let panel = RecordingOverlayPanel(state: { model.state })
        panel.isVisible = true
        let controller = OverlayController(model: model, panel: panel)

        controller.show(.success("Fixed"))

        #expect(panel.events == [.setFrame(animated: true), .show])
        #expect(panel.stateWhenShown == .success("Fixed"))
    }
}

@MainActor
private final class RecordingOverlayPanel: OverlayPanelPresenting {
    enum Event: Equatable {
        case setFrame(animated: Bool)
        case prepare
        case show
        case hide
    }

    var isVisible = false
    private(set) var events: [Event] = []
    private(set) var stateWhenShown: OverlayState?
    private let state: () -> OverlayState

    init(state: @escaping () -> OverlayState) {
        self.state = state
    }

    func setOverlayFrame(_ frame: NSRect, animated: Bool) {
        events.append(.setFrame(animated: animated))
    }

    func prepareForPresentation() {
        events.append(.prepare)
    }

    func showOverlay() {
        stateWhenShown = state()
        isVisible = true
        events.append(.show)
    }

    func hideOverlay() {
        isVisible = false
        events.append(.hide)
    }
}
