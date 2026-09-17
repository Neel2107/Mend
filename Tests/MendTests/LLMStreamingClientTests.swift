import Foundation
@testable import Mend
import Testing

extension NetworkClientTests {
@Suite("LLM streaming client")
struct LLMStreamingClientTests {
    private let configuration = LLMConfiguration(
        endpoint: "https://example.test/v1/chat/completions",
        model: "test-model",
        prompt: "Base system prompt.",
        apiKey: "stream-secret-key"
    )

    private func client(_ configuration: LLMConfiguration) -> LLMClient {
        StubURLProtocol.reset()
        return LLMClient(configuration: configuration, session: StubURLProtocol.makeSession())
    }

    @Test("Streaming parses SSE chunks and yields tokens")
    func testStreamingYieldsTokens() async throws {
        let client = client(configuration)
        let ssePayload = """
        data: {"choices":[{"delta":{"content":"Fixed"}}]}

        data: {"choices":[{"delta":{"content":" text"}}]}

        data: [DONE]

        """
        StubURLProtocol.handler = { request, _ in
            (.stub(request, status: 200), Data(ssePayload.utf8))
        }

        var tokens: [String] = []
        for try await token in client.streamRewrite("Broken text") {
            tokens.append(token)
        }

        #expect(tokens == ["Fixed", " text"])
        let sent = try #require(StubURLProtocol.requests.first)
        let body = jsonObject(sent.body)
        #expect(body["stream"] as? Bool == true)
        #expect(body["model"] as? String == "test-model")
    }

    @Test("Contextual instructions and vocabulary are injected into system prompt")
    func testContextualPromptInjection() async throws {
        let client = client(configuration)
        StubURLProtocol.handler = { request, _ in
            (.stub(request, status: 200), json(["choices": [["message": ["role": "assistant", "content": "Cleaned code"]]]]))
        }

        let context = WritingContext(
            bundleIdentifier: "com.apple.dt.Xcode",
            applicationName: "Xcode",
            customVocabulary: ["Mend", "V2"]
        )

        _ = try await client.rewrite("var x = 1", context: context)

        let sent = try #require(StubURLProtocol.requests.first)
        let body = jsonObject(sent.body)
        let messages = body["messages"] as? [[String: String]]
        let systemMessage = messages?.first?["content"]

        #expect(systemMessage?.contains("Base system prompt.") == true)
        #expect(systemMessage?.contains("Strictly preserve all code identifiers") == true)
        #expect(systemMessage?.contains("“Mend”") == true)
        #expect(systemMessage?.contains("“V2”") == true)
    }
}
}
