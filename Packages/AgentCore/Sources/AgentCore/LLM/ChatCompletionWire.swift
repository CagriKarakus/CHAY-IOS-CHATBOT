// `/chat/completions` istek ve yanıtlarının JSON biçimleri.

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let tools: [ToolDefinition]?
}

/// İstekteki `tools` dizisinin bir elemanı.
public struct ToolDefinition: Encodable, Equatable, Sendable {
    public struct Function: Encodable, Equatable, Sendable {
        public let name: String
        public let description: String
        public let parameters: JSONValue
    }

    public let type = "function"
    public let function: Function

    public init(name: String, description: String, parameters: JSONValue) {
        function = Function(name: name, description: description, parameters: parameters)
    }

    enum CodingKeys: CodingKey {
        case type, function
    }
}

struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let toolCalls: [ToolCallDelta]?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
        let delta: Delta?
    }
    let choices: [Choice]
}

/// Streaming'de parça parça gelen araç çağrısı; `index` ile birleştirilir.
struct ToolCallDelta: Decodable {
    struct Function: Decodable {
        let name: String?
        let arguments: String?
    }
    let index: Int?
    let id: String?
    let function: Function?
}

struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        let message: String?
    }
    let error: Detail
}
