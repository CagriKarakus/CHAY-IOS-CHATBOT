import AgentCore
import Foundation
import Observation
import SwiftData
import UIKit

/// Ekrandaki bir mesaj. Asistan mesajı, bir istekteki tüm adımları (araçlar + cevap) toplar.
struct ChatItem: Identifiable, Codable {
    enum Role: String, Codable {
        case user, assistant
    }

    var id = UUID()
    let role: Role
    var text: String
    var activities: [ToolActivity] = []
    var sources: [Source] = []
    /// Documents klasöründeki dosya adları (uygulama güncellenince klasör yolu değişebildiği için tam yol tutulmaz).
    var files: [String] = []
}

struct ToolActivity: Identifiable, Codable {
    enum State: String, Codable {
        case running, done, failed
    }

    let id: String
    let toolName: String
    let title: String
    var state: State = .running
}

/// Kullanıcıdan onay bekleyen bir araç çağrısı (örn. web okunduktan sonra hafızaya not).
struct PendingApproval: Identifiable {
    let id = UUID()
    let request: ApprovalRequest
}

/// Açık sohbet: ekran mesajları + modele giden geçmiş. Her turda SwiftData'ya kaydedilir.
@Observable @MainActor
final class ChatViewModel {
    private(set) var items: [ChatItem] = []
    private(set) var isStreaming = false
    private(set) var pendingApproval: PendingApproval?
    /// Açık sohbetin kaydı; ilk mesaj gönderilene kadar `nil`.
    private(set) var conversationID: UUID?
    var input = ""
    var errorMessage: String?

    /// Modele giden mesajlar (sistem mesajı hariç): kullanıcı, asistan, araç çağrıları ve sonuçları.
    private var history: [ChatMessage] = []
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var context: ModelContext?

    var canSend: Bool {
        !isStreaming && !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Son istek hata verdiyse ve cevapsız kaldıysa aynı geçmişle tekrar denenebilir.
    var canRetry: Bool {
        !isStreaming && errorMessage != nil && history.last.map { $0.role == .user || $0.role == .tool } == true
    }

    func attach(_ context: ModelContext) {
        self.context = context
    }

    /// Ekranı ve geçmişi temizler; önceki sohbet kayıtlı kalır.
    func startNewChat() {
        guard !isStreaming else { return }
        items = []
        history = []
        conversationID = nil
        errorMessage = nil
    }

    func open(_ record: ConversationRecord) {
        guard !isStreaming else { return }
        let content = record.content
        items = content.items.map { item in
            var item = item
            // Uygulama istek ortasında kapandıysa yarım kalan araçlar başarısız sayılır.
            for index in item.activities.indices where item.activities[index].state == .running {
                item.activities[index].state = .failed
            }
            return item
        }
        history = content.history
        conversationID = record.id
        errorMessage = nil
    }

    func resolveApproval(_ approved: Bool) {
        approvalContinuation?.resume(returning: approved)
        approvalContinuation = nil
        pendingApproval = nil
    }

    private func requestApproval(_ request: ApprovalRequest) async -> Bool {
        await withCheckedContinuation { continuation in
            approvalContinuation = continuation
            pendingApproval = PendingApproval(request: request)
        }
    }

    func send(using settings: AppSettings) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        do {
            _ = try settings.configuration()
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        input = ""
        errorMessage = nil
        items.append(ChatItem(role: .user, text: text))
        history.append(ChatMessage(role: .user, content: text))
        persist()
        runTurn(using: settings)
    }

    func retry(using settings: AppSettings) {
        guard canRetry else { return }
        errorMessage = nil
        runTurn(using: settings)
    }

    private func runTurn(using settings: AppSettings) {
        let configuration: LLMConfiguration
        do {
            configuration = try settings.configuration()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard let context else { return }
        let notes = SwiftDataNoteStore(context: context)

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
                SaveNoteTool(store: notes),
                ReadNotesTool(store: notes),
            ],
            approve: { [weak self] request in
                await self?.requestApproval(request) ?? false
            }
        )
        let userInstructions = settings.userInstructions
        let conversation = history
        // Kullanıcı uygulamadan çıkarsa iOS'un verdiği ek sürede istek tamamlansın.
        let background = BackgroundActivity(name: "AgentTurn")

        Task {
            do {
                let systemPrompt = SystemPrompt.make(notes: try await notes.allNotes(), userInstructions: userInstructions)
                let messages = [ChatMessage(role: .system, content: systemPrompt)] + conversation
                for try await event in agent.run(messages) {
                    apply(event, to: reply.id)
                }
            } catch is CancellationError {
            } catch {
                errorMessage = userFacingMessage(for: error)
            }
            if let index = items.firstIndex(where: { $0.id == reply.id }),
               items[index].text.isEmpty, items[index].activities.isEmpty {
                items.remove(at: index)
            }
            isStreaming = false
            persist()
            background.end()
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
            for name in files.map(\.lastPathComponent) where !items[index].files.contains(name) {
                items[index].files.append(name)
            }
            for source in sources where !items[index].sources.contains(where: { $0.url == source.url }) {
                items[index].sources.append(source)
            }
        case let .message(message):
            history.append(message)
        }
    }

    /// Açık sohbeti kaydeder; ilk kayıtta yeni bir `ConversationRecord` oluşturur.
    private func persist() {
        guard let context, !items.isEmpty else { return }
        let content = ConversationContent(items: items, history: history)

        if let conversationID,
           let record = try? context.fetch(FetchDescriptor<ConversationRecord>(predicate: #Predicate { $0.id == conversationID })).first {
            record.update(content)
        } else {
            let record = ConversationRecord(content: content)
            context.insert(record)
            conversationID = record.id
        }
        try? context.save()
    }
}

/// `beginBackgroundTask` sarmalayıcısı: iOS süre dolduğunu bildirirse görev hemen kapatılır.
@MainActor
private final class BackgroundActivity {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init(name: String) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
