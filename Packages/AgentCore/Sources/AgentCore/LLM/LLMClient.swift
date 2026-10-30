import Foundation

public enum LLMStreamEvent: Equatable, Sendable {
    /// Cevap metninin bir parçası.
    case text(String)
    /// Modelin düşünme (reasoning) metninin bir parçası; `delta.reasoning` veya `delta.reasoning_content`.
    case reasoning(String)
    /// Model bir araç çağrısının argümanlarını yazıyor (ör. uzun bir artifact); ilerleme için.
    case toolCallProgress(name: String, characters: Int)
    /// Modelin istediği araç çağrıları; akışın sonunda, birleştirilmiş olarak bir kez gelir.
    case toolCalls([ToolCall])
    /// Sunucu bildirdiyse çağrının token kullanımı; en sonda bir kez gelir.
    case usage(TokenUsage)
    /// Sağlayıcının kendi aramasından gelen kaynaklar.
    case citations([Source])
}

/// OpenAI-uyumlu `/chat/completions` istemcisi (SSE streaming).
public struct LLMClient: Sendable {
    private let configuration: LLMConfiguration
    private let transport: any HTTPTransport

    public init(configuration: LLMConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    var serverTools: ServerTools? {
        configuration.serverTools
    }

    /// Aynı model, sağlayıcının yerleşik araçları olmadan.
    func withoutServerTools() -> LLMClient {
        var plain = configuration
        plain.serverTools = nil
        return LLMClient(configuration: plain, transport: transport)
    }

    /// Cevabı geldikçe olaylar olarak döndürür. Akışı tüketen görev iptal edilirse istek de iptal edilir.
    /// `useServerTools`: sağlayıcının yerleşik araçları da gönderilsin (özetleme gibi araçsız çağrılarda gönderilmez).
    public func streamChat(
        _ messages: [ChatMessage],
        tools: [ToolDefinition] = [],
        useServerTools: Bool = false
    ) -> AsyncThrowingStream<LLMStreamEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await run(messages, tools: tools, useServerTools: useServerTools) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Endpoint'in sunduğu modelleri (`GET /models`) ada göre sıralı döndürür; sunucu bildirirse yetenekleriyle.
    public static func listModels(
        baseURL: String,
        apiKey: String,
        extraHeaders: [String: String] = [:],
        transport: any HTTPTransport
    ) async throws -> [ModelInfo] {
        let url = try LLMConfiguration.validatedBaseURL(baseURL)
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw LLMError.missingAPIKey }

        let response = try await transport.send(HTTPRequest(
            url: url.appendingPathComponent("models"),
            method: "GET",
            headers: ["Authorization": "Bearer \(key)"].merging(LLMConfiguration.cleaned(extraHeaders)) { current, _ in current },
            body: nil
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw LLMError.http(status: response.statusCode, message: nil)
        }
        guard let list = try? JSONDecoder().decode(ModelList.self, from: response.body) else {
            throw LLMError.invalidResponse
        }
        return list.data.map(ModelInfo.init).sorted { $0.id.localizedStandardCompare($1.id) == .orderedAscending }
    }

    /// Modelin kartı (`GET /models/{id}`): efor desteği, görsel ve bağlam uzunluğu.
    /// Bu uç noktayı sunmayan veya yetenek bildirmeyen sunucularda `nil` döner; hata fırlatmaz.
    public static func modelDetails(
        baseURL: String,
        apiKey: String,
        extraHeaders: [String: String] = [:],
        modelID: String,
        transport: any HTTPTransport
    ) async -> ModelInfo? {
        guard let url = try? LLMConfiguration.validatedBaseURL(baseURL),
              let encoded = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let target = URL(string: url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/models/" + encoded)
        else { return nil }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let response = try? await transport.send(HTTPRequest(
            url: target,
            method: "GET",
            headers: ["Authorization": "Bearer \(key)"].merging(LLMConfiguration.cleaned(extraHeaders)) { current, _ in current },
            body: nil
        )), (200..<300).contains(response.statusCode),
            let card = try? JSONDecoder().decode(ModelCard.self, from: response.body)
        else { return nil }
        return card.info
    }

    func makeRequest(_ messages: [ChatMessage], tools: [ToolDefinition] = [], useServerTools: Bool = false) throws -> HTTPRequest {
        let server = useServerTools ? configuration.serverTools : nil
        let requestTools = tools.map(RequestTool.function) + (server?.tools ?? []).map(RequestTool.server)
        let body = try JSONEncoder().encode(
            ChatCompletionRequest(
                model: configuration.model,
                messages: messages.map(WireMessage.init),
                stream: true,
                tools: requestTools.isEmpty ? nil : requestTools,
                reasoningEffort: configuration.reasoningEffort,
                maxToolCalls: server?.maxToolCalls
            )
        )
        return HTTPRequest(
            url: configuration.baseURL.appendingPathComponent("chat/completions"),
            method: "POST",
            headers: configuration.headers([
                "Authorization": "Bearer \(configuration.apiKey)",
                "Content-Type": "application/json",
                "Accept": "text/event-stream",
            ]),
            body: body
        )
    }

    private func run(_ messages: [ChatMessage], tools: [ToolDefinition], useServerTools: Bool, onEvent: (LLMStreamEvent) -> Void) async throws {
        let decoder = JSONDecoder()
        var toolCalls = ToolCallAccumulator()
        var usage: ChatCompletionChunk.Usage?
        // Token/saniye için: düşünme (reasoning) parçaları da üretim süresine dahildir.
        let clock = ContinuousClock()
        var firstChunk: ContinuousClock.Instant?
        var lastChunk: ContinuousClock.Instant?
        do {
            lines: for try await line in transport.lines(for: try makeRequest(messages, tools: tools, useServerTools: useServerTools)) {
                switch SSELine(line) {
                case .ignored:
                    continue
                case .done:
                    break lines
                case let .data(json):
                    let data = Data(json.utf8)
                    if let chunk = try? decoder.decode(ChatCompletionChunk.self, from: data) {
                        if let chunkUsage = chunk.usage {
                            usage = chunkUsage
                        }
                        guard let delta = chunk.choices.first?.delta else { continue }
                        let now = clock.now
                        firstChunk = firstChunk ?? now
                        lastChunk = now
                        if let thought = delta.reasoning ?? delta.reasoningContent, !thought.isEmpty {
                            onEvent(.reasoning(thought))
                        }
                        if let text = delta.content, !text.isEmpty {
                            onEvent(.text(text))
                        }
                        let citations = delta.citations
                        if !citations.isEmpty {
                            onEvent(.citations(citations))
                        }
                        delta.toolCalls?.forEach { toolCalls.add($0) }
                        if let progress = toolCalls.progressUpdate() {
                            onEvent(.toolCallProgress(name: progress.name, characters: progress.characters))
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
        if !toolCalls.isEmpty {
            onEvent(.toolCalls(toolCalls.calls))
        }
        if let usage {
            let seconds = firstChunk.flatMap { first in lastChunk.map { ($0 - first).seconds } }
            onEvent(.usage(TokenUsage(
                promptTokens: usage.prompt_tokens ?? 0,
                completionTokens: usage.completion_tokens ?? 0,
                generationSeconds: seconds,
                webSearchRequests: usage.webSearchRequests
            )))
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

    /// Mesajda API key veya ek başlık değerleri geçiyorsa gizler.
    private func redacted(_ message: String) -> String? {
        let secrets = [configuration.apiKey] + configuration.extraHeaders.values.filter { $0.count >= 6 }
        let text = secrets
            .reduce(message) { $0.replacingOccurrences(of: $1, with: "***") }
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

/// Parça parça gelen araç çağrılarını `index`'e göre birleştirir.
private struct ToolCallAccumulator {
    private var parts: [Int: (id: String?, name: String, arguments: String)] = [:]

    var isEmpty: Bool { parts.isEmpty }

    /// Son bildirimden bu yana yeterince (≥ 200 karakter) ilerlendiyse yazılmakta olan çağrının adı ve argüman uzunluğu.
    private var lastReported = -1
    mutating func progressUpdate() -> (name: String, characters: Int)? {
        guard let part = parts.max(by: { $0.key < $1.key })?.value, !part.name.isEmpty else { return nil }
        let characters = part.arguments.count
        guard lastReported < 0 || characters - lastReported >= 200 else { return nil }
        lastReported = characters
        return (part.name, characters)
    }

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
