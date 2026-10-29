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

    public init(role: Role, content: String?, toolCalls: [ToolCall]? = nil, toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
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
