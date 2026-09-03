import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @State private var saveMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Endpoint", text: $settings.endpoint)
                        .textFieldStyle(.roundedBorder)
                    TextField("Model", text: $settings.model)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        SecureField("API key", text: $settings.apiKey)
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
                    Text("Mend supports OpenAI-compatible chat-completions endpoints. Your key is stored in macOS Keychain.")
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
                        Text("⌃⌥G")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                } header: {
                    Text("Shortcut")
                        .font(.headline)
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
                        try settings.save()
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
        .frame(minWidth: 500, minHeight: 510)
    }

    private var messageColor: Color {
        if saveMessage == "Saved" { return .green }
        if saveMessage == "Key pasted — save to apply" { return .secondary }
        return .red
    }
}
