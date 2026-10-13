import Foundation

/// Every provider's API key in a single Keychain item, so macOS asks about
/// Mend once per build rather than once per provider.
struct ProviderKeyStore {
    static let service = "com.mend.api"
    static let account = "provider-keys"

    var keychain: any KeychainAccess = SystemKeychain()

    /// The keys a read returned, and whether that is all of them.
    struct StoredKeys: Equatable {
        var keys: [LLMProvider: String] = [:]
        /// False when the Keychain refused a read. More keys may be stored
        /// than were returned, so nothing may be written over them.
        var isComplete = true
    }

    func load() -> StoredKeys {
        switch keychain.read(service: Self.service, account: Self.account) {
        case .value(let json):
            return StoredKeys(keys: Self.decode(json))
        case .unavailable:
            return StoredKeys(isComplete: false)
        case .missing:
            return migrateLegacyItems()
        }
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
    private func migrateLegacyItems() -> StoredKeys {
        var stored = StoredKeys()
        for provider in LLMProvider.allCases {
            switch keychain.read(service: Self.service, account: Self.legacyAccount(for: provider)) {
            case .value(let key):
                if !key.isEmpty { stored.keys[provider] = key }
            case .missing:
                continue
            case .unavailable:
                stored.isComplete = false
            }
            // One refusal is an answer; do not ask again for each provider.
            if !stored.isComplete { break }
        }
        if stored.isComplete, stored.keys.isEmpty {
            switch keychain.read(service: Self.service, account: Self.originalAccount) {
            case .value(let original):
                if !original.isEmpty { stored.keys[.openAI] = original }
            case .missing:
                break
            case .unavailable:
                stored.isComplete = false
            }
        }
        // Combining is only safe when every item was read: one that was
        // refused would be missing from the new item and then deleted. A
        // partial answer is treated as none, so callers have one case to handle.
        guard stored.isComplete else { return StoredKeys(isComplete: false) }
        guard !stored.keys.isEmpty else { return stored }

        do {
            try save(stored.keys)
        } catch {
            return stored
        }
        for provider in LLMProvider.allCases {
            try? keychain.save("", service: Self.service, account: Self.legacyAccount(for: provider))
        }
        try? keychain.save("", service: Self.service, account: Self.originalAccount)
        return stored
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
