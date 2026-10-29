import Foundation

public enum AgentEvent: Equatable, Sendable {
    /// Cevap metninin bir parçası.
    case text(String)
    /// Bir araç çalışmaya başladı. `id` araç çağrısının kimliği.
    case toolStarted(id: String, name: String, activity: String)
    case toolFinished(id: String, sources: [Source], files: [URL], failed: Bool)
    /// Geçmişe eklenmesi gereken tam bir mesaj (araç çağrısı, araç sonucu veya final cevap).
    case message(ChatMessage)
}

/// Model araç istedikçe araçları çalıştırıp sonucu geri veren döngü.
public struct AgentLoop: Sendable {
    private let client: LLMClient
    private let tools: [String: any Tool]
    private let maxSteps: Int

    /// `maxSteps`: bir istekte modele en fazla kaç kez gidileceği. Son adımda araç verilmez, model cevap vermek zorunda kalır.
    public init(client: LLMClient, tools: [any Tool], maxSteps: Int = 8) {
        self.client = client
        self.tools = Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        self.maxSteps = max(1, maxSteps)
    }

    public func run(_ messages: [ChatMessage]) -> AsyncThrowingStream<AgentEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await loop(messages) { continuation.yield($0) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func loop(_ messages: [ChatMessage], emit: (AgentEvent) -> Void) async throws {
        var conversation = messages
        let definitions = tools.values.map(\.definition).sorted { $0.function.name < $1.function.name }

        for step in 1...maxSteps {
            var text = ""
            var calls: [ToolCall] = []
            let offeredTools = step < maxSteps ? definitions : []

            for try await event in client.streamChat(conversation, tools: offeredTools) {
                switch event {
                case let .text(delta):
                    text += delta
                    emit(.text(delta))
                case let .toolCalls(requested):
                    calls = requested
                }
            }

            let assistant = ChatMessage(
                role: .assistant,
                content: text.isEmpty ? nil : text,
                toolCalls: calls.isEmpty ? nil : calls
            )
            conversation.append(assistant)
            emit(.message(assistant))

            if calls.isEmpty || offeredTools.isEmpty {
                return
            }

            for call in calls {
                try Task.checkCancellation()
                let result = try await execute(call, emit: emit)
                conversation.append(result)
                emit(.message(result))
            }
        }
    }

    /// Aracı çalıştırır; hataları modele metin olarak döner ki model toparlayabilsin.
    private func execute(_ call: ToolCall, emit: (AgentEvent) -> Void) async throws -> ChatMessage {
        guard let tool = tools[call.function.name] else {
            emit(.toolStarted(id: call.id, name: call.function.name, activity: call.function.name))
            emit(.toolFinished(id: call.id, sources: [], files: [], failed: true))
            return ChatMessage(role: .tool, content: "Hata: '\(call.function.name)' adında bir araç yok.", toolCallID: call.id)
        }

        emit(.toolStarted(id: call.id, name: tool.name, activity: tool.activity(for: call.function.arguments) ?? tool.name))
        do {
            let output = try await tool.run(arguments: call.function.arguments)
            emit(.toolFinished(id: call.id, sources: output.sources, files: output.files, failed: false))
            return ChatMessage(role: .tool, content: output.content, toolCallID: call.id)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            emit(.toolFinished(id: call.id, sources: [], files: [], failed: true))
            return ChatMessage(role: .tool, content: "Hata: \(error.localizedDescription)", toolCallID: call.id)
        }
    }
}
