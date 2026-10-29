import AgentCore
import Foundation
import Observation
import SwiftData
import UIKit

/// Ekrandaki bir mesaj. Asistan mesajı, bir istekteki tüm adımları (araçlar + cevap) toplar.
/// Yeni alanlar opsiyonel olmalı ki eski kayıtlı sohbetler açılabilsin.
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
    /// Bu cevaptaki tüm model çağrılarının toplam kullanımı.
    var usage: TokenUsage?
    /// Kullanıcı durdurduysa `true`.
    var stopped: Bool?
    /// Kullanıcı mesajındaki eklerin önizlemesi (tam veri `history`'de).
    var attachments: [AttachmentPreview]?
    /// Üretilen görsellerin Documents'taki dosya adları.
    var images: [String]?
    /// Modelin düşünme metni (gösterim için; modele geri gönderilmez).
    var reasoning: String?
    /// Model bir aracın argümanlarını yazarken (ör. uzun artifact) gösterilen ilerleme.
    var preparing: PreparingTool?
}

struct AttachmentPreview: Codable, Hashable {
    let kind: Attachment.Kind
    /// Görseller için küçük JPEG.
    let thumbnail: Data?
    /// Ses kayıtları için süre (saniye).
    let duration: Double?
    /// Dokümanların dosya adı.
    var name: String? = nil
    /// Görselin tam boyutlu kopyası (`AttachmentFiles`), büyütüp göstermek için.
    var file: String? = nil
}

/// Henüz çalışmamış, argümanları akmakta olan araç çağrısı.
struct PreparingTool: Codable, Hashable {
    let toolName: String
    let characters: Int
}

/// Gönderilmeyi bekleyen ek.
struct PendingAttachment: Identifiable {
    let id = UUID()
    let attachment: Attachment
    let preview: AttachmentPreview
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
    /// Son istekteki giriş tokenı (veya tahmini) bunu aşarsa eski mesajlar özetlenir.
    private static let compactionThreshold = 48_000
    /// Özetlenmeden korunan son kullanıcı turu sayısı.
    private static let keptTurns = 2

    private(set) var items: [ChatItem] = []
    private(set) var isStreaming = false
    private(set) var pendingApproval: PendingApproval?
    private(set) var pendingAttachments: [PendingAttachment] = []
    /// Açık sohbetin kaydı; ilk mesaj gönderilene kadar `nil`.
    private(set) var conversationID: UUID?
    /// Gizli sohbet: kaydedilmez, hafıza okunmaz ve yazılmaz.
    private(set) var isIncognito = false
    /// Sohbetin ait olduğu proje; talimatları ve dosyaları her istekte system prompt'a eklenir.
    private(set) var projectID: UUID?
    private(set) var projectName: String?
    /// Bu sohbette hafıza kullanılsın mı (sohbete özel).
    private(set) var memoryEnabled = true
    /// Bu sohbette seçili skill'ler; `nil` ise kütüphanedeki varsayılanlar.
    private(set) var selectedSkillIDs: Set<UUID>?
    /// Düzenlenmekte olan kullanıcı mesajı; gönderilince o mesaj ve sonrası yeniden oluşturulur.
    private(set) var editingItemID: ChatItem.ID?
    /// Bu sohbete özel model (ör. kestirmenin seçtiği); `nil` ise Ayarlar'daki seçili model.
    private(set) var modelOverrideID: UUID?

    /// Uygulama şu an arka planda mı (ChatView bildirir).
    private var isInBackground = false
    /// Bu tur sürerken uygulama arka plana geçti mi.
    private var backgroundedDuringTurn = false
    /// Arka planda kesilen istek; uygulamaya dönülünce kendiliğinden yeniden denenir.
    private var resumeOnForeground = false
    private var lastSettings: AppSettings?
    var input = ""
    var errorMessage: String?

    /// Hafıza bu sohbette gerçekten kullanılıyor mu.
    var usesMemory: Bool {
        memoryEnabled && !isIncognito
    }

