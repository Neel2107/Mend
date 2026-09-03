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

@MainActor
final class AppSettings: ObservableObject {
    static let defaultPrompt = """
    Correct grammar, spelling, punctuation, and awkward phrasing. Preserve the writer's meaning, tone, formatting, and level of formality. Make the smallest changes needed. Return only the corrected text.
    """

    private enum Key {
        static let endpoint = "apiEndpoint"
        static let model = "apiModel"
        static let prompt = "rewritePrompt"
        static let shortcut = "globalShortcut"
        static let provider = "apiProvider"
        static let showsMenuBarIcon = "showsMenuBarIcon"

        static func subscriptionEnabled(_ provider: SubscriptionProvider) -> String {
            "subscriptionProviderEnabled-\(provider.rawValue)"
        }
    }

    @Published private(set) var provider: LLMProvider
    @Published var endpoint: String
    @Published var model: String
    @Published var prompt: String
    @Published var apiKey: String
    @Published var shortcut: GlobalShortcut
    @Published private(set) var showsMenuBarIcon: Bool
    @Published private(set) var enabledSubscriptionProviders: Set<SubscriptionProvider>

    private var draftAPIKeys: [LLMProvider: String] = [:]
    private let readsAPIKeyFromKeychain: Bool

    init(readsAPIKeyFromKeychain: Bool = true) {
        self.readsAPIKeyFromKeychain = readsAPIKeyFromKeychain
        let defaults = UserDefaults.standard
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
        prompt = defaults.string(forKey: Key.prompt) ?? Self.defaultPrompt
        apiKey = savedAPIKey
        if let data = defaults.data(forKey: Key.shortcut),
           let savedShortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data) {
            shortcut = savedShortcut
        } else {
            shortcut = .default
        }
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
        enabledSubscriptionProviders = Set(
            SubscriptionProvider.allCases.filter { provider in
                let key = Key.subscriptionEnabled(provider)
                if let saved = defaults.object(forKey: key) as? Bool {
                    return saved
                }
                return provider.executableURL != nil
            }
        )
        draftAPIKeys[savedProvider] = savedAPIKey
    }

    func setMenuBarIconVisible(_ isVisible: Bool) {
        showsMenuBarIcon = isVisible
        UserDefaults.standard.set(isVisible, forKey: Key.showsMenuBarIcon)
    }

    func isSubscriptionProviderEnabled(_ provider: SubscriptionProvider) -> Bool {
        enabledSubscriptionProviders.contains(provider)
    }

    func setSubscriptionProvider(_ provider: SubscriptionProvider, enabled: Bool) {
        if enabled {
            enabledSubscriptionProviders.insert(provider)
        } else {
            enabledSubscriptionProviders.remove(provider)
        }
        UserDefaults.standard.set(enabled, forKey: Key.subscriptionEnabled(provider))
    }

    var availableSubscriptionConfigurations: [SubscriptionConfiguration] {
        SubscriptionProvider.availableConfigurations.filter {
            enabledSubscriptionProviders.contains($0.provider)
        }
    }

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
            ?? KeychainStore.read(service: "com.mend.api", account: Self.keyAccount(for: newProvider))
            ?? ""
        draftAPIKeys[newProvider] = apiKey
    }

    var configuration: LLMConfiguration {
        LLMConfiguration(
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    var availableProviderConfigurations: [ProviderConfiguration] {
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
            guard !configuration.apiKey.isEmpty else { return nil }
            return ProviderConfiguration(provider: candidate, llm: configuration)
        }
    }

    private func storedAPIKey(for provider: LLMProvider) -> String {
        if let cachedKey = draftAPIKeys[provider] {
            return cachedKey
        }
        guard readsAPIKeyFromKeychain else { return "" }

        let savedKey = KeychainStore.read(
            service: "com.mend.api",
            account: Self.keyAccount(for: provider)
        ) ?? ""
        draftAPIKeys[provider] = savedKey
        return savedKey
    }

    func save() throws {
        let defaults = UserDefaults.standard
        defaults.set(endpoint, forKey: Key.endpoint)
        defaults.set(model, forKey: Key.model)
        defaults.set(prompt, forKey: Key.prompt)
        defaults.set(provider.rawValue, forKey: Key.provider)
        defaults.set(try JSONEncoder().encode(shortcut), forKey: Key.shortcut)
        try KeychainStore.save(apiKey, service: "com.mend.api", account: Self.keyAccount(for: provider))
        draftAPIKeys[provider] = apiKey
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
