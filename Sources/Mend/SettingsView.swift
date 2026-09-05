import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onMenuBarVisibilityChange: @MainActor (Bool) -> Void
    let onCheckForUpdates: @MainActor () -> Void
    let onError: @MainActor (any Error) -> Void

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Provider")
                    Spacer(minLength: 12)
                    APIProviderPicker(selection: providerBinding)
                        .frame(width: 320)
                }

                settingsField("Endpoint", text: $settings.endpoint)
                settingsField("Model", text: $settings.model)
                HStack(spacing: 8) {
                    SecureField("\(settings.provider.displayName) API key", text: $settings.apiKey)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        if let key = NSPasteboard.general.string(forType: .string) {
                            settings.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Provider")
                    .font(.headline)
            }

            Section {
                ForEach($settings.actions) { $action in
                    ActionEditor(
                        action: $action,
                        canRemove: settings.actions.count > 1,
                        onRemove: { settings.removeAction(id: action.id) },
                        onSetShortcut: { new, old in settings.setShortcut(new, replacing: old, in: action.id) }
                    )
                }

                HStack {
                    Button {
                        settings.addAction()
                    } label: {
                        Label("Add Action", systemImage: "plus")
                    }
                    Spacer()
                    Button("Restore Defaults") {
                        settings.restoreDefaultActions()
                    }
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Actions")
                    .font(.headline)
            }

            Section {
                Toggle("Show Mend in the menu bar", isOn: menuBarVisibilityBinding)
                Toggle("Open Mend at login", isOn: launchAtLoginBinding)
                HStack {
                    Text("Version \(UpdateChecker.currentVersion.description)")
                    Spacer()
                    Button("Check for Updates…", action: onCheckForUpdates)
                }
            } header: {
                Text("Controls")
                    .font(.headline)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 500, minHeight: 640)
    }

    /// A labeled field that keeps its label beside it however long the value is.
    private func settingsField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            TextField(label, text: text)
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 520)
        }
    }

    private var providerBinding: Binding<LLMProvider> {
        Binding(
            get: { settings.provider },
            set: { settings.selectProvider($0) }
        )
    }

    private var menuBarVisibilityBinding: Binding<Bool> {
        Binding(
            get: { settings.showsMenuBarIcon },
            set: { onMenuBarVisibilityChange($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { settings.launchesAtLogin },
            set: { isEnabled in
                do {
                    try settings.setLaunchesAtLogin(isEnabled)
                } catch {
                    onError(error)
                }
            }
        )
    }
}

private struct ActionEditor: View {
    @Binding var action: RewriteAction
    let canRemove: Bool
    let onRemove: () -> Void
    /// Applies one shortcut change; false means the combination is taken.
    let onSetShortcut: (_ new: GlobalShortcut?, _ old: GlobalShortcut?) -> Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Name", text: $action.name)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
                .help("Remove this action")
            }

            // Wraps so any number of shortcuts fits the window's width.
            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(action.shortcuts, id: \.self) { shortcut in
                    ShortcutRecorder(shortcut: shortcut) { onSetShortcut($0, shortcut) }
                }
                ShortcutRecorder(shortcut: nil, placeholder: "Add Shortcut") { onSetShortcut($0, nil) }
            }

            TextEditor(text: $action.prompt)
                .font(.system(size: 13))
                .frame(minHeight: 96, maxHeight: 240)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
        }
        .padding(.vertical, 4)
    }
}

/// Lays children out left to right and starts a new row when one would not fit.
private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + verticalSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for (index, size) in zip(row.indices, row.sizes) {
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + horizontalSpacing
            }
            y += row.height + verticalSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var sizes: [CGSize] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let needed = row.indices.isEmpty ? size.width : row.width + horizontalSpacing + size.width
            if !row.indices.isEmpty, needed > width {
                rows.append(row)
                row = Row()
            }
            row.indices.append(index)
            row.sizes.append(size)
            row.width = row.indices.count == 1 ? size.width : row.width + horizontalSpacing + size.width
            row.height = max(row.height, size.height)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

private struct APIProviderPicker: View {
    @Binding var selection: LLMProvider

    var body: some View {
        HStack(spacing: 2) {
            ForEach(LLMProvider.allCases) { provider in
                Button {
                    selection = provider
                } label: {
                    HStack(spacing: 5) {
                        if let brand = provider.brand {
                            ProviderLogo(
                                brand: brand,
                                size: 14,
                                tint: selection == provider ? .white : .primary
                            )
                        } else {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .medium))
                        }
                        Text(provider.displayName)
                            .font(.callout)
                    }
                    .foregroundStyle(selection == provider ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .background(
                        selection == provider ? Color.accentColor : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == provider ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        }
    }
}

private struct ShortcutRecorder: View {
    let shortcut: GlobalShortcut?
    var placeholder = "Record Shortcut"
    /// Receives the recorded shortcut, or nil to clear. False means it was refused.
    let onChange: (GlobalShortcut?) -> Bool

    @State private var isRecording = false
    @State private var eventMonitor: Any?
    @State private var focusObserver: (any NSObjectProtocol)?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                beginRecording()
            } label: {
                Text(label)
                    .font(.system(.body, design: .rounded).weight(.semibold))
                    .frame(minWidth: 72)
            }
            .buttonStyle(.bordered)

            if shortcut != nil {
                Button {
                    _ = onChange(nil)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Clear the shortcut")
            }
        }
        .onDisappear {
            stopRecording()
        }
    }

    private var label: String {
        if isRecording { return "Press shortcut…" }
        return shortcut?.displayString ?? placeholder
    }

    private func beginRecording() {
        stopRecording()
        isRecording = true
        // A click anywhere, including on another recorder, ends this one so
        // two chips never listen at once; so does the window losing focus.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
            guard event.type == .keyDown else {
                stopRecording()
                return event
            }
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            guard let newShortcut = GlobalShortcut(event: event), onChange(newShortcut) else {
                NSSound.beep()
                return nil
            }

            stopRecording()
            return nil
        }
        focusObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: nil,
            queue: .main
        ) { _ in
            stopRecording()
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        if let focusObserver {
            NotificationCenter.default.removeObserver(focusObserver)
            self.focusObserver = nil
        }
        isRecording = false
    }
}