    /// Modele giden mesajlar (sistem mesajı hariç): kullanıcı, asistan, araç çağrıları ve sonuçları.
    private var history: [ChatMessage] = []
    /// Sıkıştırılan eski mesajların özeti; system prompt'a eklenir.
    private var summary: String?
    private var lastPromptTokens: Int?
    /// Henüz `.message` olarak gelmemiş, akmakta olan adımın metni (durdurulursa geçmişe eklenir).
    private var pendingStepText = ""
    private var turnTask: Task<Void, Never>?
    private var approvalContinuation: CheckedContinuation<Bool, Never>?
    private var context: ModelContext?
    private var usageTracker: UsageTracker?
    private var skillLibrary: SkillLibrary?
    /// Bu turdaki aramaların sayılacağı servis.
    private var currentModel: (providerID: UUID, name: String)?

    var canSend: Bool {
        !isStreaming && (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingAttachments.isEmpty)
    }

    func addImage(_ data: Data) {
        guard let prepared = preparedImage(from: data) else {
            errorMessage = L("Couldn't read the image.", "Görsel okunamadı.")
            return
        }
        pendingAttachments.append(PendingAttachment(
            attachment: Attachment(kind: .image, mimeType: "image/jpeg", data: prepared.jpeg),
            preview: AttachmentPreview(kind: .image, thumbnail: prepared.thumbnail, duration: nil, file: AttachmentFiles.save(prepared.jpeg))
        ))
    }

