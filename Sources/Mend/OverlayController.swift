import AppKit
import SwiftUI

enum OverlayState: Equatable {
    case working(String)
    case success(String)
    case failure(String)
    case message(String)
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .working("Fixing grammar…")
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
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 54),
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

    private func positionPanel() {
        // NSScreen.main follows the window of the currently active writing app.
        // The panel never activates Mend, so this remains the user's working screen.
        let screen = NSScreen.main
        guard let frame = screen?.visibleFrame else { return }

        let origin = NSPoint(
            x: frame.midX - panel.frame.width / 2,
            y: frame.minY + 24
        )
        panel.setFrameOrigin(origin)
    }
}

private struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 22, height: 22)

            Text(label)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            if case .working = model.state {
                Text("⌃⌥G to cancel")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 330, height: 54)
        .background(.ultraThickMaterial, in: Capsule())
        .overlay {
            Capsule().strokeBorder(.white.opacity(0.13), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch model.state {
        case .working:
            ProgressView().controlSize(.small)
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
