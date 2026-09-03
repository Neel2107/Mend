import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onSave: @MainActor () throws -> Void
    @State private var saveMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Picker("Provider", selection: providerBinding) {
                        ForEach(LLMProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .pickerStyle(.segmented)

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
                    TextEditor(text: $settings.prompt)
                        .font(.system(size: 13))
                        .frame(minHeight: 130)
                        .padding(6)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
                        }
                } header: {
                    Text("Instruction")
                        .font(.headline)
                } footer: {
                    Text("The selected text is appended securely and treated as content rather than an instruction.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        Text("Rewrite selected text")
                        Spacer()
                        ShortcutRecorder(shortcut: $settings.shortcut) {
                            saveMessage = "Shortcut changed — save to apply"
                        }
                        Button("Reset") {
                            settings.shortcut = .default
                            saveMessage = "Shortcut changed — save to apply"
                        }
                        .buttonStyle(.borderless)
                    }
                } header: {
                    Text("Shortcut")
                        .font(.headline)
                } footer: {
                    Text("Page Up, Page Down, Home, End, and function keys work alone. Letter and number keys require Command, Control, or Option. Escape cancels recording.")
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
                Button("Restore Prompt") {
                    settings.prompt = AppSettings.defaultPrompt
                    saveMessage = ""
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
        .frame(minWidth: 500, minHeight: 640)
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
            return "Uses Google's OpenAI-compatible Gemini endpoint. Your Gemini key is stored separately in macOS Keychain."
        case .custom:
            return "Uses an OpenAI-compatible chat-completions endpoint. Its key is stored separately in macOS Keychain."
        }
    }
}

private struct ShortcutRecorder: View {
    @Binding var shortcut: GlobalShortcut
    let onChange: () -> Void

    @State private var isRecording = false
    @State private var eventMonitor: Any?

    var body: some View {
        Button {
            beginRecording()
        } label: {
            Text(isRecording ? "Press shortcut…" : shortcut.displayString)
                .font(.system(.body, design: .rounded).weight(.semibold))
                .frame(minWidth: 72)
        }
        .buttonStyle(.bordered)
        .onDisappear {
            stopRecording()
        }
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
