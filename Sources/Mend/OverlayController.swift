import AppKit
import SwiftUI

// Change these values to explore the overlay without touching its behavior.
enum OverlayDesign {
    static let initialPanelSize = NSSize(width: 210, height: 42)
    static let minimumPanelWidth: CGFloat = 88
    static let maximumPanelWidth: CGFloat = 340
    /// Errors and streaming text need room to be read.
    static let maximumFailurePanelWidth: CGFloat = 520
    static let trailingMargin: CGFloat = 20
    static let bottomMargin: CGFloat = 18
    /// Windows smaller than this get the screen corner instead of their own.
    static let minimumAnchorSize = NSSize(width: 360, height: 160)

    static let horizontalPadding: CGFloat = 11
    static let contentSpacing: CGFloat = 8
    static let iconSize: CGFloat = 17
    static let labelFontSize: CGFloat = 13
    static let resizeDuration: TimeInterval = 0.42
    static let contentTransitionDuration: TimeInterval = 0.24
    static let transitionBlurRadius: CGFloat = 5
    static let presentationDelayNanoseconds: UInt64 = 16_000_000
}

enum OverlayState: Equatable {
    case working(String)
    case streaming(partial: String, actionLabel: String)
    case diff(summary: String, actionLabel: String)
    case success(String)
    case failure(String)
    case message(String, symbol: String = "text.badge.checkmark")
}

@MainActor
final class OverlayModel: ObservableObject {
    nonisolated static let initialState = OverlayState.working("Fixing grammar…")

    @Published var state: OverlayState = initialState

    init(state: OverlayState = initialState) {
        self.state = state
    }
}

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
protocol OverlayPanelPresenting: AnyObject {
    var isVisible: Bool { get }
    func setOverlayFrame(_ frame: NSRect, animated: Bool)
    func setOverlayContentVisible(_ isVisible: Bool)
    func rebuildOverlayContent(using model: OverlayModel)
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

    func setOverlayContentVisible(_ isVisible: Bool) {
        alphaValue = isVisible ? 1 : 0
    }

    func rebuildOverlayContent(using model: OverlayModel) {
        contentView = NSHostingView(rootView: OverlayView(model: model))
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
    private var presentationTask: Task<Void, Never>?
    private var isPresentationPending = false

    /// The window the user is editing, in AppKit screen coordinates.
    var anchorFrame: NSRect?

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
        presentationTask?.cancel()
        let shouldAnimate = panel.isVisible && !isPresentationPending
        isPresentationPending = false

        if shouldAnimate {
            withAnimation(.easeInOut(duration: OverlayDesign.contentTransitionDuration)) {
                model.state = state
            }
        } else {
            model.state = state
        }

        resizeAndPositionPanel(for: state, animated: shouldAnimate)
        if !shouldAnimate {
            panel.setOverlayContentVisible(false)
            panel.rebuildOverlayContent(using: model)
            panel.prepareForPresentation()
            panel.showOverlay()
            isPresentationPending = true
            presentationTask = Task { [weak self] in
                try? await Task.sleep(
                    nanoseconds: OverlayDesign.presentationDelayNanoseconds
                )
                guard !Task.isCancelled, let self else { return }
                self.panel.prepareForPresentation()
                self.panel.setOverlayContentVisible(true)
                self.isPresentationPending = false
                self.presentationTask = nil
            }
        } else {
            panel.showOverlay()
        }

        if let seconds {
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.hideOverlay()
                }
            }
        }
    }

    func keepVisibleForNextState() {
        hideTask?.cancel()
        hideTask = nil
    }

    func waitForPendingPresentation() async {
        await presentationTask?.value
    }

    private func hideOverlay() {
        presentationTask?.cancel()
        presentationTask = nil
        isPresentationPending = false
        panel.setOverlayContentVisible(false)
        panel.hideOverlay()
    }

    private func resizeAndPositionPanel(for state: OverlayState, animated: Bool) {
        let screen = anchorFrame.flatMap { anchor in
            NSScreen.screens.first { $0.frame.intersects(anchor) }
        } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        let frame = Self.panelFrame(
            width: targetWidth(for: state),
            height: OverlayDesign.initialPanelSize.height,
            anchor: anchorFrame,
            within: visibleFrame
        )
        panel.setOverlayFrame(frame, animated: animated)
    }

    nonisolated static func panelFrame(width: CGFloat, height: CGFloat, anchor: NSRect?, within visibleFrame: NSRect) -> NSRect {
        var container = visibleFrame
        if let anchor,
           anchor.width >= OverlayDesign.minimumAnchorSize.width,
           anchor.height >= OverlayDesign.minimumAnchorSize.height {
            let visible = anchor.intersection(visibleFrame)
            if !visible.isNull,
               visible.width >= width + OverlayDesign.trailingMargin * 2,
               visible.height >= height + OverlayDesign.bottomMargin * 2 {
                container = visible
            }
        }

        return NSRect(
            x: container.maxX - width - OverlayDesign.trailingMargin,
            y: container.minY + OverlayDesign.bottomMargin,
            width: width,
            height: height
        )
    }

    private func targetWidth(for state: OverlayState) -> CGFloat {
        let label: String
        let maximumWidth: CGFloat
        switch state {
        case .failure(let text):
            label = text
            maximumWidth = OverlayDesign.maximumFailurePanelWidth
        case .working(let text), .success(let text), .message(let text, _):
            label = text
            maximumWidth = OverlayDesign.maximumPanelWidth
        case .streaming(let partial, let actionLabel):
            label = "\(actionLabel): \(partial)"
            maximumWidth = OverlayDesign.maximumFailurePanelWidth
        case .diff(let summary, let actionLabel):
            label = "\(actionLabel) · \(summary)"
            maximumWidth = OverlayDesign.maximumPanelWidth
        }

        let font = NSFont.systemFont(ofSize: OverlayDesign.labelFontSize, weight: .medium)
        let labelWidth = ceil((label as NSString).size(withAttributes: [.font: font]).width)
        let width = (OverlayDesign.horizontalPadding * 2)
            + OverlayDesign.iconSize
            + OverlayDesign.contentSpacing
            + labelWidth

        return min(max(width, OverlayDesign.minimumPanelWidth), maximumWidth)
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
        .modifier(CapsuleSurface())
        .animation(
            .easeInOut(duration: OverlayDesign.contentTransitionDuration),
            value: model.state
        )
    }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .working, .streaming:
            SearchingOrb()
        case .diff:
            Image(systemName: "plus.forwardslash.minus")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.cyan)
        case .success:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
        case .failure:
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
        case .message(_, let symbol):
            Image(systemName: symbol)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        }
    }

    private var label: String {
        switch model.state {
        case .working(let text), .success(let text), .failure(let text), .message(let text, _):
            return text
        case .streaming(let partial, let actionLabel):
            let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return "\(actionLabel)…"
            }
            let preview = trimmed.count > 24 ? "…" + String(trimmed.suffix(24)) : trimmed
            return "\(actionLabel): \(preview)"
        case .diff(let summary, let actionLabel):
            return "\(actionLabel) · \(summary)"
        }
    }
}

private struct CapsuleSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.ultraThickMaterial, in: Capsule())
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
