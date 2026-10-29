import Foundation
import Testing
@testable import AgentCore

/// `send` isteklerini kaydeden ve sabit yanıt dönen transport.
final class SendRecorder: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [HTTPRequest] = []
    let response: HTTPResponse

    init(status: Int = 200, json: String) {
        response = HTTPResponse(statusCode: status, contentType: "application/json", body: Data(json.utf8))
    }

    var requests: [HTTPRequest] { lock.withLock { recorded } }

    func lines(for request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock { recorded.append(request) }
        return response
    }

    func body(of index: Int) throws -> [String: Any] {
        let data = try #require(requests[index].body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

// MARK: - Efor

@Test func sendsReasoningEffortWhenSet() throws {
    let configuration = try LLMConfiguration(baseURL: "https://a.com/v1", apiKey: "k", model: "m", reasoningEffort: .high)
    let body = try #require(try LLMClient(configuration: configuration, transport: MockTransport()).makeRequest([]).body)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(json["reasoning_effort"] as? String == "high")
}

@Test func omitsReasoningEffortByDefault() throws {
    let body = try #require(try LLMClient(configuration: try makeConfiguration(), transport: MockTransport()).makeRequest([]).body)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect(json["reasoning_effort"] == nil)
}

// MARK: - Model listesi

@Test func listsModelsSorted() async throws {
    let transport = SendRecorder(json: #"{"object":"list","data":[{"id":"zai/glm-5.3"},{"id":"gpt-5"},{"id":"claude-x"}]}"#)

    let models = try await LLMClient.listModels(baseURL: "https://router.example.com/v1/", apiKey: " key ", transport: transport)

    #expect(models == ["claude-x", "gpt-5", "zai/glm-5.3"])
    #expect(transport.requests.first?.url.absoluteString == "https://router.example.com/v1/models")
    #expect(transport.requests.first?.method == "GET")
    #expect(transport.requests.first?.headers["Authorization"] == "Bearer key")
}

@Test func listModelsReportsErrors() async throws {
    await #expect(throws: LLMError.http(status: 401, message: nil)) {
        try await LLMClient.listModels(baseURL: "https://a.com/v1", apiKey: "k", transport: SendRecorder(status: 401, json: "{}"))
    }
    await #expect(throws: LLMError.invalidResponse) {
        try await LLMClient.listModels(baseURL: "https://a.com/v1", apiKey: "k", transport: SendRecorder(json: "[]"))
    }
    await #expect(throws: LLMError.invalidBaseURL) {
        try await LLMClient.listModels(baseURL: "http://a.com/v1", apiKey: "k", transport: SendRecorder(json: "{}"))
    }
}

// MARK: - Uyarlanabilir arama

@Test(arguments: [
    (#"{"query":"hava"}"#, 3),
    (#"{"query":"hava","max_results":1}"#, 1),
    (#"{"query":"analiz","max_results":8}"#, 8),
    (#"{"query":"x","max_results":50}"#, 10),
    (#"{"query":"x","max_results":0}"#, 1),
])
func webSearchUsesRequestedResultCount(_ arguments: String, _ expected: Int) async throws {
    let transport = SendRecorder(json: #"{"results":[]}"#)

    _ = try await WebSearchTool(apiKey: "k", transport: transport).run(arguments: arguments)

    #expect(try transport.body(of: 0)["max_results"] as? Int == expected)
}
