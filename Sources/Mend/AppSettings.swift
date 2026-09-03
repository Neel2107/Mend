import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let defaultPrompt = """
    Correct grammar, spelling, punctuation, and awkward phrasing. Preserve the writer's meaning, tone, formatting, and level of formality. Make the smallest changes needed. Return only the corrected text.
    """

    private enum Key {
        static let endpoint = "apiEndpoint"
        static let model = "apiModel"
        static let prompt = "rewritePrompt"
    }

    @Published var endpoint: String
    @Published var model: String
    @Published var prompt: String
    @Published var apiKey: String

    init() {
        let defaults = UserDefaults.standard
        endpoint = defaults.string(forKey: Key.endpoint) ?? "https://api.openai.com/v1/chat/completions"
        model = defaults.string(forKey: Key.model) ?? "gpt-4.1-mini"
        prompt = defaults.string(forKey: Key.prompt) ?? Self.defaultPrompt
        apiKey = KeychainStore.read(service: "com.mend.api", account: "provider-key") ?? ""
    }

    var configuration: LLMConfiguration {
        LLMConfiguration(
            endpoint: endpoint.trimmingCharacters(in: .whitespacesAndNewlines),
            model: model.trimmingCharacters(in: .whitespacesAndNewlines),
            prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func save() throws {
        let defaults = UserDefaults.standard
        defaults.set(endpoint, forKey: Key.endpoint)
        defaults.set(model, forKey: Key.model)
        defaults.set(prompt, forKey: Key.prompt)
        try KeychainStore.save(apiKey, service: "com.mend.api", account: "provider-key")
    }
}
