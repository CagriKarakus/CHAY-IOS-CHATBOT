import AgentCore
import Foundation
import Observation

struct ChatItem: Identifiable {
    let id = UUID()
    var message: ChatMessage
}

/// Bellekteki sohbet geçmişi ve streaming cevap.
@Observable @MainActor
final class ChatViewModel {
    private(set) var items: [ChatItem] = []
    private(set) var isStreaming = false
    var input = ""
    var errorMessage: String?

    var canSend: Bool {
        !isStreaming && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send(using settings: AppSettings) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }

        let configuration: LLMConfiguration
        do {
            configuration = try settings.configuration()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        input = ""
        errorMessage = nil
        items.append(ChatItem(message: ChatMessage(role: .user, content: text)))
        let history = items.map(\.message)
        let reply = ChatItem(message: ChatMessage(role: .assistant, content: ""))
        items.append(reply)
        isStreaming = true

        let client = LLMClient(configuration: configuration, transport: URLSessionTransport())
        Task {
            do {
                for try await delta in client.streamChat(history) {
                    appendToReply(reply.id, delta)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            if let index = items.firstIndex(where: { $0.id == reply.id }), items[index].message.content?.isEmpty ?? true {
                items.remove(at: index)
            }
            isStreaming = false
        }
    }

    private func appendToReply(_ id: ChatItem.ID, _ delta: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].message.content = (items[index].message.content ?? "") + delta
    }
}
