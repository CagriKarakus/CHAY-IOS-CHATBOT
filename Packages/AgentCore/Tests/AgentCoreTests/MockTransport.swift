@testable import AgentCore

/// Sabit satırlar döndüren veya HTTP hatasıyla biten sahte transport.
struct MockTransport: HTTPTransport {
    var responseLines: [String] = []
    var failure: HTTPStatusError?

    func lines(for request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            if let failure {
                continuation.finish(throwing: failure)
                return
            }
            for line in responseLines {
                continuation.yield(line)
            }
            continuation.finish()
        }
    }
}

/// OpenAI'nin streaming metin yanıtının satırları (URLSession boş satırları zaten atlar).
let textStreamLines = [
    ": keep-alive",
    #"data: {"id":"c1","choices":[{"index":0,"delta":{"role":"assistant","content":""}}]}"#,
    #"data: {"id":"c1","choices":[{"index":0,"delta":{"content":"Merhaba"}}]}"#,
    "",
    #"data: {"id":"c1","choices":[{"index":0,"delta":{"content":" dünya"}}]}"#,
    #"data: {"id":"c1","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#,
    #"data: {"id":"c1","choices":[],"usage":{"prompt_tokens":5,"completion_tokens":2}}"#,
    "data: [DONE]",
]

func collect(_ stream: AsyncThrowingStream<String, any Error>) async throws -> [String] {
    var result: [String] = []
    for try await item in stream {
        result.append(item)
    }
    return result
}

func makeConfiguration() throws -> LLMConfiguration {
    try LLMConfiguration(baseURL: "https://router.example.com/v1", apiKey: "sk-test-123", model: "test-model")
}
