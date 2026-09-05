import Carbon
import Foundation
@testable import Mend
import Testing

/// An in-memory keychain that records every read, so tests can count prompts.
private final class FakeKeychain: KeychainAccess {
    var items: [String: String]
    private(set) var reads: [String] = []

    init(items: [String: String] = [:]) {
        self.items = items
    }

    func read(service: String, account: String) -> String? {
        reads.append(account)
        return items[account]
    }

    func save(_ value: String, service: String, account: String) throws {
        if value.isEmpty {
            items.removeValue(forKey: account)
        } else {
            items[account] = value
        }
    }
}

@MainActor
@Suite("App settings")
struct AppSettingsTests {
    private func makeDefaults() -> UserDefaults {
        let name = "MendTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeSettings(_ defaults: UserDefaults) -> AppSettings {
        AppSettings(readsAPIKeyFromKeychain: false, defaults: defaults)
    }

    @Test("A fresh install starts with the grammar action on the default shortcut")
    func testDefaultAction() {
        let settings = makeSettings(makeDefaults())

        #expect(settings.actions.count == 1)
        #expect(settings.actions[0].name == "Fix grammar")
        #expect(settings.actions[0].prompt == AppSettings.defaultPrompt)
        #expect(settings.actions[0].shortcuts == [.default])
        #expect(settings.actions[0].workingLabel == "Fix grammar…")
    }

    @Test("The old single prompt and shortcut become the first action")
    func testLegacyMigration() throws {
        let defaults = makeDefaults()
        let shortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "M")
        defaults.set("Translate to French.", forKey: "rewritePrompt")
        defaults.set(try JSONEncoder().encode(shortcut), forKey: "globalShortcut")

        let settings = makeSettings(defaults)

