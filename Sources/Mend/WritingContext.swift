import AppKit
import Foundation

/// Captures surrounding application context and user-specific vocabulary
/// to adapt the rewrite instructions to the environment the user is writing in.
public struct WritingContext: Equatable, Codable {
    public let bundleIdentifier: String?
    public let applicationName: String?
    public let surroundingContext: String?
    public let customVocabulary: [String]

    public init(
        bundleIdentifier: String? = nil,
        applicationName: String? = nil,
        surroundingContext: String? = nil,
        customVocabulary: [String] = []
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.applicationName = applicationName
        self.surroundingContext = surroundingContext
        self.customVocabulary = customVocabulary
    }

    /// Contextual guidance injected into the system prompt based on the target app.
    public var contextualInstruction: String? {
        guard let bundleIdentifier = bundleIdentifier?.lowercased() else { return nil }

        if isDeveloperApp(bundleIdentifier) {
            return "The user is writing in a developer code editor or terminal. Strictly preserve all code identifiers, symbols, function names, markdown backticks, and variable naming conventions (camelCase, snake_case, etc.). Only correct natural-language prose and comments."
        } else if isChatApp(bundleIdentifier) {
            return "The user is writing an informal chat message. Keep the tone natural, conversational, and direct. Avoid overly rigid or bureaucratic phrasing."
        } else if isDocumentApp(bundleIdentifier) {
            return "The user is writing a formal document or email. Ensure polished cadence, precise phrasing, and professional clarity."
        }
        return nil
    }

    /// User vocabulary terms that must remain untouched.
    public var vocabularyInstruction: String? {
        guard !customVocabulary.isEmpty else { return nil }
        let terms = customVocabulary
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !terms.isEmpty else { return nil }
        let formattedTerms = terms.map { "“\($0)”" }.joined(separator: ", ")
        return "Preserve these exact brand names, technical terms, and acronyms without altering their spelling or capitalization: \(formattedTerms)."
    }

    private func isDeveloperApp(_ bundleId: String) -> Bool {
        bundleId.contains("xcode") ||
        bundleId.contains("vscode") ||
        bundleId.contains("sublime") ||
        bundleId.contains("jetbrains") ||
        bundleId.contains("terminal") ||
        bundleId.contains("iterm") ||
        bundleId.contains("cursor") ||
        bundleId.contains("zed") ||
        bundleId.contains("warp")
    }

    private func isChatApp(_ bundleId: String) -> Bool {
        bundleId.contains("slack") ||
        bundleId.contains("discord") ||
        bundleId.contains("messages") ||
        bundleId.contains("telegram") ||
        bundleId.contains("whatsapp") ||
        bundleId.contains("mattermost")
    }

    private func isDocumentApp(_ bundleId: String) -> Bool {
        bundleId.contains("mail") ||
        bundleId.contains("pages") ||
        bundleId.contains("word") ||
        bundleId.contains("notes") ||
        bundleId.contains("keynote") ||
        bundleId.contains("notion")
    }

    /// Gathers the writing context from the current running application.
    public static func current(
        application: NSRunningApplication? = NSWorkspace.shared.frontmostApplication,
        surrounding: String? = nil,
        vocabulary: [String] = []
    ) -> WritingContext {
        WritingContext(
            bundleIdentifier: application?.bundleIdentifier,
            applicationName: application?.localizedName,
            surroundingContext: surrounding,
            customVocabulary: vocabulary
        )
    }
}
