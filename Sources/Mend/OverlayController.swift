import AppKit
import SwiftUI

// Change these values to explore the overlay without touching its behavior.
enum OverlayDesign {
    static let initialPanelSize = NSSize(width: 210, height: 42)
    static let minimumPanelWidth: CGFloat = 88
    static let maximumPanelWidth: CGFloat = 320
    static let trailingMargin: CGFloat = 20
    static let bottomMargin: CGFloat = 18

    static let horizontalPadding: CGFloat = 11
    static let contentSpacing: CGFloat = 8
    static let iconSize: CGFloat = 17
    static let labelFontSize: CGFloat = 13
    static let resizeDuration: TimeInterval = 0.42
    static let contentTransitionDuration: TimeInterval = 0.24
    static let transitionBlurRadius: CGFloat = 5
}

enum OverlayState: Equatable {
    case working(String)
    case success(String)
    case failure(String)
    case message(String)
}

@MainActor
final class OverlayModel: ObservableObject {
    static let initialState = OverlayState.working("Fixing grammar…")

    @Published var state: OverlayState = initialState
}

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
protocol OverlayPanelPresenting: AnyObject {
    var isVisible: Bool { get }
    func setOverlayFrame(_ frame: NSRect, animated: Bool)
    func prepareForPresentation()
    func showOverlay()
    func hideOverlay()
}

extension NonActivatingPanel: OverlayPanelPresenting {
    func setOverlayFrame(_ frame: NSRect, animated: Bool) {
        guard animated else {
            setFrame(frame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayDesign.resizeDuration
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.22,
                1,
                0.36,
                1
            )
            animator().setFrame(frame, display: true)
        }
    }

    func prepareForPresentation() {
        contentView?.layoutSubtreeIfNeeded()
        displayIfNeeded()
    }

    func showOverlay() {
        orderFrontRegardless()
    }

    func hideOverlay() {
        orderOut(nil)
    }
}

@MainActor
final class OverlayController {
    private let model: OverlayModel
    private let panel: any OverlayPanelPresenting
    private var hideTask: Task<Void, Never>?

    init() {
        let model = OverlayModel()
        let panel = NonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: OverlayDesign.initialPanelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: OverlayView(model: model))
        self.model = model
        self.panel = panel
    }

    init(model: OverlayModel, panel: any OverlayPanelPresenting) {
        self.model = model
        self.panel = panel
    }

    func show(_ state: OverlayState, autoHideAfter seconds: Double? = nil) {
        hideTask?.cancel()
        let shouldAnimate = panel.isVisible

        if shouldAnimate {
            withAnimation(.easeInOut(duration: OverlayDesign.contentTransitionDuration)) {
                model.state = state
            }
        } else {
            model.state = state
        }

        resizeAndPositionPanel(for: state, animated: shouldAnimate)
        if !shouldAnimate {
            // SwiftUI commits view updates on the next layout pass. Commit the new
            // state while the panel is hidden so its previous result never flashes.
            panel.prepareForPresentation()
        }
        panel.showOverlay()

        if let seconds {
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.hideAndPrepareForNextPresentation()
                }
            }
        }
    }

    func hideAndPrepareForNextPresentation() {
        panel.hideOverlay()
        model.state = OverlayModel.initialState
        panel.prepareForPresentation()
    }

    private func resizeAndPositionPanel(for state: OverlayState, animated: Bool) {
        // NSScreen.main follows the window of the currently active writing app.
        // The panel never activates Mend, so this remains the user's working screen.
        let screen = NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let width = targetWidth(for: state)
        // Keep the trailing edge visually fixed while the capsule grows or shrinks.
        let anchoredFrame = NSRect(
            x: frame.maxX - width - OverlayDesign.trailingMargin,
            y: frame.minY + OverlayDesign.bottomMargin,
            width: width,
            height: OverlayDesign.initialPanelSize.height
        )

        panel.setOverlayFrame(anchoredFrame, animated: animated)
    }

    private func targetWidth(for state: OverlayState) -> CGFloat {
        let label: String
        switch state {
        case .working(let text), .success(let text), .failure(let text), .message(let text):
            label = text
        }

        let font = NSFont.systemFont(ofSize: OverlayDesign.labelFontSize, weight: .medium)
        let labelWidth = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        let width = (OverlayDesign.horizontalPadding * 2)
            + OverlayDesign.iconSize
            + OverlayDesign.contentSpacing
            + labelWidth

        return min(
            max(width, OverlayDesign.minimumPanelWidth),
            OverlayDesign.maximumPanelWidth
        )
    }
}

private struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: OverlayDesign.contentSpacing) {
            icon
                .frame(width: OverlayDesign.iconSize, height: OverlayDesign.iconSize)

            ZStack(alignment: .leading) {
                Text(label)
                    .font(.system(size: OverlayDesign.labelFontSize, weight: .medium, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .id(label)
                    .transition(.mendBlur)
            }

        }
        .padding(.horizontal, OverlayDesign.horizontalPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThickMaterial, in: Capsule())
        .animation(
            .easeInOut(duration: OverlayDesign.contentTransitionDuration),
            value: model.state
        )
    }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .working:
            SearchingOrb()
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
        case .message:
            Image(systemName: "text.badge.checkmark")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
    }

    private var label: String {
        switch model.state {
        case .working(let text), .success(let text), .failure(let text), .message(let text):
            return text
        }
    }
}

private struct BlurTransitionModifier: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content
            .blur(radius: radius)
            .opacity(opacity)
    }
}

private extension AnyTransition {
    static let mendBlur = AnyTransition.modifier(
        active: BlurTransitionModifier(
            radius: OverlayDesign.transitionBlurRadius,
            opacity: 0
        ),
        identity: BlurTransitionModifier(radius: 0, opacity: 1)
    )
}
