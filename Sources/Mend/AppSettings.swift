import Combine
import Foundation

public enum LLMProvider: String, CaseIterable, Identifiable {
    case openAI
    case gemini
    case ollama
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Gemini"
        case .ollama: return "Ollama (Local)"
        case .custom: return "Custom"
        }
    }

    public var defaultEndpoint: String? {
        switch self {
        case .openAI:
            return "https://api.openai.com/v1/chat/completions"
        case .gemini:
            return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .ollama:
            return "http://127.0.0.1:11434/v1/chat/completions"
        case .custom:
            return nil
        }
    }

    public var defaultModel: String? {
        switch self {
        case .openAI: return "gpt-4.1-mini"
        case .gemini: return "gemini-3.5-flash-lite"
        case .ollama: return "llama3.2:3b"
        case .custom: return nil
        }
    }

    public var brand: ProviderBrand? {
        switch self {
        case .openAI: return .openAI
        case .gemini: return .gemini
        case .ollama, .custom: return nil
        }
    }
}

/// One thing Mend can do to a selection: an instruction and the shortcuts that run it.
public struct RewriteAction: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var prompt: String
    public var shortcuts: [GlobalShortcut]

    public init(id: UUID = UUID(), name: String, prompt: String, shortcuts: [GlobalShortcut]) {
        self.id = id
        self.name = name
        self.prompt = prompt
        self.shortcuts = shortcuts
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, prompt, shortcuts
        case legacyShortcut = "shortcut"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        prompt = try container.decode(String.self, forKey: .prompt)
        if let saved = try container.decodeIfPresent([GlobalShortcut].self, forKey: .shortcuts) {
            shortcuts = saved
        } else if let single = try container.decodeIfPresent(GlobalShortcut.self, forKey: .legacyShortcut) {
            shortcuts = [single]
        } else {
            shortcuts = []
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(prompt, forKey: .prompt)
        try container.encode(shortcuts, forKey: .shortcuts)
    }

    public mutating func addShortcut(_ shortcut: GlobalShortcut) {
        guard !shortcuts.contains(shortcut) else { return }
        shortcuts.append(shortcut)
    }

    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Rewrite" : trimmed
    }

    /// What the capsule shows while this action runs.
    public var workingLabel: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Rewriting…" : "\(trimmed)…"
    }

    public static func makeDefault() -> RewriteAction {
        RewriteAction(name: "Fix grammar", prompt: AppSettings.defaultPrompt, shortcuts: [.default])
    }
}

@MainActor
public final class AppSettings: ObservableObject {
    public nonisolated static let defaultPrompt = """
    Correct grammar, spelling, punctuation, and awkward phrasing. Preserve the writer's meaning, tone, formatting, and level of formality. Make the smallest changes needed. Return only the corrected text.
    """

    private enum Key {
        static let endpoint = "apiEndpoint"
        static let model = "apiModel"
        static let provider = "apiProvider"
        static let showsMenuBarIcon = "showsMenuBarIcon"
        static let actions = "rewriteActions"
        static let providerDrafts = "providerDrafts"
        static let customVocabulary = "customVocabulary"
        static let enableGhostDiff = "enableGhostDiff"
        static let enableStreaming = "enableStreaming"
        static let legacyPrompt = "rewritePrompt"
        static let legacyShortcut = "globalShortcut"
    }

    @Published public private(set) var provider: LLMProvider
    @Published public var endpoint: String
    @Published public var model: String
    @Published public var apiKey: String
    @Published public var actions: [RewriteAction]
    @Published public var customVocabulary: [String]
    @Published public var enableGhostDiff: Bool
    @Published public var enableStreaming: Bool
    @Published public private(set) var showsMenuBarIcon: Bool
    @Published public private(set) var launchesAtLogin: Bool

    public struct ProviderDraft: Codable, Equatable {
        public var endpoint: String
        public var model: String

        public init(endpoint: String, model: String) {
            self.endpoint = endpoint
            self.model = model
        }
    }

    private var draftAPIKeys: [LLMProvider: String] = [:]
    private var providerDrafts: [LLMProvider: ProviderDraft] = [:]
    private let defaults: UserDefaults
    private let keyStore: ProviderKeyStore
    private let usesKeychain: Bool
    private var cancellables: Set<AnyCancellable> = []

