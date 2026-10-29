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
    /// Aramada kullanılan, mesajların küçük harfli düz metni. Bu alan eklenmeden önce kaydedilen sohbetlerde boştur.
    var searchText: String = ""
    /// Sohbetin ait olduğu proje (`ProjectRecord.id`); projesiz sohbetlerde `nil`.
    var projectID: UUID?

    init(content: ConversationContent) {
        id = UUID()
        createdAt = .now
        updatedAt = .now
        title = Self.title(for: content)
        contentData = (try? JSONEncoder().encode(content)) ?? Data()
        searchText = Self.searchText(for: content)
    }

    /// Yedekten geri yükleme için.
    init(id: UUID, title: String, createdAt: Date, updatedAt: Date, content: ConversationContent, projectID: UUID? = nil) {
        self.id = id
        self.projectID = projectID
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        contentData = (try? JSONEncoder().encode(content)) ?? Data()
        searchText = Self.searchText(for: content)
    }

    var content: ConversationContent {
        (try? JSONDecoder().decode(ConversationContent.self, from: contentData)) ?? ConversationContent(items: [], history: [])
    }

    func update(_ content: ConversationContent) {
        contentData = (try? JSONEncoder().encode(content)) ?? contentData
        // İlk mesaj düzenlendiyse başlık da güncellensin.
        title = Self.title(for: content)
        searchText = Self.searchText(for: content)
        updatedAt = .now
    }

    /// Başlıkta veya mesajlarda geçiyor mu.
    func matches(_ query: String) -> Bool {
        let text = searchText.isEmpty ? Self.searchText(for: content) : searchText
        return title.localizedCaseInsensitiveContains(query) || text.localizedCaseInsensitiveContains(query)
    }

    /// İlk kullanıcı mesajının başı.
    static func title(for content: ConversationContent) -> String {
        let text = content.items.first { $0.role == .user }?.text ?? ""
        let first = text.isEmpty ? L("New chat", "Yeni sohbet") : text
        let line = first.components(separatedBy: .newlines).first ?? first
        return line.count > 60 ? String(line.prefix(60)) + "…" : line
    }

    private static func searchText(for content: ConversationContent) -> String {
        content.items.map(\.text).joined(separator: "\n").lowercased()
    }
}
