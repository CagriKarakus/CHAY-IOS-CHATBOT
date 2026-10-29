import Foundation

/// OpenAI-uyumlu `/chat/completions` isteğindeki tek bir mesaj.
public struct ChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant, tool
    }

    public var role: Role
    public var content: String?
    /// Asistanın istediği araç çağrıları.
    public var toolCalls: [ToolCall]?
    /// `tool` mesajının cevap verdiği çağrı.
    public var toolCallID: String?
    /// Kullanıcı mesajına eklenen görsel/ses (istekte `content` parçalarına dönüşür).
    public var attachments: [Attachment]?

    public init(role: Role, content: String?, toolCalls: [ToolCall]? = nil, toolCallID: String? = nil, attachments: [Attachment]? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
        self.attachments = attachments
    }

    enum CodingKeys: String, CodingKey {
        case role, content, attachments
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }
}

/// Mesaja eklenen görsel, ses kaydı veya doküman (PDF/metin dosyasından çıkarılmış metin).
public struct Attachment: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case image, audio, document
    }

    public var kind: Kind
    /// Örn. "image/jpeg", "audio/wav", "text/plain".
    public var mimeType: String
    /// Dokümanlarda UTF-8 metin.
    public var data: Data
    /// Dokümanın dosya adı.
    public var name: String?

    public init(kind: Kind, mimeType: String, data: Data, name: String? = nil) {
        self.kind = kind
        self.mimeType = mimeType
        self.data = data
        self.name = name
    }

    /// Dokümanın modele giden metni.
    var documentText: String {
        """
        <document name="\(name ?? "document")">
        \(String(decoding: data, as: UTF8.self))
        </document>
        """
    }

    /// `input_audio.format` değeri; OpenAI "wav" ve "mp3" kabul eder.
    var audioFormat: String {
        mimeType.contains("mpeg") || mimeType.contains("mp3") ? "mp3" : "wav"
    }
}

public struct ToolCall: Codable, Equatable, Sendable {
    public struct Function: Codable, Equatable, Sendable {
        public var name: String
        /// Model tarafından üretilen JSON metni.
        public var arguments: String
    }

    public var id: String
    public var type = "function"
    public var function: Function

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.function = Function(name: name, arguments: arguments)
    }
}
