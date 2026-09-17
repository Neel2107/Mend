import Foundation
@testable import Mend
import Testing

@Suite("Writing context")
struct WritingContextTests {
    @Test("Xcode and developer editors receive code-preservation instructions")
    func testDeveloperAppInstructions() {
        let context = WritingContext(
            bundleIdentifier: "com.apple.dt.Xcode",
            applicationName: "Xcode"
        )

        let instruction = context.contextualInstruction
        #expect(instruction?.contains("Strictly preserve all code identifiers") == true)
        #expect(instruction?.contains("camelCase") == true)
    }

    @Test("VS Code editor is recognized as developer tool")
    func testVSCodeInstructions() {
        let context = WritingContext(
            bundleIdentifier: "com.microsoft.VSCode",
            applicationName: "Code"
        )

        let instruction = context.contextualInstruction
        #expect(instruction?.contains("developer code editor") == true)
    }

    @Test("Slack and chat apps receive natural tone instructions")
    func testChatAppInstructions() {
        let context = WritingContext(
            bundleIdentifier: "com.tinyspeck.slackmacgap",
            applicationName: "Slack"
        )

        let instruction = context.contextualInstruction
        #expect(instruction?.contains("informal chat message") == true)
        #expect(instruction?.contains("conversational") == true)
    }

    @Test("Mail and document apps receive formal clarity instructions")
    func testDocumentAppInstructions() {
        let context = WritingContext(
            bundleIdentifier: "com.apple.mail",
            applicationName: "Mail"
        )

        let instruction = context.contextualInstruction
        #expect(instruction?.contains("formal document or email") == true)
    }

    @Test("Custom vocabulary generates exact preservation list")
    func testCustomVocabularyInstruction() {
        let context = WritingContext(
            bundleIdentifier: "com.apple.Notes",
            customVocabulary: ["Mend", "Antigravity", "macOS 26"]
        )

        let vocabInstruction = context.vocabularyInstruction
        #expect(vocabInstruction?.contains("“Mend”") == true)
        #expect(vocabInstruction?.contains("“Antigravity”") == true)
        #expect(vocabInstruction?.contains("“macOS 26”") == true)
    }

    @Test("Empty vocabulary returns nil instruction")
    func testEmptyVocabularyInstruction() {
        let context = WritingContext(
            bundleIdentifier: "com.apple.Notes",
            customVocabulary: ["  ", ""]
        )

        #expect(context.vocabularyInstruction == nil)
    }
}
