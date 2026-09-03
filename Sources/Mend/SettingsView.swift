import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onSave: @MainActor () throws -> Void
    let onMenuBarVisibilityChange: @MainActor (Bool) -> Void
    @State private var saveMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack {
                        Text("Provider")
                        Spacer(minLength: 12)
                        APIProviderPicker(selection: providerBinding)
                            .frame(width: 320)
                    }

                    TextField("Endpoint", text: $settings.endpoint)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        SecureField("\(settings.provider.displayName) API key", text: $settings.apiKey)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            if let key = NSPasteboard.general.string(forType: .string) {
                                settings.apiKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
                                saveMessage = "Key pasted — save to apply"
                            }
                        } label: {
                            Label("Paste", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                    }
                } header: {
                    Text("Provider")
                        .font(.headline)
                } footer: {
                    Text(providerHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach($settings.actions) { $action in
                        ActionEditor(
                            action: $action,
                            canRemove: settings.actions.count > 1,
                            onShortcutChange: { saveMessage = "Shortcut changed — save to apply" },
                            onRemove: { settings.removeAction(id: action.id) }
                        )
                    }

                    Button {
                        settings.addAction()
                    } label: {
                        Label("Add Action", systemImage: "plus")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("Actions")
                        .font(.headline)
                } footer: {
                    Text("Each action has its own instruction and one or more shortcuts. The selected text is appended securely and treated as content rather than an instruction.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Show Mend in the menu bar", isOn: menuBarVisibilityBinding)
                    Toggle("Open Mend at login", isOn: launchAtLoginBinding)
                } header: {
                    Text("Controls")
                        .font(.headline)
                } footer: {
                    Text("Navigation and function keys work alone; letters and numbers need a modifier. Escape cancels recording. If the icon is hidden, search for Mend in Spotlight or Raycast.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !saveMessage.isEmpty {
                    Text(saveMessage)
                        .font(.caption)
                        .foregroundStyle(messageColor)
                }
                Spacer()
                Button("Restore Defaults") {
                    settings.restoreDefaultActions()
                    saveMessage = "Actions restored — save to apply"
                }
                Button("Save") {
                    do {
                        try onSave()
                        saveMessage = "Saved"
                    } catch {
                        saveMessage = error.localizedDescription
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.bar)
        }
        .frame(minWidth: 500, minHeight: 700)
    }

    private var messageColor: Color {
        if saveMessage == "Saved" { return .green }
        if saveMessage.contains("save to apply") { return .secondary }
        return .red
    }

    private var providerBinding: Binding<LLMProvider> {
        Binding(
            get: { settings.provider },
            set: { provider in
                settings.selectProvider(provider)
                saveMessage = "Provider changed — add its API key and save to apply"
            }
        )
    }

    private var providerHelp: String {
        switch settings.provider {
        case .openAI:
            return "Uses OpenAI's chat-completions API. Your key is stored in macOS Keychain."
        case .gemini:
            return "Uses Google's OpenAI-compatible Gemini endpoint. Your key is stored in macOS Keychain."
        case .custom:
            return "Uses an OpenAI-compatible chat-completions endpoint. Leave the key empty for local servers that do not need one."
        }
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
                    saveMessage = ""
                } catch {
                    saveMessage = error.localizedDescription
                }
            }
        )
    }
}

private struct ActionEditor: View {
    @Binding var action: RewriteAction
    let canRemove: Bool
    let onShortcutChange: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("Name, shown in the capsule while it runs", text: $action.name)
                    .textFieldStyle(.roundedBorder)
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(!canRemove)
                .help("Remove this action")
            }

            HStack(spacing: 6) {
                ForEach(action.shortcuts, id: \.self) { shortcut in
                    ShortcutRecorder(shortcut: binding(for: shortcut), onChange: onShortcutChange)
                }
                ShortcutRecorder(shortcut: newShortcutBinding, placeholder: "Add Shortcut", onChange: onShortcutChange)
            }

            TextEditor(text: $action.prompt)
                .font(.system(size: 13))
                .frame(minHeight: 96)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                }
        }
        .padding(.vertical, 4)
    }

    /// Edits one existing shortcut in place; clearing it removes it.
    private func binding(for shortcut: GlobalShortcut) -> Binding<GlobalShortcut?> {
        Binding(
            get: { shortcut },
            set: { replacement in
                guard let index = action.shortcuts.firstIndex(of: shortcut) else { return }
                if let replacement {
                    action.shortcuts[index] = replacement
                } else {
                    action.shortcuts.remove(at: index)
                }
            }
        )
    }

    private var newShortcutBinding: Binding<GlobalShortcut?> {
        Binding(
            get: { nil },
            set: { recorded in
                if let recorded { action.addShortcut(recorded) }
            }
        )
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
    @Binding var shortcut: GlobalShortcut?
    var placeholder = "Record Shortcut"
    let onChange: () -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

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
                    shortcut = nil
                    onChange()
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
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }

            guard let newShortcut = GlobalShortcut(event: event) else {
                NSSound.beep()
                return nil
            }

            shortcut = newShortcut
            onChange()
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }
        isRecording = false
    }
}
