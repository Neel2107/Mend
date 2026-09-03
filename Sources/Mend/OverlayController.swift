import AppKit
import SwiftUI

// Change these values to explore the overlay without touching its behavior.
enum OverlayDesign {
    static let panelSize = NSSize(width: 272, height: 46)
    static let trailingMargin: CGFloat = 20
    static let bottomMargin: CGFloat = 18

    static let horizontalPadding: CGFloat = 13
    static let contentSpacing: CGFloat = 9
    static let iconSize: CGFloat = 18
    static let labelFontSize: CGFloat = 13
    static let shortcutFontSize: CGFloat = 10
    static let borderOpacity: CGFloat = 0.12
}

enum OverlayState: Equatable {
    case working(String)
    case success(String)
    case failure(String)
    case message(String)
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .working("Fixing grammar…")
    @Published var shortcutLabel = GlobalShortcut.default.displayString
}

final class NonActivatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class OverlayController {
    private let model = OverlayModel()
    private let panel: NonActivatingPanel
    private var hideTask: Task<Void, Never>?

    init() {
        panel = NonActivatingPanel(
            contentRect: NSRect(origin: .zero, size: OverlayDesign.panelSize),
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
    }

    func show(_ state: OverlayState, autoHideAfter seconds: Double? = nil) {
        hideTask?.cancel()
        model.state = state
        positionPanel()
        panel.orderFrontRegardless()

        if let seconds {
            hideTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    self?.panel.orderOut(nil)
                }
            }
        }
    }

    func updateShortcutLabel(_ label: String) {
        model.shortcutLabel = label
    }

    private func positionPanel() {
        // NSScreen.main follows the window of the currently active writing app.
        // The panel never activates Mend, so this remains the user's working screen.
        let screen = NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: frame.maxX - panel.frame.width - OverlayDesign.trailingMargin,
            y: frame.minY + OverlayDesign.bottomMargin
        )
        panel.setFrameOrigin(origin)
    }
}

private struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: OverlayDesign.contentSpacing) {
            icon
                .frame(width: OverlayDesign.iconSize, height: OverlayDesign.iconSize)

            Text(label)
                .font(.system(size: OverlayDesign.labelFontSize, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if case .working = model.state {
                Text(model.shortcutLabel)
                    .font(.system(size: OverlayDesign.shortcutFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, OverlayDesign.horizontalPadding)
        .frame(width: OverlayDesign.panelSize.width, height: OverlayDesign.panelSize.height)
        .background(.ultraThickMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(OverlayDesign.borderOpacity), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .working:
            ProgressView().controlSize(.mini)
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
