import Foundation

/// Every provider's API key in a single Keychain item, so macOS asks about
/// Mend once per build rather than once per provider.
struct ProviderKeyStore {
    static let service = "com.mend.api"
    static let account = "provider-keys"

    var keychain: any KeychainAccess = SystemKeychain()

    func load() -> [LLMProvider: String] {
        if let json = keychain.read(service: Self.service, account: Self.account) {
            return Self.decode(json)
        }
        return migrateLegacyItems()
    }

    func save(_ keys: [LLMProvider: String]) throws {
        let kept = keys.compactMapValues { key -> String? in
            let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        try keychain.save(Self.encode(kept), service: Self.service, account: Self.account)
    }

    // MARK: Legacy items

    /// Builds before 0.4 kept one item per provider, and the very first
    /// builds a single unnamed item. Read them once, write the combined item,
    /// and only then remove them.
    private func migrateLegacyItems() -> [LLMProvider: String] {
        var keys: [LLMProvider: String] = [:]
        for provider in LLMProvider.allCases {
            if let key = keychain.read(service: Self.service, account: Self.legacyAccount(for: provider)),
               !key.isEmpty {
                keys[provider] = key
            }
        }
        if keys.isEmpty,
           let original = keychain.read(service: Self.service, account: Self.originalAccount),
           !original.isEmpty {
            keys[.openAI] = original
        }
        guard !keys.isEmpty else { return [:] }

        do {
            try save(keys)
        } catch {
            return keys
        }
        for provider in LLMProvider.allCases {
            try? keychain.save("", service: Self.service, account: Self.legacyAccount(for: provider))
        }
        try? keychain.save("", service: Self.service, account: Self.originalAccount)
        return keys
    }

    static func legacyAccount(for provider: LLMProvider) -> String {
        "provider-key-\(provider.rawValue)"
    }

    static let originalAccount = "provider-key"

    // MARK: Encoding

    static func encode(_ keys: [LLMProvider: String]) -> String {
        guard !keys.isEmpty else { return "" }
        let byName = Dictionary(uniqueKeysWithValues: keys.map { ($0.key.rawValue, $0.value) })
        let data = (try? JSONEncoder().encode(byName)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ json: String) -> [LLMProvider: String] {
        guard let decoded = try? JSONDecoder().decode([String: String].self, from: Data(json.utf8)) else {
            return [:]
        }
        return decoded.reduce(into: [:]) { keys, entry in
            if let provider = LLMProvider(rawValue: entry.key), !entry.value.isEmpty {
                keys[provider] = entry.value
            }
        }
    }
}