    /// PDF/metin dosyasından çıkarılan metni ekler; çok uzunsa kırpılır.
    func addDocument(text: String, name: String) {
        let limit = 60_000
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = L("No text found in this file. Scanned PDFs (images only) can't be read.",
                             "Bu dosyada metin bulunamadı. Taranmış (sadece görüntüden oluşan) PDF'ler okunamaz.")
            return
        }
        let body = trimmed.count > limit ? String(trimmed.prefix(limit)) + "\n[…truncated at \(limit) characters]" : trimmed
        pendingAttachments.append(PendingAttachment(
            attachment: Attachment(kind: .document, mimeType: "text/plain", data: Data(body.utf8), name: name),
            preview: AttachmentPreview(kind: .document, thumbnail: nil, duration: nil, name: name)
        ))
    }

    func addAudio(_ data: Data, duration: TimeInterval) {
        pendingAttachments.append(PendingAttachment(
            attachment: Attachment(kind: .audio, mimeType: "audio/wav", data: data),
            preview: AttachmentPreview(kind: .audio, thumbnail: nil, duration: duration)
        ))
    }

    func removeAttachment(_ id: PendingAttachment.ID) {
        pendingAttachments.removeAll { $0.id == id }
    }

    /// Son istek hata verdiyse ve cevapsız kaldıysa aynı geçmişle tekrar denenebilir.
    var canRetry: Bool {
        !isStreaming && errorMessage != nil && history.last.map { $0.role == .user || $0.role == .tool } == true
    }

    func attach(_ context: ModelContext, usage: UsageTracker, skills: SkillLibrary) {
        self.context = context
        usageTracker = usage
        skillLibrary = skills
    }

    /// Ekranı ve geçmişi temizler; önceki sohbet kayıtlı kalır (gizli sohbet hiç kaydedilmez).
    /// Kullanıcı model seçicisinden model değiştirince sohbete özel model bırakılır.
    func clearModelOverride() {
        modelOverrideID = nil
    }

    func startNewChat(incognito: Bool = false, project: ProjectRecord? = nil, modelOverride: UUID? = nil) {
        guard !isStreaming else { return }
        if isIncognito {
            AttachmentFiles.delete(items.flatMap { $0.attachments ?? [] }.compactMap(\.file))
        }
        items = []
        history = []
        summary = nil
        lastPromptTokens = nil
        conversationID = nil
        errorMessage = nil
        isIncognito = incognito
        projectID = incognito ? nil : project?.id
        projectName = incognito ? nil : project?.name
        memoryEnabled = true
        selectedSkillIDs = nil
        editingItemID = nil
        modelOverrideID = modelOverride
    }

    // MARK: - Düzenle / yeniden üret

    /// Kullanıcı mesajının modele giden geçmişteki yeri; eski mesajlar bağlam sıkıştırmasıyla
    /// özetlendiyse `nil` (o mesaj artık düzenlenemez).
    private func historyIndex(ofUserItem id: ChatItem.ID) -> Int? {
        let userItems = items.filter { $0.role == .user }
        guard let position = userItems.firstIndex(where: { $0.id == id }) else { return nil }
        let fromEnd = userItems.count - 1 - position
        let userIndices = history.indices.filter { history[$0].role == .user }
        guard fromEnd < userIndices.count else { return nil }
        return userIndices[userIndices.count - 1 - fromEnd]
    }

    func canEdit(_ item: ChatItem) -> Bool {
        !isStreaming && item.role == .user && historyIndex(ofUserItem: item.id) != nil
    }

    /// Mesajı (ekleriyle) giriş kutusuna geri koyar; gönderilince bu mesajdan sonrası silinip yeniden sorulur.
    func beginEditing(_ item: ChatItem) {
        guard canEdit(item), let index = historyIndex(ofUserItem: item.id) else { return }
        input = item.text
        let full = history[index].attachments ?? []
        pendingAttachments = zip(full, item.attachments ?? []).map { PendingAttachment(attachment: $0, preview: $1) }
        editingItemID = item.id
        errorMessage = nil
    }

    func cancelEditing() {
        editingItemID = nil
        input = ""
        pendingAttachments = []
    }

    var canRegenerate: Bool {
        !isStreaming && items.last?.role == .assistant && history.contains { $0.role == .user }
    }

    /// Son cevabı siler ve son kullanıcı mesajını (seçili modelle) yeniden gönderir.
    func regenerate(using settings: AppSettings) {
        guard canRegenerate,
              let lastUserItem = items.lastIndex(where: { $0.role == .user }),
              let lastUserMessage = history.lastIndex(where: { $0.role == .user })
        else { return }
        items.removeSubrange(items.index(after: lastUserItem)...)
        history.removeSubrange(history.index(after: lastUserMessage)...)
        errorMessage = nil
        if settings.selection(for: modelOverrideID)?.model.generatesImages == true {
            generateImage(prompt: history[lastUserMessage].content ?? "", using: settings)
        } else {
            runTurn(using: settings)
        }
    }

    /// Dışa aktarma ve dosya adları için sohbet başlığı.
    var title: String {
        ConversationRecord.title(for: ConversationContent(items: items, history: []))
    }

    func setMemoryEnabled(_ enabled: Bool) {
        memoryEnabled = enabled
        persist()
    }

    func isSkillActive(_ skill: InstalledSkill) -> Bool {
        selectedSkillIDs?.contains(skill.id) ?? skill.enabledByDefault
    }

    /// Skill'i bu sohbette açar/kapatır; ilk değişiklikte varsayılanlar sohbete kopyalanır.
    func setSkill(_ skill: InstalledSkill, active: Bool) {
        var selection = selectedSkillIDs ?? Set(skillLibrary?.active(in: nil).map(\.id) ?? [])
        if active { selection.insert(skill.id) } else { selection.remove(skill.id) }
        selectedSkillIDs = selection
        persist()
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
        history = content.history.closingUnansweredToolCalls()
        summary = content.summary
        lastPromptTokens = content.lastPromptTokens
        memoryEnabled = content.memoryEnabled ?? true
        selectedSkillIDs = content.skillIDs.map(Set.init)
        conversationID = record.id
        projectID = record.projectID
        projectName = record.projectID.flatMap { id in context.flatMap { ProjectRecord.find(id, in: $0)?.name } }
        isIncognito = false
        modelOverrideID = content.modelID
        errorMessage = nil
    }

    /// Devam eden cevabı hemen keser.
    // MARK: - Arka plan

    func appMovedToBackground() {
        isInBackground = true
        if isStreaming {
            backgroundedDuringTurn = true
            TurnNotifications.scheduleStillRunning()
        }
    }

    func appBecameActive() {
        isInBackground = false
        TurnNotifications.cancelStillRunning()
        guard resumeOnForeground else { return }
        resumeOnForeground = false
        if let settings = lastSettings, canRetry {
            retry(using: settings)
        }
    }

    private func beginTurn(using settings: AppSettings) {
        isStreaming = true
        backgroundedDuringTurn = isInBackground
        lastSettings = settings
    }

    /// Hata mesajı; iOS'un arka planda kestiği istek sunucu hatasıyla karışmasın diye ayrı anlatılır.
    private func handleFailure(_ error: any Error) {
        if backgroundedDuringTurn, error is URLError {
            errorMessage = L("The request was interrupted because the app was in the background. It continues when you return to CHAY.",
                             "Uygulama arka planda olduğu için istek yarıda kesildi. CHAY'a döndüğünde kaldığı yerden devam eder.")
            resumeOnForeground = true
        } else {
            errorMessage = userFacingMessage(for: error)
        }
    }

    private func endTurn() {
        if isInBackground, errorMessage == nil {
            TurnNotifications.notifyFinished(title: title)
        } else {
            TurnNotifications.cancelStillRunning()
        }
        backgroundedDuringTurn = false
    }

    func stop() {
        turnTask?.cancel()
        resolveApproval(false)
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
        TurnNotifications.requestPermissionIfNeeded()
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        do {
            _ = try settings.configuration(modelID: modelOverrideID)
        } catch {
            errorMessage = userFacingMessage(for: error)
            return
        }

        // Seçili model ekin türünü desteklemiyorsa gönderme (ör. model sonradan değiştirildiyse).
        let model = settings.selection(for: modelOverrideID)?.model
        if pendingAttachments.contains(where: { $0.attachment.kind == .image }), model?.acceptsImages != true {
            errorMessage = L("This model doesn't accept images. Choose another model or remove the image.",
                             "Bu model görsel kabul etmiyor. Başka bir model seç ya da görseli kaldır.")
            return
        }
        if pendingAttachments.contains(where: { $0.attachment.kind == .audio }), model?.acceptsAudio != true {
            errorMessage = L("This model doesn't accept audio. Choose another model or remove the recording.",
                             "Bu model ses kabul etmiyor. Başka bir model seç ya da kaydı kaldır.")
            return
        }

        // Düzenlenen mesaj: o mesaj ve sonrası silinir, yeni hali gönderilir.
        if let editing = editingItemID {
            if let itemIndex = items.firstIndex(where: { $0.id == editing }),
               let messageIndex = historyIndex(ofUserItem: editing) {
                items.removeSubrange(itemIndex...)
                history.removeSubrange(messageIndex...)
                lastPromptTokens = nil
            }
            editingItemID = nil
        }

        let attachments = pendingAttachments
        input = ""
        pendingAttachments = []
        errorMessage = nil
        items.append(ChatItem(role: .user, text: text, attachments: attachments.isEmpty ? nil : attachments.map(\.preview)))
        history.append(ChatMessage(
            role: .user,
            content: text,
            attachments: attachments.isEmpty ? nil : attachments.map(\.attachment)
        ))
        persist()
        if model?.generatesImages == true {
            generateImage(prompt: text, using: settings)
        } else {
            runTurn(using: settings)
        }
    }

    /// Görsel üreten modellerde mesaj, sohbet yerine `/images/generations`'a istem olarak gider.
    private func generateImage(prompt: String, using settings: AppSettings) {
        let configuration: LLMConfiguration
        do {
            configuration = try settings.configuration(modelID: modelOverrideID)
        } catch {
            errorMessage = userFacingMessage(for: error)
            return
        }
        var reply = ChatItem(role: .assistant, text: "")
        reply.activities = [ToolActivity(id: "image-\(reply.id)", toolName: "generate_image", title: L("Generating image", "Görsel üretiliyor"))]
        items.append(reply)
        beginTurn(using: settings)
        let generator = ImageGenerator(configuration: configuration, transport: URLSessionTransport())
        let background = BackgroundActivity(name: "ImageGeneration")

        turnTask = Task {
            var succeeded = false
            do {
                let data = try await generator.generate(prompt: prompt)
                let name = try saveGeneratedImage(data)
                if let index = items.firstIndex(where: { $0.id == reply.id }) {
                    items[index].images = [name]
                }
                // Sohbet geçmişi tutarlı kalsın; sonraki mesajlar bir sohbet modeline giderse bağlamı bilsin.
                history.append(ChatMessage(role: .assistant, content: "[Generated an image: \(name)]"))
                succeeded = true
            } catch {
                if Task.isCancelled || error is CancellationError {
                    markStopped(reply.id)
                } else {
                    handleFailure(error)
                }
            }
            if let index = items.firstIndex(where: { $0.id == reply.id }),
               let activity = items[index].activities.indices.first {
                items[index].activities[activity].state = succeeded ? .done : .failed
            }
            isStreaming = false
            turnTask = nil
            persist()
            endTurn()
            background.end()
        }
    }

    func retry(using settings: AppSettings) {
        guard canRetry else { return }
        errorMessage = nil
        if settings.selection(for: modelOverrideID)?.model.generatesImages == true, let prompt = history.last(where: { $0.role == .user })?.content {
            generateImage(prompt: prompt, using: settings)
        } else {
            runTurn(using: settings)
        }
    }

    private func runTurn(using settings: AppSettings) {
        let configuration: LLMConfiguration
        do {
            configuration = try settings.configuration(modelID: modelOverrideID)
        } catch {
            errorMessage = userFacingMessage(for: error)
            return
        }
        guard let context, let selected = settings.selection(for: modelOverrideID) else { return }
        currentModel = (selected.provider.id, selected.model.name)
        let notes = SwiftDataNoteStore(context: context)
        let usesMemory = self.usesMemory
        let skills = skillLibrary?.active(in: selectedSkillIDs).map(\.skill) ?? []
        let project = projectID.flatMap { ProjectRecord.find($0, in: context)?.context }

        let reply = ChatItem(role: .assistant, text: "")
        items.append(reply)
        beginTurn(using: settings)
        pendingStepText = ""

        let providerID = selected.provider.id
        let tracker = usageTracker
        var transport = URLSessionTransport()
        transport.onDailyRemaining = { remaining in
            Task { @MainActor in tracker?.recordDailyRemaining(remaining, providerID: providerID) }
        }
        let client = LLMClient(configuration: configuration, transport: transport)
        var tools: [any Tool] = [
            WebSearchTool(backend: settings.searchBackend, transport: transport, fallback: settings.searchFallback) { used in
                Task { @MainActor in tracker?.recordSearch(with: SearchProvider(used)) }
            },
            FetchPageTool(transport: transport),
            WriteFileTool(directory: DocumentFile.directory),
            CalculatorTool(evaluate: javaScriptCalculator),
            CreateArtifactTool(directory: DocumentFile.directory),
        ]
        if usesMemory {
            tools += [SaveNoteTool(store: notes), ReadNotesTool(store: notes)] as [any Tool]
        }
        if !skills.isEmpty {
            tools.append(UseSkillTool(skills: skills))
        }
        let agent = AgentLoop(
            client: client,
            tools: tools,
            approve: { [weak self] request in
                await self?.requestApproval(request) ?? false
            }
        )
        let userInstructions = settings.userInstructions

        // Eski turların okunmuş sayfaları ve arama sonuçları kısaltılır; asıl bilgi cevaplarda zaten var.
        history = ContextCompactor.trimmingOldToolResults(history)
        // Bağlam penceresi biliniyorsa yarısı (en fazla 128K), bilinmiyorsa 48K token.
        let threshold = selected.model.contextLength.map { min(max($0 / 2, 16_000), 128_000) } ?? Self.compactionThreshold
        let needsCompaction = max(lastPromptTokens ?? 0, ContextCompactor.estimatedTokens(history)) > threshold

        // Kullanıcı uygulamadan çıkarsa iOS'un verdiği ek sürede istek tamamlansın.
        let background = BackgroundActivity(name: "AgentTurn")

        turnTask = Task {
            do {
                if needsCompaction {
                    try await compact(using: client, replyID: reply.id)
                }
                let systemPrompt = SystemPrompt.make(
                    notes: usesMemory ? try await notes.allNotes() : [],
                    summary: summary,
                    userInstructions: userInstructions,
                    memoryEnabled: usesMemory,
                    skills: skills,
                    project: project
                )
                let messages = [ChatMessage(role: .system, content: systemPrompt)] + history
                for try await event in agent.run(messages) {
                    apply(event, to: reply.id)
                }
                if Task.isCancelled {
                    markStopped(reply.id)
                }
            } catch {
                if Task.isCancelled || error is CancellationError {
                    markStopped(reply.id)
                } else {
                    handleFailure(error)
                }
            }
            if let index = items.firstIndex(where: { $0.id == reply.id }) {
                items[index].preparing = nil
                if items[index].text.isEmpty, items[index].activities.isEmpty, items[index].stopped != true {
                    items.remove(at: index)
                }
            }
            isStreaming = false
            turnTask = nil
            persist()
            endTurn()
            background.end()
        }
    }

    /// Eski mesajları özetleyip geçmişten çıkarır; son turlar olduğu gibi kalır.
    private func compact(using client: LLMClient, replyID: ChatItem.ID) async throws {
        let (older, recent) = ContextCompactor.split(history, keepingLastTurns: Self.keptTurns)
        guard !older.isEmpty, let index = items.firstIndex(where: { $0.id == replyID }) else { return }

        let activityID = "compact-\(UUID().uuidString)"
        items[index].activities.append(ToolActivity(id: activityID, toolName: "compact", title: L("Summarizing earlier messages", "Önceki mesajlar özetleniyor")))
        summary = try await ContextCompactor.summarize(older, previousSummary: summary, client: client)
        history = recent
        if let index = items.firstIndex(where: { $0.id == replyID }),
           let activity = items[index].activities.firstIndex(where: { $0.id == activityID }) {
            items[index].activities[activity].state = .done
        }
    }

    /// Durdurulan cevabın yarım kalan kısmını geçmişe tutarlı biçimde ekler.
    private func markStopped(_ replyID: ChatItem.ID) {
        history = history.closingUnansweredToolCalls()
        if !pendingStepText.isEmpty {
            history.append(ChatMessage(role: .assistant, content: pendingStepText))
            pendingStepText = ""
        }
        guard let index = items.firstIndex(where: { $0.id == replyID }) else { return }
        items[index].stopped = true
        for activity in items[index].activities.indices where items[index].activities[activity].state == .running {
            items[index].activities[activity].state = .failed
        }
    }

    private func apply(_ event: AgentEvent, to id: ChatItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        switch event {
        case let .text(delta):
            items[index].text += delta
            items[index].preparing = nil
            pendingStepText += delta
        case let .reasoning(thought):
            items[index].reasoning = (items[index].reasoning ?? "") + thought
        case let .preparingTool(name, characters):
            items[index].preparing = PreparingTool(toolName: name, characters: characters)
        case let .toolStarted(callID, name, detail):
            items[index].preparing = nil
            // Sonraki adımın düşüncesi öncekiyle birleşmesin.
            if let reasoning = items[index].reasoning, !reasoning.isEmpty, !reasoning.hasSuffix("\n\n") {
                items[index].reasoning = reasoning + "\n\n"
            }
            // Araçtan önce yazılmış metinle sonraki cevap birbirine yapışmasın.
            if !items[index].text.isEmpty, !items[index].text.hasSuffix("\n\n") {
                items[index].text += "\n\n"
            }
            items[index].activities.append(ToolActivity(id: callID, toolName: name, title: activityTitle(toolName: name, detail: detail)))
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
            if message.role == .assistant {
                pendingStepText = ""
            }
        case let .usage(usage):
            items[index].usage = items[index].usage.map { $0 + usage } ?? usage
            lastPromptTokens = usage.promptTokens
            if let currentModel {
                usageTracker?.record(usage, providerID: currentModel.providerID, model: currentModel.name)
            }
        }
    }

    /// Açık sohbeti kaydeder; ilk kayıtta yeni bir `ConversationRecord` oluşturur.
    private func persist() {
        guard let context, !items.isEmpty, !isIncognito else { return }
        let content = ConversationContent(
            items: items,
            history: history,
            summary: summary,
            lastPromptTokens: lastPromptTokens,
            memoryEnabled: memoryEnabled,
            skillIDs: selectedSkillIDs.map(Array.init),
            modelID: modelOverrideID
        )

        if let conversationID,
           let record = try? context.fetch(FetchDescriptor<ConversationRecord>(predicate: #Predicate { $0.id == conversationID })).first {
            record.update(content)
        } else {
            let record = ConversationRecord(content: content)
            record.projectID = projectID
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
