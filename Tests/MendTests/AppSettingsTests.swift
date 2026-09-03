import Carbon
import Foundation
@testable import Mend
import Testing

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
        #expect(settings.actions[0].shortcut == .default)
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
        #expect(settings.actions[0].shortcut == shortcut)
    }

    @Test("Actions round-trip through save and the last one cannot be removed")
    func testActionsPersist() throws {
        let defaults = makeDefaults()
        let settings = makeSettings(defaults)
        settings.addAction()
        settings.actions[1].name = "Tighten"
        settings.actions[1].prompt = "Make it shorter."
        settings.actions[1].shortcut = GlobalShortcut(keyCode: UInt32(kVK_ANSI_T), modifiers: UInt32(controlKey | optionKey), keyLabel: "T")
        try settings.save()

        let reloaded = makeSettings(defaults)
        #expect(reloaded.actions == settings.actions)
        #expect(reloaded.actions[1].workingLabel == "Tighten…")

        reloaded.removeAction(id: reloaded.actions[0].id)
        #expect(reloaded.actions.count == 1)
        reloaded.removeAction(id: reloaded.actions[0].id)
        #expect(reloaded.actions.count == 1)
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
}
