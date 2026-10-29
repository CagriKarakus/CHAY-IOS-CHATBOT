import Foundation

public enum LLMStreamEvent: Equatable, Sendable {
    /// Cevap metninin bir parçası.
    case text(String)
    /// Modelin istediği araç çağrıları; akışın sonunda, birleştirilmiş olarak bir kez gelir.
    case toolCalls([ToolCall])
}

/// OpenAI-uyumlu `/chat/completions` istemcisi (SSE streaming).
public struct LLMClient: Sendable {
    private let configuration: LLMConfiguration
    private let transport: any HTTPTransport

    public init(configuration: LLMConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Cevabı geldikçe olaylar olarak döndürür. Akışı tüketen görev iptal edilirse istek de iptal edilir.
    public func streamChat(_ messages: [ChatMessage], tools: [ToolDefinition] = []) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(messages, tools: tools) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Endpoint'in sunduğu model adlarını (`GET /models`) alfabetik döndürür.
    public static func listModels(baseURL: String, apiKey: String, transport: any HTTPTransport) async throws -> [String] {
        let url = try LLMConfiguration.validatedBaseURL(baseURL)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LLMError.missingAPIKey }

        let response = try await transport.send(HTTPRequest(
            url: url.appendingPathComponent("models"),
            method: "GET",
            headers: ["Authorization": "Bearer \(key)"],
            body: nil
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw LLMError.http(status: response.statusCode, message: nil)
        }
        guard let list = try? JSONDecoder().decode(ModelList.self, from: response.body) else {
            throw LLMError.invalidResponse
        }
        return list.data.map(\.id).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func makeRequest(_ messages: [ChatMessage], tools: [ToolDefinition] = []) throws -> HTTPRequest {
        let body = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: configuration.model,
                messages: messages,
                stream: true,
                tools: tools.isEmpty ? nil : tools,
                reasoningEffort: configuration.reasoningEffort
            )
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

    private func run(_ messages: [ChatMessage], tools: [ToolDefinition], onEvent: (LLMStreamEvent) -> Void) async throws {
        let decoder = JSONDecoder()
        var toolCalls = ToolCallAccumulator()
        do {
            lines: for try await line in transport.lines(for: try makeRequest(messages, tools: tools)) {
                switch SSELine(line) {
                case .ignored:
                    continue
                case .done:
                    break lines
                case let .data(json):
                    let data = Data(json.utf8)
                    if let chunk = try? decoder.decode(ChatCompletionChunk.self, from: data) {
                        guard let delta = chunk.choices.first?.delta else { continue }
                        if let text = delta.content, !text.isEmpty {
                            onEvent(.text(text))
                        }
                        delta.toolCalls?.forEach { toolCalls.add($0) }
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
        if !toolCalls.isEmpty {
            onEvent(.toolCalls(toolCalls.calls))
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

/// Parça parça gelen araç çağrılarını `index`'e göre birleştirir.
private struct ToolCallAccumulator {
    private var parts: [Int: (id: String?, name: String, arguments: String)] = [:]

    var isEmpty: Bool { parts.isEmpty }

    mutating func add(_ delta: ToolCallDelta) {
        let index = delta.index ?? 0
        var part = parts[index] ?? (id: nil, name: "", arguments: "")
        if let id = delta.id, !id.isEmpty { part.id = id }
        part.name += delta.function?.name ?? ""
        part.arguments += delta.function?.arguments ?? ""
        parts[index] = part
    }

    var calls: [ToolCall] {
        parts.sorted { $0.key < $1.key }.map { index, part in
            ToolCall(id: part.id ?? "call_\(index)", name: part.name, arguments: part.arguments)
        }
    }
}
