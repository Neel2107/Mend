import Foundation
@testable import Mend
import Testing

@Suite("Diff engine")
struct DiffEngineTests {
    @Test("Identical texts produce no changes")
    func testIdenticalTexts() {
        let diff = DiffEngine.diff(original: "Hello world", modified: "Hello world")

        #expect(!diff.hasChanges)
        #expect(diff.additionsCount == 0)
        #expect(diff.deletionsCount == 0)
        #expect(diff.summary == "No changes")
        #expect(diff.chunks == [.equal("Hello world")])
    }

    @Test("Empty strings produce no changes")
    func testEmptyStrings() {
        let diff = DiffEngine.diff(original: "", modified: "")

        #expect(!diff.hasChanges)
        #expect(diff.chunks.isEmpty)
    }

    @Test("Word substitution counts additions and deletions properly")
    func testWordSubstitution() {
        let diff = DiffEngine.diff(original: "I have send it.", modified: "I sent it.")

        #expect(diff.hasChanges)
        #expect(diff.additionsCount == 1) // "sent"
        #expect(diff.deletionsCount == 2) // "have", "send"
        #expect(diff.summary == "+1, -2")
    }

    @Test("Word insertion is detected as addition")
    func testWordInsertion() {
        let diff = DiffEngine.diff(original: "Hello world", modified: "Hello beautiful world")

        #expect(diff.hasChanges)
        #expect(diff.additionsCount == 1)
        #expect(diff.deletionsCount == 0)
        #expect(diff.summary == "+1")
    }

    @Test("Word deletion is detected as deletion")
    func testWordDeletion() {
        let diff = DiffEngine.diff(original: "Please do kindly send", modified: "Please send")

        #expect(diff.hasChanges)
        #expect(diff.additionsCount == 0)
        #expect(diff.deletionsCount == 2)
        #expect(diff.summary == "-2")
    }

    @Test("Tokenization preserves whitespace and punctuation")
    func testTokenization() {
        let tokens = DiffEngine.tokenize("Hello,  world!\nNew line")

        #expect(tokens == ["Hello", ",", "  ", "world", "!", "\n", "New", " ", "line"])
    }
}
