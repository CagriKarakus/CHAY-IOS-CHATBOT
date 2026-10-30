import Foundation

public enum AgentEvent: Equatable, Sendable {
    /// Cevap metninin bir parçası.
    case text(String)
    /// Modelin düşünme metninin bir parçası.
    case reasoning(String)
    /// Model bir aracın argümanlarını yazıyor; araç henüz çalışmadı.
    case preparingTool(name: String, characters: Int)
    /// Bir araç çalışmaya başladı. `id` araç çağrısının kimliği.
    case toolStarted(id: String, name: String, detail: String?)
    case toolFinished(id: String, sources: [Source], files: [URL], failed: Bool)
    /// Geçmişe eklenmesi gereken tam bir mesaj (araç çağrısı, araç sonucu veya final cevap).
    case message(ChatMessage)
    /// Bir model çağrısının token kullanımı (adım başına bir kez).
    case usage(TokenUsage)
}

/// Kullanıcıdan onay istenen araç çağrısı.
public struct ApprovalRequest: Equatable, Sendable {
    public let toolName: String
    /// Aracın ayrıntısı (örn. kaydedilecek not).
    public let detail: String?
    /// Modelin araca verdiği argümanlar (JSON).
    public var arguments: String? = nil
}

/// Model araç istedikçe araçları çalıştırıp sonucu geri veren döngü.
public struct AgentLoop: Sendable {
    public typealias Approver = @Sendable (ApprovalRequest) async -> Bool

    private let client: LLMClient
    private let tools: [String: any Tool]
    private let maxSteps: Int
    private let approve: Approver
    private let refreshTools: (@Sendable () async -> [any Tool])?

    /// `maxSteps`: bir istekte modele en fazla kaç kez gidileceği. Son adımda araç verilmez, model cevap vermek zorunda kalır.
    /// `approve`: onay gerektiren araç çağrılarında kullanıcıya sorar; verilmezse bu çağrılar reddedilir.
    /// `refreshTools`: her adımdan önce güncel araç listesini verir (ör. turda yeni bağlanan bağlayıcılar için).
    public init(
        client: LLMClient,
        tools: [any Tool],
        maxSteps: Int = 8,
        approve: @escaping Approver = { _ in false },
        refreshTools: (@Sendable () async -> [any Tool])? = nil
    ) {
        self.client = client
        self.tools = Self.index(tools)
        self.maxSteps = max(1, maxSteps)
        self.approve = approve
        self.refreshTools = refreshTools
    }

    private static func index(_ tools: [any Tool]) -> [String: any Tool] {
        Dictionary(tools.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
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
        var tools = self.tools

        for step in 1...maxSteps {
            if let refreshTools {
                tools = Self.index(await refreshTools())
            }
            let definitions = tools.values.map(\.definition).sorted { $0.function.name < $1.function.name }
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
                case let .usage(usage):
                    emit(.usage(usage))
                case let .reasoning(thought):
                    emit(.reasoning(thought))
                case let .toolCallProgress(name, characters):
                    emit(.preparingTool(name: name, characters: characters))
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
                let result = try await execute(call, tools: tools, conversation: conversation, emit: emit)
                conversation.append(result)
                emit(.message(result))
            }
        }
    }

    /// Aracı çalıştırır; hataları modele metin olarak döner ki model toparlayabilsin.
    private func execute(_ call: ToolCall, tools: [String: any Tool], conversation: [ChatMessage], emit: (AgentEvent) -> Void) async throws -> ChatMessage {
        guard let tool = tools[call.function.name] else {
            emit(.toolStarted(id: call.id, name: call.function.name, detail: nil))
            emit(.toolFinished(id: call.id, sources: [], files: [], failed: true))
            return ChatMessage(role: .tool, content: "Error: there is no tool named '\(call.function.name)'.", toolCallID: call.id)
        }

        let detail = tool.activityDetail(for: call.function.arguments)
        emit(.toolStarted(id: call.id, name: tool.name, detail: detail))

        // Web içeriği okunduktan sonra hafıza gibi kalıcı işlemler ve veri değiştiren bağlayıcı araçları
        // kullanıcı onayı olmadan yapılmaz.
        if tool.requiresApproval || (tool.requiresApprovalAfterUntrustedContent && containsUntrustedContent(conversation)) {
            let approved = await approve(ApprovalRequest(
                toolName: tool.name,
                detail: detail,
                arguments: tool.requiresApproval ? call.function.arguments : nil
            ))
            try Task.checkCancellation()
            guard approved else {
                emit(.toolFinished(id: call.id, sources: [], files: [], failed: true))
                return ChatMessage(role: .tool, content: "The user declined this action; do not retry it.", toolCallID: call.id)
            }
        }

        do {
            let output = try await tool.run(arguments: call.function.arguments)
            emit(.toolFinished(id: call.id, sources: output.sources, files: output.files, failed: false))
            return ChatMessage(role: .tool, content: output.content, toolCallID: call.id)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            emit(.toolFinished(id: call.id, sources: [], files: [], failed: true))
            return ChatMessage(role: .tool, content: "Error: \(error.localizedDescription)", toolCallID: call.id)
        }
    }

    /// Geçmişte (önceki istekler dahil) web'den gelen bir araç sonucu var mı.
    private func containsUntrustedContent(_ conversation: [ChatMessage]) -> Bool {
        conversation.contains { $0.role == .tool && ($0.content?.contains(untrustedContentMarker) ?? false) }
    }
}
