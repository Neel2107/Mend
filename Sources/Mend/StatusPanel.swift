import AppKit
import SwiftUI

/// The panel under the menu bar icon: what Mend is set up to do, anything
/// that needs attention before it can, and the way into Settings.
struct StatusPanelView: View {
    @ObservedObject var settings: AppSettings
    let isAccessibilityTrusted: Bool
    let onOpenSettings: @MainActor () -> Void
    let onRequestAccessibility: @MainActor () -> Void
    let onCheckForUpdates: @MainActor () -> Void
    let onQuit: @MainActor () -> Void

    /// Beyond this many actions the list scrolls instead of growing the panel.
    private static let visibleActions = 6
    private static let rowHeight: CGFloat = 38

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 12)
            actionList
            notes
            Divider()
                .padding(.top, 12)
                .padding(.bottom, 8)
            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 8)
        .frame(width: 316)
    }

    private var header: some View {
        HStack(spacing: 5) {
            Text("Mend")
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 12)
            if let brand = settings.provider.brand {
                ProviderLogo(brand: brand, size: 12, tint: .secondary)
            } else {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(providerLine)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var providerLine: String {
        let model = settings.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? settings.provider.displayName : "\(settings.provider.displayName) · \(model)"
    }

    private var actionList: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        let rows = VStack(spacing: 0) {
            ForEach(Array(settings.actions.enumerated()), id: \.element.id) { index, action in
                if index > 0 {
                    Divider()
                        .padding(.leading, 12)
                }
                ActionRow(action: action)
                    .frame(height: Self.rowHeight)
            }
        }
        return Group {
            if settings.actions.count > Self.visibleActions {
                // Half a row extra shows there is more to scroll to.
                ScrollView { rows }
                    .frame(height: Self.rowHeight * (CGFloat(Self.visibleActions) + 0.5))
            } else {
                rows
            }
        }
        .background(shape.fill(Color.primary.opacity(0.055)))
        .clipShape(shape)
    }

    @ViewBuilder private var notes: some View {
        if !isAccessibilityTrusted {
            note(
                "Mend needs Accessibility access to read and replace your selection.",
                button: "Allow…",
                action: onRequestAccessibility
            )
        }
        if let problem = settings.firstSetupProblem {
            note(problem, button: "Open", action: onOpenSettings)
        }
    }

    private func note(_ text: String, button: String, action: @escaping @MainActor () -> Void) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .frame(width: 16)
            Text(text)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(button, action: action)
                .controlSize(.small)
        }
        .font(.system(size: 11))
        .padding(.top, 10)
    }

    private var footer: some View {
        HStack(spacing: 2) {
            Button("Settings…", action: onOpenSettings)
                .keyboardShortcut(",")
            Button("Check for Updates…", action: onCheckForUpdates)
            Spacer()
            Button("Quit", action: onQuit)
                .keyboardShortcut("q")
        }
        .buttonStyle(QuietButtonStyle())
        // Let the button labels, not their hover backgrounds, line up with the content above.
        .padding(.horizontal, -7)
    }
}

/// One action and the shortcuts that run it. A legend, not a button: actions
/// work on the selection in another app, which a click here would take focus from.
private struct ActionRow: View {
    let action: RewriteAction

    var body: some View {
        HStack(spacing: 8) {
            Text(action.displayName)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(1)
            Spacer(minLength: 8)
            // The shortcut side keeps its size; a long name gives way and truncates.
            Group {
                if let first = action.shortcuts.first {
                    Keycaps(shortcut: first)
                    // One shortcut fits beside any name; further ones are counted.
                    if action.shortcuts.count > 1 {
                        Text("+\(action.shortcuts.count - 1)")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No shortcut")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        let shortcuts = action.shortcuts.map(\.displayString).joined(separator: ", ")
        return shortcuts.isEmpty ? "\(action.displayName), no shortcut" : "\(action.displayName), \(shortcuts)"
    }
}

private struct Keycaps: View {
    let shortcut: GlobalShortcut

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(shortcut.keycaps.enumerated()), id: \.offset) { _, cap in
                Text(cap)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .frame(minWidth: 18, minHeight: 18)
                    // Named keys such as Space need room; single glyphs sit in a square.
                    .padding(.horizontal, cap.count > 1 ? 4 : 0)
                    .background(
                        RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                            .fill(Color.primary.opacity(0.1))
                    )
            }
        }
    }
}

/// Text that only shows itself to be a button on hover, for the panel's footer.
private struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Label(configuration: configuration)
    }

    private struct Label: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12))
                .foregroundStyle(isHovering ? .primary : .secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.14 : isHovering ? 0.08 : 0))
                )
                .contentShape(Rectangle())
                .onHover { isHovering = $0 }
        }
    }
}

/// Shows `StatusPanelView` in a popover under the menu bar icon.
@MainActor
final class StatusPanelController: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private let makeContent: @MainActor () -> StatusPanelView
    private var closedAt = Date.distantPast

    init(makeContent: @escaping @MainActor () -> StatusPanelView) {
        self.makeContent = makeContent
        super.init()
        popover.behavior = .transient
        popover.delegate = self
    }

    func toggle(below button: NSStatusBarButton) {
        if popover.isShown {
            close()
            return
        }
        // A click on the icon while the panel is open dismisses it, since it
        // is transient, and then arrives here; without this it would reopen.
        guard Date().timeIntervalSince(closedAt) > 0.25 else { return }

        // Built on every open so it shows the Accessibility permission as it is now.
        let host = NSHostingController(rootView: makeContent())
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host

        NSApplication.shared.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        host.view.window?.makeKey()
    }

    func close() {
        popover.performClose(nil)
    }

    func popoverDidClose(_ notification: Notification) {
        closedAt = Date()
    }
}
