import Foundation
import Testing
@testable import AgentCore

/// Sabit satırlar döndüren veya HTTP hatasıyla biten sahte transport.
struct MockTransport: HTTPTransport {
    var responseLines: [String] = []
    var failure: HTTPStatusError?
    var response = HTTPResponse(statusCode: 200, contentType: "text/html", body: Data())

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

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        response
    }
}

/// Her `lines` çağrısında sıradaki yanıtı döndürür ve gelen istekleri kaydeder (agent loop testleri için).
final class ScriptedTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var queue: [[String]]
    private var recorded: [HTTPRequest] = []

    init(_ responses: [[String]]) {
        queue = responses
    }

    var requests: [HTTPRequest] {
        lock.withLock { recorded }
    }

    func lines(for request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        let lines = lock.withLock {
            recorded.append(request)
            return queue.isEmpty ? [] : queue.removeFirst()
        }
        return AsyncThrowingStream { continuation in
            lines.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(statusCode: 500, contentType: nil, body: Data())
    }

    /// Kaydedilen bir isteğin JSON gövdesi.
    func body(of index: Int) throws -> [String: Any] {
        let data = try #require(requests[index].body)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
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

/// Tek bir araç çağrısı isteyen streaming yanıt.
func toolCallLines(id: String, name: String, arguments: String) -> [String] {
    let escaped = arguments.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    return [
        #"data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"id":"\#(id)","type":"function","function":{"name":"\#(name)","arguments":"\#(escaped)"}}]}}]}"#,
        #"data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}"#,
        "data: [DONE]",
    ]
}

/// Faz 0'da gerçek router'dan kaydedilen yanıtın satırları.
func fixtureLines(_ name: String) throws -> [String] {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
        .appendingPathComponent(name)
    return try String(contentsOf: url, encoding: .utf8).components(separatedBy: "\n")
}

func collect<T>(_ stream: AsyncThrowingStream<T, any Error>) async throws -> [T] {
    var result: [T] = []
    for try await item in stream {
        result.append(item)
    }
    return result
}

func makeConfiguration() throws -> LLMConfiguration {
    try LLMConfiguration(baseURL: "https://router.example.com/v1", apiKey: "sk-test-123", model: "test-model")
}
