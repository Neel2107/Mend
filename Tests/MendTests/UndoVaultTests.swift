import Foundation
@testable import Mend
import Testing

@Suite("Undo vault")
struct UndoVaultTests {
    @Test("Records transactions and returns the most recent one")
    func testRecordAndRetrieve() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_vault_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let vault = UndoVault(storageURL: tempURL, maxRecords: 10)

        let record1 = RewriteRecord(
            actionName: "Fix grammar",
            originalText: "Original one",
            replacedText: "Fixed one",
            provider: "OpenAI",
            latencyMs: 150,
            method: "accessibility"
        )
        let record2 = RewriteRecord(
            actionName: "Professional",
            originalText: "Original two",
            replacedText: "Fixed two",
            provider: "Gemini",
            latencyMs: 180,
            method: "paste"
        )

        vault.record(record1)
        vault.record(record2)

        #expect(vault.lastRecord()?.id == record2.id)
        #expect(vault.allRecords().count == 2)
        #expect(vault.allRecords().first?.originalText == "Original two")
    }

    @Test("Prunes records exceeding max capacity")
    func testMaxCapacityPruning() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_vault_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let vault = UndoVault(storageURL: tempURL, maxRecords: 3)

        for i in 1...5 {
            vault.record(
                RewriteRecord(
                    actionName: "Fix",
                    originalText: "Text \(i)",
                    replacedText: "Fixed \(i)",
                    provider: "OpenAI",
                    latencyMs: 100,
                    method: "accessibility"
                )
            )
        }

        let all = vault.allRecords()
        #expect(all.count == 3)
        #expect(all[0].originalText == "Text 5")
        #expect(all[1].originalText == "Text 4")
        #expect(all[2].originalText == "Text 3")
    }

    @Test("Clear removes all records from cache and disk")
    func testClearRecords() {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("test_vault_\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let vault = UndoVault(storageURL: tempURL)
        vault.record(
            RewriteRecord(
                actionName: "Fix",
                originalText: "Text",
                replacedText: "Fixed",
                provider: "OpenAI",
                latencyMs: 100,
                method: "accessibility"
            )
        )

        #expect(vault.lastRecord() != nil)
        vault.clear()
        #expect(vault.lastRecord() == nil)
        #expect(vault.allRecords().isEmpty)
    }
}
