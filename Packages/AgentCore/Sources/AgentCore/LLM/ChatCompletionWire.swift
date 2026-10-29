// `/chat/completions` istek ve yanıtlarının JSON biçimleri.

struct ChatCompletionRequest: Encodable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
}

struct ChatCompletionChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta?
    }
    let choices: [Choice]
}

struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        let message: String?
    }
    let error: Detail
}
