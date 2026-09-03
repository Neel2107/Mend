import Foundation
@testable import Mend
import Testing

// Both suites share one URL protocol stub, so they must not run at the same time.
@Suite("Network clients", .serialized)
struct NetworkClientTests {}

extension NetworkClientTests {
@Suite("LLM client")
struct LLMClientTests {
    private let configuration = LLMConfiguration(
        endpoint: "https://example.test/v1/chat/completions",
        model: "test-model",
        prompt: "Fix it.",
        apiKey: "secret-key"
    )

    private func client(_ configuration: LLMConfiguration) -> LLMClient {
        StubURLProtocol.reset()
        return LLMClient(configuration: configuration, session: StubURLProtocol.makeSession())
    }

    private static func completion(_ content: String) -> Data {
        json(["choices": [["message": ["role": "assistant", "content": content]]]])
    }

    @Test("A successful reply is trimmed and the request carries the key, prompt, and temperature")
    func testSuccessfulRewrite() async throws {
        let client = client(configuration)
        StubURLProtocol.handler = { request, _ in
            (.stub(request, status: 200), Self.completion("  I sent it.\n"))
        }

        let result = try await client.rewrite("I have send it.")

        #expect(result == "I sent it.")
        let sent = try #require(StubURLProtocol.requests.first)
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == "Bearer secret-key")
        let body = jsonObject(sent.body)
        #expect(body["model"] as? String == "test-model")
        #expect(body["temperature"] as? Double == 0)
        let messages = body["messages"] as? [[String: String]]
        #expect(messages?.first?["role"] == "system")
        #expect(messages?.first?["content"] == "Fix it.")
        #expect(messages?.last?["content"]?.contains("<selected_text>\nI have send it.\n</selected_text>") == true)
    }

    @Test("An empty key sends no Authorization header")
    func testEmptyKeyOmitsAuthorization() async throws {
        let client = client(LLMConfiguration(
            endpoint: "http://localhost:11434/v1/chat/completions",
            model: "llama",
            prompt: "Fix it.",
            apiKey: ""
        ))
        StubURLProtocol.handler = { request, _ in
            (.stub(request, status: 200), Self.completion("Fixed"))
        }

        _ = try await client.rewrite("text")

        let sent = try #require(StubURLProtocol.requests.first)
        #expect(sent.request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("Service errors surface the provider's message")
    func testServiceErrorMessage() async {
        let client = client(configuration)
        StubURLProtocol.handler = { request, _ in
            (.stub(request, status: 401), json(["error": ["message": "Incorrect API key provided"]]))
        }

        await #expect {
            try await client.rewrite("text")
        } throws: { error in
            guard case MendError.serviceError(let message) = error else { return false }
            return message == "Incorrect API key provided"
        }
    }

    @Test("A model that rejects temperature is retried without it")
    func testTemperatureRetry() async throws {
        let client = client(configuration)
        StubURLProtocol.handler = { request, body in
            if jsonObject(body)["temperature"] != nil {
                return (
                    .stub(request, status: 400),
                    json(["error": ["message": "Unsupported value: 'temperature' does not support 0 with this model."]])
                )
            }
            return (.stub(request, status: 200), Self.completion("Fixed"))
        }

        let result = try await client.rewrite("text")

        #expect(result == "Fixed")
        #expect(StubURLProtocol.requests.count == 2)
        #expect(jsonObject(StubURLProtocol.requests[0].body)["temperature"] != nil)
        #expect(jsonObject(StubURLProtocol.requests[1].body)["temperature"] == nil)
    }

    @Test("An unreadable reply is reported as invalid")
    func testInvalidResponse() async {
        let client = client(configuration)
        StubURLProtocol.handler = { request, _ in
            (.stub(request, status: 200), Data("not json".utf8))
        }

        await #expect {
            try await client.rewrite("text")
        } throws: { error in
            guard case MendError.invalidResponse = error else { return false }
            return true
        }
    }

    @Test("Endpoints without an http scheme are rejected before any request")
    func testInvalidEndpoint() async {
        let client = client(LLMConfiguration(endpoint: "ftp://x", model: "m", prompt: "p", apiKey: "k"))

        await #expect {
            try await client.rewrite("text")
        } throws: { error in
            guard case MendError.invalidEndpoint = error else { return false }
            return true
        }
        #expect(StubURLProtocol.requests.isEmpty)
    }
}

@Suite("Update checker")
struct UpdateCheckerTests {
    @Test("Versions compare numerically and ignore a leading v")
    func testVersionComparison() throws {
        let current = try #require(AppVersion("0.2.3"))
        #expect(try #require(AppVersion("v0.3.0")) > current)
        #expect(try #require(AppVersion("0.2.10")) > current)
        #expect(try #require(AppVersion("0.2.3.0")) == current)
        #expect(try #require(AppVersion("1.0")) > current)
        #expect(AppVersion("latest") == nil)
        #expect(AppVersion("") == nil)
    }

    @Test("A newer release reports its version and page")
    func testNewerRelease() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { request, _ in
            (
                .stub(request, status: 200),
                json(["tag_name": "v0.3.0", "html_url": "https://github.com/Neel2107/Mend/releases/tag/v0.3.0"])
            )
        }
        let checker = UpdateChecker(session: StubURLProtocol.makeSession())

        let outcome = try await checker.check(currentVersion: AppVersion("0.2.3")!)

        #expect(
            StubURLProtocol.requests.first?.request.url?.absoluteString
                == "https://api.github.com/repos/Neel2107/Mend/releases/latest"
        )
        #expect(outcome == .available(
            version: AppVersion("0.3.0")!,
            url: URL(string: "https://github.com/Neel2107/Mend/releases/tag/v0.3.0")!
        ))
    }

    @Test("The current release reports up to date")
    func testUpToDate() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.handler = { request, _ in
            (.stub(request, status: 200), json(["tag_name": "v0.2.3", "html_url": "https://example.test"]))
        }
        let checker = UpdateChecker(session: StubURLProtocol.makeSession())

        let outcome = try await checker.check(currentVersion: AppVersion("0.2.3")!)

        #expect(outcome == .upToDate(AppVersion("0.2.3")!))
    }
}
}
