import Foundation
import Testing
@testable import AgentCore

@Test func streamsTextDeltas() async throws {
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: textStreamLines))

    let deltas = try await collect(client.streamChat([ChatMessage(role: .user, content: "Selam")]))

    #expect(deltas == ["Merhaba", " dünya"])
}

@Test func stopsAtDone() async throws {
    let lines = [#"data: {"choices":[{"delta":{"content":"a"}}]}"#, "data: [DONE]", #"data: {"choices":[{"delta":{"content":"b"}}]}"#]
    let client = LLMClient(configuration: try makeConfiguration(), transport: MockTransport(responseLines: lines))

    #expect(try await collect(client.streamChat([])) == ["a"])
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
    #expect((json["messages"] as? [[String: Any]])?.first?["content"] as? String == "Selam")
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
