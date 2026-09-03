import AppKit
@testable import Mend
import Testing

@MainActor
@Suite("Overlay presentation")
struct OverlayControllerTests {
    @Test("A hidden overlay reveals only its requested state")
    func testHiddenOverlayRevealsOnlyItsRequestedState() {
        let transitions: [(previous: OverlayState, requested: OverlayState)] = [
            (.success("Fixed"), .working("Fixing grammar…")),
            (.failure("Previous error"), .working("Fixing grammar…")),
            (.working("Fixing grammar…"), .failure("Select some text first")),
        ]

        for transition in transitions {
            let model = OverlayModel()
            model.state = transition.previous
            let panel = RecordingOverlayPanel(state: { model.state })
            let controller = OverlayController(model: model, panel: panel)

            controller.show(transition.requested)

            #expect(
                panel.events == [
                    .setFrame(animated: false),
                    .setContentVisible(false),
                    .show,
                    .prepare,
                    .setContentVisible(true),
                ]
            )
            #expect(panel.stateWhenRevealed == transition.requested)
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
        case setContentVisible(Bool)
        case prepare
        case show
        case hide
    }

    var isVisible = false
    private(set) var events: [Event] = []
    private(set) var stateWhenShown: OverlayState?
    private(set) var stateWhenRevealed: OverlayState?
    private let state: () -> OverlayState

    init(state: @escaping () -> OverlayState) {
        self.state = state
    }

    func setOverlayFrame(_ frame: NSRect, animated: Bool) {
        events.append(.setFrame(animated: animated))
    }

    func setOverlayContentVisible(_ isVisible: Bool) {
        if isVisible {
            stateWhenRevealed = state()
        }
        events.append(.setContentVisible(isVisible))
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
