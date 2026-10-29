// `/chat/completions` istek ve yanıtlarının JSON biçimleri.

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [WireMessage]
    let stream: Bool
    let tools: [ToolDefinition]?
    let reasoningEffort: ReasoningEffort?
    /// Streaming'de son parçada token kullanımını ister.
    let streamOptions = StreamOptions()

    struct StreamOptions: Encodable {
        let include_usage = true
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, tools
        case reasoningEffort = "reasoning_effort"
        case streamOptions = "stream_options"
    }
}

/// Mesajın API'ye giden biçimi: ek varsa `content` metin + görsel/ses parçalarından oluşan bir dizi olur.
struct WireMessage: Encodable {
    let message: ChatMessage

    private struct TextPart: Encodable {
        let type = "text"
        let text: String
    }

    private struct ImagePart: Encodable {
        struct ImageURL: Encodable { let url: String }
        let type = "image_url"
        let image_url: ImageURL
    }

    private struct AudioPart: Encodable {
        struct InputAudio: Encodable {
            let data: String
            let format: String
        }
        let type = "input_audio"
        let input_audio: InputAudio
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: ChatMessage.CodingKeys.self)
        try container.encode(message.role, forKey: .role)

        let attachments = message.attachments ?? []
        let documents = attachments.filter { $0.kind == .document }
        let media = attachments.filter { $0.kind != .document }
        // Dokümanlar düz metin olarak eklenir; böylece sadece metin kabul eden modellerde de çalışır.
        let text = ([message.content].compactMap { $0 }.filter { !$0.isEmpty } + documents.map(\.documentText))
            .joined(separator: "\n\n")

        if !media.isEmpty {
            var parts = container.nestedUnkeyedContainer(forKey: .content)
            if !text.isEmpty {
                try parts.encode(TextPart(text: text))
            }
            for attachment in media {
                let base64 = attachment.data.base64EncodedString()
                switch attachment.kind {
                case .image:
                    try parts.encode(ImagePart(image_url: .init(url: "data:\(attachment.mimeType);base64,\(base64)")))
                case .audio:
                    try parts.encode(AudioPart(input_audio: .init(data: base64, format: attachment.audioFormat)))
                case .document:
                    break
                }
            }
        } else if !documents.isEmpty {
            try container.encode(text, forKey: .content)
        } else {
            try container.encodeIfPresent(message.content, forKey: .content)
        }

        try container.encodeIfPresent(message.toolCalls, forKey: .toolCalls)
        try container.encodeIfPresent(message.toolCallID, forKey: .toolCallID)
    }
}

/// `GET /models` yanıtı. Standart alanların yanında bilinen yetenek uzantıları da okunur:
/// Evren `modalities` (giriş) ve `task`, OpenRouter `architecture.input_modalities` / `output_modalities`.
struct ModelList: Decodable {
    struct Model: Decodable {
        struct Architecture: Decodable {
            let input_modalities: [String]?
            let output_modalities: [String]?
        }
        let id: String
        let modalities: [String]?
        let task: String?
        let architecture: Architecture?
    }
    let data: [Model]
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
            let reasoning: String?
            let reasoningContent: String?
            let toolCalls: [ToolCallDelta]?

            enum CodingKeys: String, CodingKey {
                case content, reasoning
                case reasoningContent = "reasoning_content"
                case toolCalls = "tool_calls"
            }
        }
        let delta: Delta?
    }
    struct Usage: Decodable {
        let prompt_tokens: Int?
        let completion_tokens: Int?
    }
    let choices: [Choice]
    let usage: Usage?
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
