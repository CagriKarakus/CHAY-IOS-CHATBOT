import Foundation

/// OpenAI-uyumlu `/chat/completions` istemcisi (SSE streaming).
public struct LLMClient: Sendable {
    private let configuration: LLMConfiguration
    private let transport: any HTTPTransport

    public init(configuration: LLMConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Cevabı geldikçe metin parçaları olarak döndürür. Akışı tüketen görev iptal edilirse istek de iptal edilir.
    public func streamChat(_ messages: [ChatMessage]) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(messages) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func makeRequest(_ messages: [ChatMessage]) throws -> HTTPRequest {
        let body = try JSONEncoder().encode(
            ChatCompletionRequest(model: configuration.model, messages: messages, stream: true)
        )
        return HTTPRequest(
            url: configuration.baseURL.appendingPathComponent("chat/completions"),
            method: "POST",
            headers: [
                "Authorization": "Bearer \(configuration.apiKey)",
                "Content-Type": "application/json",
                "Accept": "text/event-stream",
            ],
            body: body
        )
    }

    private func run(_ messages: [ChatMessage], onDelta: (String) -> Void) async throws {
        let decoder = JSONDecoder()
        do {
            for try await line in transport.lines(for: try makeRequest(messages)) {
                switch SSELine(line) {
                case .ignored:
                    continue
                case .done:
                    return
                case let .data(json):
                    let data = Data(json.utf8)
                    if let chunk = try? decoder.decode(ChatCompletionChunk.self, from: data) {
                        if let text = chunk.choices.first?.delta?.content, !text.isEmpty {
                            onDelta(text)
                        }
                    } else if let message = apiErrorMessage(from: json) {
                        throw LLMError.server(message: message)
                    } else {
                        throw LLMError.invalidResponse
                    }
                }
            }
        } catch let error as HTTPStatusError {
            throw LLMError.http(status: error.statusCode, message: errorMessage(from: error.body))
        }
    }

    /// HTTP hata gövdesinden okunabilir mesajı çıkarır: JSON değilse düz metnin başı kullanılır.
    private func errorMessage(from body: String) -> String? {
        if let message = apiErrorMessage(from: body) {
            return message
        }
        return redacted(String(body.prefix(300)))
    }

    /// `{"error": {"message": ...}}` biçimindeki mesaj.
    private func apiErrorMessage(from json: String) -> String? {
        guard let decoded = try? JSONDecoder().decode(APIErrorBody.self, from: Data(json.utf8)),
              let message = decoded.error.message
        else { return nil }
        return redacted(message)
    }

    /// Mesajda API key geçiyorsa gizler.
    private func redacted(_ message: String) -> String? {
        let text = message
            .replacingOccurrences(of: configuration.apiKey, with: "***")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}
