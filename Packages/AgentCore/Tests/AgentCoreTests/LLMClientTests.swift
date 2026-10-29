import Foundation
import Testing
@testable import AgentCore

@Test func streamsTextDeltas() async throws {
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: textStreamLines))

    let events = try await collect(client.streamChat([ChatMessage(role: .user, content: "Selam")]))

    #expect(withoutUsage(events) == [.text("Merhaba"), .text(" dünya")])
}

@Test func stopsAtDone() async throws {
    let lines = [#"data: {"choices":[{"delta":{"content":"a"}}]}"#, "data: [DONE]", #"data: {"choices":[{"delta":{"content":"b"}}]}"#]
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: lines))

    #expect(try await collect(client.streamChat([])) == [.text("a")])
}

@Test func parsesRecordedTextStreamWithoutReasoning() async throws {
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: try fixtureLines("text-stream.sse")))

    let events = try await collect(client.streamChat([]))
    let text = events.map { event -> String in
        if case let .text(delta) = event { return delta }
        return ""
    }.joined()

    #expect(text.hasSuffix("Size nasıl yardımcı olabilirim?"))
    #expect(!text.contains("The user"))
    #expect(!events.contains { if case .toolCalls = $0 { true } else { false } })
}

@Test func assemblesRecordedToolCall() async throws {
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: try fixtureLines("tool-call-stream.sse")))

    let events = try await collect(client.streamChat([]))

    #expect(withoutUsage(events) == [.toolCalls([ToolCall(id: "chatcmpl-tool-8714506b287573ca", name: "get_weather", arguments: #"{"city": "İstanbul"}"#)])])
}

@Test func mergesToolCallsByIndex() async throws {
    let lines = [
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"a","function":{"name":"web_search","arguments":""}},{"index":1,"id":"b","function":{"name":"fetch_page","arguments":"{\"url\":"}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"query\":\"x\"}"}},{"index":1,"function":{"arguments":"\"https://a.com\"}"}}]}}]}"#,
        "data: [DONE]",
    ]
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: lines))

    let events = try await collect(client.streamChat([]))

    #expect(events == [.toolCalls([
        ToolCall(id: "a", name: "web_search", arguments: #"{"query":"x"}"#),
        ToolCall(id: "b", name: "fetch_page", arguments: #"{"url":"https://a.com"}"#),
    ])])
}

@Test func buildsStreamingRequest() throws {
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport())

    let request = try client.makeRequest([ChatMessage(role: .user, content: "Selam")])

    #expect(request.url.absoluteString == "https://router.example.com/v1/chat/completions")
    #expect(request.method == "POST")
    #expect(request.headers["Authorization"] == "Bearer sk-test-123")
    let body = try #require(request.body)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["model"] as? String == "test-model")
    #expect(json["stream"] as? Bool == true)
    #expect(json["tools"] == nil)
    #expect((json["messages"] as? [[String: Any]])?.first?["content"] as? String == "Selam")
}

@Test func encodesToolsAndToolMessages() throws {
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport())
    let messages = [
        ChatMessage(role: .assistant, content: nil, toolCalls: [ToolCall(id: "c1", name: "web_search", arguments: #"{"query":"x"}"#)]),
        ChatMessage(role: .tool, content: "sonuç", toolCallID: "c1"),
    ]
    let tool = ToolDefinition(name: "web_search", description: "Arar", parameters: ["type": "object"])

    let body = try #require(try client.makeRequest(messages, tools: [tool]).body)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

    let tools = try #require(json["tools"] as? [[String: Any]])
    #expect(tools.first?["type"] as? String == "function")
    #expect((tools.first?["function"] as? [String: Any])?["name"] as? String == "web_search")
    let encoded = try #require(json["messages"] as? [[String: Any]])
    let call = try #require((encoded[0]["tool_calls"] as? [[String: Any]])?.first)
    #expect(call["id"] as? String == "c1")
    #expect((call["function"] as? [String: Any])?["arguments"] as? String == #"{"query":"x"}"#)
    #expect(encoded[1]["tool_call_id"] as? String == "c1")
}

@Test func unauthorizedGivesReadableError() async throws {
    let failure = HTTPStatusError(statusCode: 401, body: #"{"error":{"message":"Incorrect API key provided: sk-test-123"}}"#)
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(failure: failure))

    let error = await streamError(client)

    #expect(error == .http(status: 401, message: "Incorrect API key provided: ***"))
    #expect(error?.errorDescription?.contains("API key geçersiz") == true)
    #expect(error?.errorDescription?.contains("sk-test-123") == false)
}

@Test func serverErrorUsesPlainTextBody() async throws {
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(failure: HTTPStatusError(statusCode: 502, body: "Bad Gateway")))

    let error = await streamError(client)

    #expect(error == .http(status: 502, message: "Bad Gateway"))
    #expect(error?.errorDescription == "Sunucu hatası (502): Bad Gateway")
}

@Test func errorInsideStreamIsReported() async throws {
    let lines = [#"data: {"choices":[{"delta":{"content":"a"}}]}"#, #"data: {"error":{"message":"overloaded"}}"#]
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: lines))

    #expect(await streamError(client) == .server(message: "overloaded"))
}

@Test func malformedChunkIsInvalidResponse() async throws {
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: ["data: <html>"]))

    #expect(await streamError(client) == .invalidResponse)
}

private func streamError(_ client: LLMClient) async -> LLMError? {
    do {
        _ = try await collect(client.streamChat([ChatMessage(role: .user, content: "Selam")]))
        Issue.record("Hata bekleniyordu")
        return nil
    } catch {
        return error as? LLMError
    }
}
