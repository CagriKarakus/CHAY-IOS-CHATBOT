import AgentCore
import Foundation
import Observation

/// Ekrandaki bir mesaj. Asistan mesajı, bir istekteki tüm adımları (araçlar + cevap) toplar.
struct ChatItem: Identifiable {
    enum Role {
        case user, assistant
    }

    let id = UUID()
    let role: Role
    var text: String
    var activities: [ToolActivity] = []
    var sources: [Source] = []
    var files: [URL] = []
}

struct ToolActivity: Identifiable {
    enum State {
        case running, done, failed
    }

    let id: String
    let toolName: String
    let title: String
    var state: State = .running
}

/// Bellekteki sohbet: ekran mesajları + modele giden geçmiş.
@Observable @MainActor
final class ChatViewModel {
    private(set) var items: [ChatItem] = []
    private(set) var isStreaming = false
    var input = ""
    var errorMessage: String?

    /// Modele giden mesajlar (sistem mesajı hariç): kullanıcı, asistan, araç çağrıları ve sonuçları.
    private var history: [ChatMessage] = []

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
        items.append(ChatItem(role: .user, text: text))
        history.append(ChatMessage(role: .user, content: text))
        let reply = ChatItem(role: .assistant, text: "")
        items.append(reply)
        isStreaming = true

        let transport = URLSessionTransport()
        let agent = AgentLoop(
            client: LLMClient(configuration: configuration, transport: transport),
            tools: [
                WebSearchTool(apiKey: settings.tavilyKey, transport: transport),
                FetchPageTool(transport: transport),
                WriteFileTool(directory: DocumentFile.directory),
            ]
        )
        let systemPrompt = SystemPrompt.make(userInstructions: settings.userInstructions)
        let messages = [ChatMessage(role: .system, content: systemPrompt)] + history

        Task {
            do {
                for try await event in agent.run(messages) {
                    apply(event, to: reply.id)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            if let index = items.firstIndex(where: { $0.id == reply.id }),
               items[index].text.isEmpty, items[index].activities.isEmpty {
                items.remove(at: index)
            }
            isStreaming = false
        }
    }

    private func apply(_ event: AgentEvent, to id: ChatItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        switch event {
        case let .text(delta):
            items[index].text += delta
        case let .toolStarted(callID, name, activity):
            // Araçtan önce yazılmış metinle sonraki cevap birbirine yapışmasın.
            if !items[index].text.isEmpty, !items[index].text.hasSuffix("\n\n") {
                items[index].text += "\n\n"
            }
            items[index].activities.append(ToolActivity(id: callID, toolName: name, title: activity))
        case let .toolFinished(callID, sources, files, failed):
            if let activity = items[index].activities.firstIndex(where: { $0.id == callID }) {
                items[index].activities[activity].state = failed ? .failed : .done
            }
            items[index].files += files
            for source in sources where !items[index].sources.contains(where: { $0.url == source.url }) {
                items[index].sources.append(source)
            }
        case let .message(message):
            history.append(message)
        }
    }
}
