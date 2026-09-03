import Foundation

enum LLMProvider: String, CaseIterable, Identifiable {
    case openAI
    case gemini
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .custom: return "Custom"
        }
    }

    var defaultEndpoint: String? {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .custom:
            return nil
        }
    }

    var defaultModel: String? {
        switch self {
        case .openAI: return "gpt-4.1-mini"
        case .gemini: return "gemini-3.5-flash-lite"
        case .custom: return nil
        }
    }

    var brand: ProviderBrand? {
        switch self {
        case .openAI: return .openAI
        case .gemini: return .gemini
        case .custom: return nil
        }
    }
}

/// One thing Mend can do to a selection: an instruction and the shortcut that runs it.
struct RewriteAction: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var prompt: String
    var shortcut: GlobalShortcut?

    init(id: UUID = UUID(), name: String, prompt: String, shortcut: GlobalShortcut?) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.shortcut = shortcut
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Rewrite" : trimmed
    }

    /// What the overlay shows while this action runs.
    var workingLabel: String { "\(displayName)…" }

    static func makeDefault() -> RewriteAction {
        RewriteAction(name: "Fix grammar", prompt: AppSettings.defaultPrompt, shortcut: .default)
    }
}

@MainActor
final class AppSettings: ObservableObject {
    nonisolated static let defaultPrompt = """
    Correct grammar, spelling, punctuation, and awkward phrasing. Preserve the writer's meaning, tone, formatting, and level of formality. Make the smallest changes needed. Return only the corrected text.
    """

    private enum Key {
        static let endpoint = "apiEndpoint"
        static let model = "apiModel"
        static let provider = "apiProvider"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let actions = "rewriteActions"
        // Settings from before actions existed. Read once for migration.
        static let legacyPrompt = "rewritePrompt"
        static let legacyShortcut = "globalShortcut"
    }

    @Published private(set) var provider: LLMProvider
    @Published var endpoint: String
    @Published var model: String
    @Published var apiKey: String
    @Published var actions: [RewriteAction]
    @Published private(set) var showsMenuBarIcon: Bool
    @Published private(set) var launchesAtLogin: Bool

    private var draftAPIKeys: [LLMProvider: String] = [:]
    private let defaults: UserDefaults
    private let usesKeychain: Bool

    init(readsAPIKeyFromKeychain: Bool = true, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        usesKeychain = readsAPIKeyFromKeychain
        let savedEndpoint = defaults.string(forKey: Key.endpoint)
        let savedProviderValue = defaults.string(forKey: Key.provider)
        let savedProvider = savedProviderValue
            .flatMap(LLMProvider.init(rawValue:))
            ?? Self.inferProvider(from: savedEndpoint)
        let savedAPIKey: String
        if readsAPIKeyFromKeychain {
            savedAPIKey = KeychainStore.read(
                service: "com.mend.api",
                account: Self.keyAccount(for: savedProvider)
            ) ?? (savedProviderValue == nil
                ? KeychainStore.read(service: "com.mend.api", account: "provider-key")
                : nil) ?? ""
        } else {
            savedAPIKey = ""
        }

        provider = savedProvider
        endpoint = savedEndpoint ?? savedProvider.defaultEndpoint ?? ""
        let savedModel = defaults.string(forKey: Key.model)
        if savedProvider == .gemini && savedModel == "gemini-2.5-flash" {
            model = savedProvider.defaultModel ?? ""
        } else {
            model = savedModel ?? savedProvider.defaultModel ?? ""
        }
        actions = Self.loadActions(from: defaults)
        apiKey = savedAPIKey
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
        launchesAtLogin = LoginItem.isEnabled
        draftAPIKeys[savedProvider] = savedAPIKey
    }

