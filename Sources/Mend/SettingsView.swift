import AppKit
import Carbon
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    let onSave: @MainActor () throws -> Void
    let onMenuBarVisibilityChange: @MainActor (Bool) -> Void
    @State private var saveMessage = ""
    @State private var providerRefreshID = UUID()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    ForEach(SubscriptionProvider.allCases) { provider in
                        SubscriptionProviderRow(
                            provider: provider,
                            isEnabled: subscriptionBinding(for: provider),
                            refreshID: providerRefreshID
                        )
                    }
                } header: {
                    HStack {
                        Text("Providers")
                            .font(.headline)
                        Spacer()
                        Button {
                            providerRefreshID = UUID()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh provider status")
                    }
                } footer: {
                    Text("Enabled subscription providers are tried from top to bottom before API providers. Their existing CLI login is used; Mend never reads or stores subscription credentials.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

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
                    Text("API fallback")
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

                    Toggle("Show Mend in the menu bar", isOn: menuBarVisibilityBinding)
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
        .frame(minWidth: 500, minHeight: 780)
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

    private func subscriptionBinding(for provider: SubscriptionProvider) -> Binding<Bool> {
        Binding(
            get: { settings.isSubscriptionProviderEnabled(provider) },
            set: { isEnabled in
                settings.setSubscriptionProvider(provider, enabled: isEnabled)
                saveMessage = "Provider priority updated"
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

    private var menuBarVisibilityBinding: Binding<Bool> {
        Binding(
            get: { settings.showsMenuBarIcon },
            set: { onMenuBarVisibilityChange($0) }
        )
    }
}

private struct SubscriptionProviderRow: View {
    let provider: SubscriptionProvider
    @Binding var isEnabled: Bool
    let refreshID: UUID

    @State private var status: SubscriptionStatus?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ProviderLogo(brand: provider.brand, size: 22)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(provider.settingsName)
                        .font(.body.weight(.semibold))
                    if let version = status?.version {
                        Text(version)
                            .font(.system(.callout, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(statusDescription)
                    .font(.callout)
                    .foregroundStyle(statusColor)
            }

            Spacer(minLength: 12)

            Toggle("", isOn: $isEnabled)
                .labelsHidden()
                .disabled(provider.executableURL == nil)
        }
        .padding(.vertical, 4)
        .task(id: refreshID) {
            status = await provider.inspectStatus()
        }
    }

    private var statusDescription: String {
        guard provider.executableURL != nil else { return "Not installed" }
        guard isEnabled else { return "Disabled" }
        guard let status else { return "Checking authentication…" }

        switch status.authentication {
        case .subscription(let label): return "Authenticated · \(label)"
        case .apiKey: return "API key login · subscription mode unavailable"
        case .notAuthenticated: return "Not authenticated · run \(provider.loginCommand)"
        case .unknown: return "Authentication could not be verified"
        }
    }

    private var statusColor: Color {
        guard provider.executableURL != nil, isEnabled else { return .secondary }
        guard let status else { return .secondary }
        if case .subscription = status.authentication { return .secondary }
        return .orange
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