        #expect(settings.actions.count == 1)
        #expect(settings.actions[0].prompt == "Translate to French.")
        #expect(settings.actions[0].shortcuts == [shortcut])
    }

    @Test("Actions saved with a single shortcut load with it as their only shortcut")
    func testSingleShortcutMigration() throws {
        let defaults = makeDefaults()
        let saved = """
        [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Fix grammar","prompt":"Fix it.",
          "shortcut":{"keyCode":5,"modifiers":6144,"keyLabel":"G"}},
         {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"New action","prompt":"Fix it.","shortcuts":[]}]
        """
        defaults.set(Data(saved.utf8), forKey: "rewriteActions")

        let settings = makeSettings(defaults)

        #expect(settings.actions[0].shortcuts == [.default])
        #expect(settings.actions[1].name == "")
        #expect(settings.actions[1].workingLabel == "Rewriting…")
    }

    @Test("An action can have several shortcuts, without duplicates")
    func testSeveralShortcuts() throws {
        let defaults = makeDefaults()
        let settings = makeSettings(defaults)
        let second = GlobalShortcut(keyCode: UInt32(kVK_F5), modifiers: 0, keyLabel: "F5")
        settings.actions[0].addShortcut(second)
        settings.actions[0].addShortcut(.default)
        try settings.save()

        let reloaded = makeSettings(defaults)
        #expect(reloaded.actions[0].shortcuts == [.default, second])
    }

    @Test("A shortcut belongs to one action; duplicates are refused, edits and removals apply")
    func testShortcutOwnership() {
        let settings = makeSettings(makeDefaults())
        settings.addAction()
        let first = settings.actions[0].id
        let second = settings.actions[1].id
        let f5 = GlobalShortcut(keyCode: UInt32(kVK_F5), modifiers: 0, keyLabel: "F5")
        let f6 = GlobalShortcut(keyCode: UInt32(kVK_F6), modifiers: 0, keyLabel: "F6")

        // Adding the default shortcut to another action, or again to its own, is refused.
        #expect(settings.setShortcut(.default, replacing: nil, in: second) == false)
        #expect(settings.setShortcut(.default, replacing: nil, in: first) == false)
        #expect(settings.actions[1].shortcuts.isEmpty)

        #expect(settings.setShortcut(f5, replacing: nil, in: second))
        #expect(settings.isShortcutTaken(f5))

        // Re-recording a chip as itself is fine; as another action's shortcut it is not.
        #expect(settings.setShortcut(f5, replacing: f5, in: second))
        #expect(settings.setShortcut(.default, replacing: f5, in: second) == false)
        #expect(settings.actions[1].shortcuts == [f5])

        #expect(settings.setShortcut(f6, replacing: f5, in: second))
        #expect(settings.actions[1].shortcuts == [f6])
        #expect(settings.setShortcut(nil, replacing: f6, in: second))
        #expect(settings.actions[1].shortcuts.isEmpty)
        #expect(settings.setShortcut(f6, replacing: nil, in: UUID()) == false)
    }

    @Test("⌘C and ⌘V cannot be shortcuts, and saved ones are dropped")
    func testReservedShortcuts() throws {
        let defaults = makeDefaults()
        let settings = makeSettings(defaults)
        let copy = GlobalShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey), keyLabel: "C")
        let paste = GlobalShortcut(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey), keyLabel: "V")
        let shiftCopy = GlobalShortcut(keyCode: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "C")
        let id = settings.actions[0].id

        #expect(settings.setShortcut(copy, replacing: nil, in: id) == false)
        #expect(settings.setShortcut(paste, replacing: nil, in: id) == false)
        #expect(settings.setShortcut(shiftCopy, replacing: nil, in: id))
        #expect(settings.actions[0].shortcuts == [.default, shiftCopy])

        // A ⌘C saved by an earlier build disappears on load.
        settings.actions[0].shortcuts.append(copy)
        try settings.save()
        let reloaded = makeSettings(defaults)
        #expect(reloaded.actions[0].shortcuts == [.default, shiftCopy])
    }

    @Test("Running an action reports the one missing setting")
    func testSetupProblems() {
        let settings = makeSettings(makeDefaults())
        var action = settings.actions[0]
        #expect(settings.setupProblem(for: action) == "Add an API key in Settings")

        settings.apiKey = "sk-test"
        #expect(settings.setupProblem(for: action) == nil)

        settings.model = " "
        #expect(settings.setupProblem(for: action) == "Add a model in Settings")
        settings.model = "gpt-4.1-mini"

        action.prompt = "\n  "
        #expect(settings.setupProblem(for: action) == "Add a prompt for “Fix grammar” in Settings")
        action.prompt = "Shorten."

        // With no other provider to fall back to, a custom endpoint must be complete.
        settings.apiKey = ""
        settings.selectProvider(.custom)
        #expect(settings.setupProblem(for: action) == "Add an endpoint in Settings")
        settings.endpoint = "http://localhost:11434/v1/chat/completions"
        #expect(settings.setupProblem(for: action) == "Add a model in Settings")
        settings.model = "llama"
        #expect(settings.setupProblem(for: action) == nil)
    }

    @Test("Actions round-trip through save and the last one cannot be removed")
    func testActionsPersist() throws {
        let defaults = makeDefaults()
        let settings = makeSettings(defaults)
        settings.addAction()
        #expect(settings.actions[1].workingLabel == "Rewriting…")
        settings.actions[1].name = "Tighten"
        settings.actions[1].prompt = "Make it shorter."
        settings.actions[1].shortcuts = [GlobalShortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), keyLabel: "T")]
        try settings.save()

        let reloaded = makeSettings(defaults)
        #expect(reloaded.actions == settings.actions)
        #expect(reloaded.actions[1].workingLabel == "Tighten…")

        reloaded.removeAction(id: reloaded.actions[0].id)
        #expect(reloaded.actions.count == 1)
        reloaded.removeAction(id: reloaded.actions[0].id)
        #expect(reloaded.actions.count == 1)
    }

    @Test("Edits apply on their own once they settle, as one change")
    func testEditsApplyAutomatically() async throws {
        let settings = makeSettings(makeDefaults())
        var applied = 0
        settings.changeHandler = { applied += 1 }

        settings.model = "a"
        settings.model = "ab"
        settings.endpoint = "https://example.com/v1/chat/completions"
        #expect(applied == 0)

        try await Task.sleep(nanoseconds: 700_000_000)
        #expect(applied == 1)
    }

    @Test("A custom endpoint works without a key, other providers do not")
    func testCustomEndpointWithoutKey() {
        let settings = makeSettings(makeDefaults())
        #expect(settings.hasUsableProvider == false)

        settings.selectProvider(.custom)
        settings.endpoint = "http://localhost:11434/v1/chat/completions"
        settings.model = "llama3"

        let configurations = settings.availableProviderConfigurations(prompt: "Fix it.")
        #expect(configurations.map(\.provider) == [.custom])
        #expect(configurations[0].llm.apiKey == "")
        #expect(configurations[0].llm.prompt == "Fix it.")

        settings.endpoint = ""
        #expect(settings.hasUsableProvider == false)
    }

    @Test("Keys typed for other providers survive switching back")
    func testDraftKeysAreKept() {
        let settings = makeSettings(makeDefaults())
        settings.apiKey = "openai-key"
        settings.selectProvider(.gemini)
        settings.apiKey = "gemini-key"
        settings.selectProvider(.openAI)

        #expect(settings.apiKey == "openai-key")
        let providers = settings.availableProviderConfigurations(prompt: "p").map(\.provider)
        #expect(providers == [.openAI, .gemini])
    }

    @Test("A custom endpoint and model survive switching providers and relaunching")
    func testProviderDraftsAreKept() throws {
        let defaults = makeDefaults()
        let settings = makeSettings(defaults)
        settings.selectProvider(.custom)
        settings.endpoint = "https://router.example/v1/chat/completions"
        settings.model = "example/model"
        settings.selectProvider(.gemini)
        #expect(settings.endpoint == LLMProvider.gemini.defaultEndpoint)

        settings.selectProvider(.custom)
        #expect(settings.endpoint == "https://router.example/v1/chat/completions")
        #expect(settings.model == "example/model")

        settings.selectProvider(.gemini)
        try settings.save()
        let relaunched = makeSettings(defaults)
        #expect(relaunched.provider == .gemini)
        relaunched.selectProvider(.custom)
        #expect(relaunched.endpoint == "https://router.example/v1/chat/completions")
        #expect(relaunched.model == "example/model")
    }

    @Test("Keys live in one Keychain item and are read once at launch")
    func testSingleKeychainItem() throws {
        let keychain = FakeKeychain()
        let defaults = makeDefaults()
        let settings = AppSettings(readsAPIKeyFromKeychain: true, defaults: defaults, keychain: keychain)
        settings.apiKey = "openai-key"
        settings.selectProvider(.gemini)
        settings.apiKey = "gemini-key"
        try settings.save()

        #expect(keychain.items.keys.sorted() == ["provider-keys"])
        #expect(ProviderKeyStore.decode(keychain.items["provider-keys"]!) == [.openAI: "openai-key", .gemini: "gemini-key"])

        let reloaded = AppSettings(readsAPIKeyFromKeychain: true, defaults: defaults, keychain: keychain)
        #expect(reloaded.apiKey == "gemini-key")
        reloaded.selectProvider(.openAI)
        #expect(reloaded.apiKey == "openai-key")
        #expect(keychain.reads.filter { $0 == "provider-keys" }.count == 2)
    }

    @Test("Per-provider items from older builds merge into the single item once")
    func testLegacyKeychainMigration() {
        let keychain = FakeKeychain(items: [
            "provider-key-openAI": "openai-key",
            "provider-key-custom": "local-key",
        ])
        let defaults = makeDefaults()

        let settings = AppSettings(readsAPIKeyFromKeychain: true, defaults: defaults, keychain: keychain)

        #expect(settings.apiKey == "openai-key")
        #expect(keychain.items.keys.sorted() == ["provider-keys"])
        #expect(ProviderKeyStore.decode(keychain.items["provider-keys"]!) == [.openAI: "openai-key", .custom: "local-key"])

        let readsBefore = keychain.reads.count
        _ = AppSettings(readsAPIKeyFromKeychain: true, defaults: defaults, keychain: keychain)
        #expect(keychain.reads.count == readsBefore + 1)
    }
}