    public var changeHandler: (@MainActor () -> Void)?

    public init(
        readsAPIKeyFromKeychain: Bool = true,
        defaults: UserDefaults = .standard,
        keychain: any KeychainAccess = SystemKeychain()
    ) {
        self.defaults = defaults
        keyStore = ProviderKeyStore(keychain: keychain)
        usesKeychain = readsAPIKeyFromKeychain
        let savedEndpoint = defaults.string(forKey: Key.endpoint)
        let savedProviderValue = defaults.string(forKey: Key.provider)
        let savedProvider = savedProviderValue
            .flatMap(LLMProvider.init(rawValue:))
            ?? Self.inferProvider(from: savedEndpoint)
        let savedKeys = readsAPIKeyFromKeychain ? keyStore.load() : [:]

        provider = savedProvider
        endpoint = savedEndpoint ?? savedProvider.defaultEndpoint ?? ""
        let savedModel = defaults.string(forKey: Key.model)
        if savedProvider == .gemini && savedModel == "gemini-2.5-flash" {
            model = savedProvider.defaultModel ?? ""
        } else {
            model = savedModel ?? savedProvider.defaultModel ?? ""
        }
        actions = Self.loadActions(from: defaults)
        providerDrafts = Self.loadProviderDrafts(from: defaults)
        apiKey = savedKeys[savedProvider] ?? ""
        showsMenuBarIcon = defaults.object(forKey: Key.showsMenuBarIcon) as? Bool ?? true
        launchesAtLogin = LoginItem.isEnabled
        draftAPIKeys = savedKeys
        providerDrafts[savedProvider] = ProviderDraft(endpoint: endpoint, model: model)

        customVocabulary = defaults.stringArray(forKey: Key.customVocabulary) ?? []
        enableGhostDiff = defaults.object(forKey: Key.enableGhostDiff) as? Bool ?? false
        enableStreaming = defaults.object(forKey: Key.enableStreaming) as? Bool ?? true

        Publishers.MergeMany(
            $provider.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $endpoint.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $model.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $apiKey.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $actions.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $customVocabulary.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $enableGhostDiff.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            $enableStreaming.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] in
            Task { @MainActor in self?.changeHandler?() }
        }
        .store(in: &cancellables)
    }

    private static func loadProviderDrafts(from defaults: UserDefaults) -> [LLMProvider: ProviderDraft] {
        guard let data = defaults.data(forKey: Key.providerDrafts),
              let saved = try? JSONDecoder().decode([String: ProviderDraft].self, from: data) else {
            return [:]
        }
        var drafts: [LLMProvider: ProviderDraft] = [:]
        for (name, draft) in saved {
            if let provider = LLMProvider(rawValue: name) {
                drafts[provider] = draft
            }
        }
        return drafts
    }

    private static func loadActions(from defaults: UserDefaults) -> [RewriteAction] {
        if let data = defaults.data(forKey: Key.actions),
           let saved = try? JSONDecoder().decode([RewriteAction].self, from: data),
           !saved.isEmpty {
            return saved.map { action in
                var action = action
                if action.name == "New action" { action.name = "" }
                action.shortcuts.removeAll(where: \.isReservedForMend)
                return action
            }
        }

        var migrated = RewriteAction.makeDefault()
        if let prompt = defaults.string(forKey: Key.legacyPrompt) {
            migrated.prompt = prompt
        }
        if let data = defaults.data(forKey: Key.legacyShortcut),
           let shortcut = try? JSONDecoder().decode(GlobalShortcut.self, from: data) {
            migrated.shortcuts = [shortcut]
        }
        return [migrated]
    }

    // MARK: Actions

    public func addAction() {
        actions.append(RewriteAction(name: "", prompt: Self.defaultPrompt, shortcuts: []))
    }

    public func removeAction(id: UUID) {
        guard actions.count > 1 else { return }
        actions.removeAll { $0.id == id }
    }

    public func restoreDefaultActions() {
        actions = [RewriteAction.makeDefault()]
    }

    public func action(id: UUID) -> RewriteAction? {
        actions.first { $0.id == id }
    }

    public func isShortcutTaken(_ shortcut: GlobalShortcut) -> Bool {
        actions.contains { $0.shortcuts.contains(shortcut) }
    }

    @discardableResult
    public func setShortcut(_ new: GlobalShortcut?, replacing old: GlobalShortcut?, in actionID: UUID) -> Bool {
        guard let index = actions.firstIndex(where: { $0.id == actionID }) else { return false }
        var shortcuts = actions[index].shortcuts

        if let new, new.isReservedForMend { return false }
        if let new, new != old, isShortcutTaken(new) { return false }

        if let old, let position = shortcuts.firstIndex(of: old) {
            if let new {
                shortcuts[position] = new
            } else {
                shortcuts.remove(at: position)
            }
        } else if let new {
            shortcuts.append(new)
        }

        if shortcuts != actions[index].shortcuts {
            actions[index].shortcuts = shortcuts
        }
        return true
    }

    public func setupProblem(for action: RewriteAction) -> String? {
        if action.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a prompt for “\(action.displayName)” in Settings"
        }
        guard availableProviderConfigurations(prompt: action.prompt).isEmpty else { return nil }
        if endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add an endpoint in Settings"
        }
        if model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Add a model in Settings"
        }
        return "Add an API key in Settings"
    }

    // MARK: Menu bar and login

    public func setMenuBarIconVisible(_ isVisible: Bool) {
        showsMenuBarIcon = isVisible
        defaults.set(isVisible, forKey: Key.showsMenuBarIcon)
    }

    public func setLaunchesAtLogin(_ isEnabled: Bool) throws {
        try LoginItem.setEnabled(isEnabled)
        launchesAtLogin = LoginItem.isEnabled
    }

    // MARK: Providers

    public func selectProvider(_ newProvider: LLMProvider) {
        guard newProvider != provider else { return }

        draftAPIKeys[provider] = apiKey
        providerDrafts[provider] = ProviderDraft(endpoint: endpoint, model: model)
        provider = newProvider

        let draft = providerDrafts[newProvider]
        endpoint = draft?.endpoint ?? newProvider.defaultEndpoint ?? ""
        model = draft?.model ?? newProvider.defaultModel ?? ""

        apiKey = draftAPIKeys[newProvider] ?? ""
        draftAPIKeys[newProvider] = apiKey
    }

    public func availableProviderConfigurations(prompt: String) -> [ProviderConfiguration] {
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
                guard candidate != .custom, candidate != .ollama,
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
            // Local servers behind a custom or Ollama endpoint often need no key.
            let hasCredentials = !configuration.apiKey.isEmpty || candidate == .custom || candidate == .ollama
            guard hasCredentials, !configuration.endpoint.isEmpty, !configuration.model.isEmpty else { return nil }
            return ProviderConfiguration(provider: candidate, llm: configuration)
        }
    }

    public var hasUsableProvider: Bool {
        !availableProviderConfigurations(prompt: Self.defaultPrompt).isEmpty
    }

    private func storedAPIKey(for provider: LLMProvider) -> String {
        draftAPIKeys[provider] ?? ""
    }

    // MARK: Saving

    public func save() throws {
        defaults.set(endpoint, forKey: Key.endpoint)
        defaults.set(model, forKey: Key.model)
        defaults.set(provider.rawValue, forKey: Key.provider)
        defaults.set(try JSONEncoder().encode(actions), forKey: Key.actions)
        defaults.set(customVocabulary, forKey: Key.customVocabulary)
        defaults.set(enableGhostDiff, forKey: Key.enableGhostDiff)
        defaults.set(enableStreaming, forKey: Key.enableStreaming)
        providerDrafts[provider] = ProviderDraft(endpoint: endpoint, model: model)
        let draftsByName = Dictionary(uniqueKeysWithValues: providerDrafts.map { ($0.key.rawValue, $0.value) })
        defaults.set(try JSONEncoder().encode(draftsByName), forKey: Key.providerDrafts)
        draftAPIKeys[provider] = apiKey
        guard usesKeychain else { return }
        try keyStore.save(draftAPIKeys)
    }

    private static func inferProvider(from endpoint: String?) -> LLMProvider {
        guard let endpoint else { return .openAI }
        if endpoint == LLMProvider.gemini.defaultEndpoint { return .gemini }
        if endpoint == LLMProvider.ollama.defaultEndpoint || endpoint.contains("11434") { return .ollama }
        if endpoint != LLMProvider.openAI.defaultEndpoint { return .custom }
        return .openAI
    }
}
