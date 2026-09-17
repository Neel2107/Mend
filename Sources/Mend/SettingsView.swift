import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onMenuBarVisibilityChange: @MainActor (Bool) -> Void
    let onCheckForUpdates: @MainActor () -> Void
    let onError: @MainActor (any Error) -> Void

    @State private var newVocabularyTerm: String = ""
    @State private var historyCount: Int = UndoVault.shared.allRecords().count

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Provider")
                    Spacer(minLength: 12)
                    APIProviderPicker(selection: providerBinding)
                        .frame(width: 380)
                }

                settingsField("Endpoint", text: $settings.endpoint)
                settingsField("Model", text: $settings.model)
                HStack(spacing: 8) {
                    SecureField(
                        settings.provider == .ollama ? "API key (optional for local)" : "\(settings.provider.displayName) API key",
                        text: $settings.apiKey
                    )
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
                Toggle("Real-time streaming preview", isOn: $settings.enableStreaming)
                Toggle("Show ghost diff before replacement", isOn: $settings.enableGhostDiff)
            } header: {
                Text("Intelligence & Feedback")
                    .font(.headline)
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Preserve these exact brand names, terms, or acronyms without modification:")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        TextField("Add protected term (e.g. Mend, Swift, Anthropic)", text: $newVocabularyTerm)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                addVocabularyTerm()
                            }
                        Button("Add") {
                            addVocabularyTerm()
                        }
                        .disabled(newVocabularyTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if !settings.customVocabulary.isEmpty {
                        FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                            ForEach(settings.customVocabulary, id: \.self) { term in
                                HStack(spacing: 4) {
                                    Text(term)
                                        .font(.caption.weight(.medium))
                                    Button {
                                        settings.customVocabulary.removeAll { $0 == term }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.borderless)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }
            } header: {
                Text("Protected Vocabulary")
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
                HStack {
                    Text("\(historyCount) rewrites saved in Undo Vault")
                    Spacer()
                    Button("Clear History") {
                        UndoVault.shared.clear()
                        historyCount = 0
                    }
                    .disabled(historyCount == 0)
                }
            } header: {
                Text("Undo History")
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
        .frame(minWidth: 540, minHeight: 700)
    }

    private func addVocabularyTerm() {
        let term = newVocabularyTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty, !settings.customVocabulary.contains(term) else { return }
        settings.customVocabulary.append(term)
        newVocabularyTerm = ""
    }

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

            FlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
                ForEach(action.shortcuts, id: \.self) { shortcut in
                    ShortcutRecorder(shortcut: shortcut) { onSetShortcut($0, shortcut) }
                }
                ShortcutRecorder(shortcut: nil, placeholder: "Add Shortcut") { onSetShortcut($0, nil) }
            }

            TextEditor(text: $action.prompt)
                .font(.body)
                .frame(minHeight: 54)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
                )
        }
        .padding(.vertical, 4)
    }
}

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 6
    var verticalSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        let rows = computeRows(subviews: subviews, totalWidth: width)
        let totalHeight = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * verticalSpacing
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(subviews: subviews, totalWidth: bounds.width)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (subviewIndex, size) in zip(row.indices, row.sizes) {
                subviews[subviewIndex].place(
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

    private func computeRows(subviews: Subviews, totalWidth: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let candidateWidth = row.width == 0 ? size.width : row.width + horizontalSpacing + size.width
            if candidateWidth > totalWidth && !row.indices.isEmpty {
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
                        } else if provider == .ollama {
                            Image(systemName: "cpu")
                                .font(.system(size: 11, weight: .medium))
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
        .padding(3)
        .background(
            Color.secondary.opacity(0.12),
            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
    }
}

private struct ShortcutRecorder: View {
    let shortcut: GlobalShortcut?
    var placeholder = "Record Shortcut"
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
