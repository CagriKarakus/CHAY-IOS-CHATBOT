import AgentCore
import Foundation
import SwiftData

/// Bir sohbetin içeriği: ekranda görünenler ve modele giden geçmiş.
struct ConversationContent: Codable {
    var items: [ChatItem]
    var history: [ChatMessage]
    /// Sıkıştırılmış eski mesajların özeti.
    var summary: String?
    /// Son model çağrısının giriş tokenı; sıkıştırma eşiği için.
    var lastPromptTokens: Int?
    /// Sohbete özel hafıza ayarı (`nil` = açık).
    var memoryEnabled: Bool?
    /// Sohbete özel skill seçimi (`nil` = varsayılanlar).
    var skillIDs: [UUID]?
}

/// Sohbetin SwiftData kaydı. İçerik tek bir JSON alanında tutulur; şema değişmeden mesaj yapısı gelişebilir.
@Model
final class ConversationRecord {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    @Attribute(.externalStorage) var contentData: Data

    init(content: ConversationContent) {
        id = UUID()
        createdAt = .now
        updatedAt = .now
        title = Self.title(for: content)
        contentData = (try? JSONEncoder().encode(content)) ?? Data()
    }

    var content: ConversationContent {
        (try? JSONDecoder().decode(ConversationContent.self, from: contentData)) ?? ConversationContent(items: [], history: [])
    }

    func update(_ content: ConversationContent) {
        contentData = (try? JSONEncoder().encode(content)) ?? contentData
        updatedAt = .now
    }

    /// İlk kullanıcı mesajının başı.
    private static func title(for content: ConversationContent) -> String {
        let text = content.items.first { $0.role == .user }?.text ?? ""
        let first = text.isEmpty ? L("New chat", "Yeni sohbet") : text
        let line = first.components(separatedBy: .newlines).first ?? first
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }
}
