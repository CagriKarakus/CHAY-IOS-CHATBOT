/// OpenAI-uyumlu `/chat/completions` isteğindeki tek bir mesaj.
public struct ChatMessage: Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant, tool
    }

    public var role: Role
    public var content: String?

    public init(role: Role, content: String?) {
        self.role = role
        self.content = content
    }
}