    private static func loadActions(from defaults: UserDefaults) -> [RewriteAction] {
        if let data = defaults.data(forKey: Key.actions),
           let saved = try? JSONDecoder().decode([RewriteAction].self, from: data),
           !saved.isEmpty {
            return saved
        }

        var migrated = RewriteAction.makeDefault()
        if let prompt = defaults.string(forKey: Key.legacyPrompt) {
            migrated.prompt = prompt
        }
        if let data = defaults.data(forKey: Key.legacyShortcut),
           let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data) {
            migrated.shortcut = shortcut
        }
        return [migrated]
    }

    // MARK: Actions

    func addAction() {
        actions.append(RewriteAction(name: "New action", prompt: Self.defaultPrompt, shortcut: nil))
    }

    func removeAction(id: UUID) {
        guard actions.count > 1 else { return }
        actions.removeAll { $0.id == id }
    }

    func restoreDefaultActions() {
        actions = [RewriteAction.makeDefault()]
    }

    func action(id: UUID) -> RewriteAction? {
        actions.first { $0.id == id }
    }

    // MARK: Menu bar and login

    func setMenuBarIconVisible(_ isVisible: Bool) {
        showsMenuBarIcon = isVisible
        defaults.set(isVisible, forKey: Key.showsMenuBarIcon)
    }

    func setLaunchesAtLogin(_ isEnabled: Bool) throws {
        try LoginItem.setEnabled(isEnabled)
        launchesAtLogin = LoginItem.isEnabled
    }

    // MARK: Providers

    func selectProvider(_ newProvider: LLMProvider) {
        guard newProvider != provider else { return }

        draftAPIKeys[provider] = apiKey
        provider = newProvider

        if let defaultEndpoint = newProvider.defaultEndpoint {
            endpoint = defaultEndpoint
        }
        if let defaultModel = newProvider.defaultModel {
            model = defaultModel
        }

        apiKey = draftAPIKeys[newProvider]
            ?? (usesKeychain
                ? KeychainStore.read(service: "com.mend.api", account: Self.keyAccount(for: newProvider))
                : nil)
            ?? ""
        draftAPIKeys[newProvider] = apiKey
    }

    /// The providers worth trying for one action, the selected one first.
    func availableProviderConfigurations(prompt: String) -> [ProviderConfiguration] {
        let providers = [provider] + LLMProvider.allCases.filter { $0 != provider }
        let sharedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        return providers.compactMap { candidate in
            let candidateEndpoint: String
            let candidateModel: String
            let candidateAPIKey: String

            if candidate == provider {
                candidateEndpoint = endpoint
                candidateModel = model
                candidateAPIKey = apiKey
            } else {
                guard candidate != .custom,
                      let defaultEndpoint = candidate.defaultEndpoint,
                      let defaultModel = candidate.defaultModel else {
                    return nil
                }
                candidateEndpoint = defaultEndpoint
                candidateModel = defaultModel
                candidateAPIKey = storedAPIKey(for: candidate)
            }

            let configuration = LLMConfiguration(
                endpoint: candidateEndpoint.trimmingCharacters(in: .whitespacesAndNewlines),
                model: candidateModel.trimmingCharacters(in: .whitespacesAndNewlines),
                prompt: sharedPrompt,
                apiKey: candidateAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            // Local servers behind a custom endpoint often need no key.
            let hasCredentials = !configuration.apiKey.isEmpty || candidate == .custom
            guard hasCredentials, !configuration.endpoint.isEmpty else { return nil }
            return ProviderConfiguration(provider: candidate, llm: configuration)
        }
    }

    var hasUsableProvider: Bool {
        !availableProviderConfigurations(prompt: Self.defaultPrompt).isEmpty
    }

    private func storedAPIKey(for provider: LLMProvider) -> String {
        if let cachedKey = draftAPIKeys[provider] {
            return cachedKey
        }
        guard usesKeychain else { return "" }

        let savedKey = KeychainStore.read(
            service: "com.mend.api",
            account: Self.keyAccount(for: provider)
        ) ?? ""
        draftAPIKeys[provider] = savedKey
        return savedKey
    }

    // MARK: Saving

    func save() throws {
        defaults.set(endpoint, forKey: Key.endpoint)
        defaults.set(model, forKey: Key.model)
        defaults.set(provider.rawValue, forKey: Key.provider)
        defaults.set(try JSONEncoder().encode(actions), forKey: Key.actions)
        draftAPIKeys[provider] = apiKey
        guard usesKeychain else { return }
        // Keys typed for other providers before switching back are kept too.
        for (candidate, key) in draftAPIKeys {
            try KeychainStore.save(key, service: "com.mend.api", account: Self.keyAccount(for: candidate))
        }
    }

    private static func keyAccount(for provider: LLMProvider) -> String {
        "provider-key-\(provider.rawValue)"
    }

    private static func inferProvider(from endpoint: String?) -> LLMProvider {
        guard let endpoint else { return .openAI }
        if endpoint == LLMProvider.gemini.defaultEndpoint { return .gemini }
        if endpoint != LLMProvider.openAI.defaultEndpoint { return .custom }
        return .openAI
    }
}
