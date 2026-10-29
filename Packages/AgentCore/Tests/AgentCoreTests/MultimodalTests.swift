import Foundation
import Testing
@testable import AgentCore

// MARK: - Model yetenekleri

/// Evren dokümanındaki örnek yanıt.
private let evrenModels = """
{"object":"list","data":[
 {"id":"glm-5.3","object":"model","created":1757900000,"owned_by":"evren","task":"chat","modalities":["text"],
  "pricing":{"prompt_token_price":0.0,"completion_token_price":0.0,"currency":"CR","free_until":"2026-12-01"}},
 {"id":"deepseek-v4.1-flash","object":"model","created":1757900000,"owned_by":"evren","task":"chat","modalities":["text","image"],
  "pricing":{"prompt_token_price":0.0,"completion_token_price":0.0,"currency":"CR","free_until":"2026-12-01"}}
]}
"""

@Test func readsEvrenModalities() async throws {
    let models = try await LLMClient.listModels(baseURL: "https://evren.example/v1", apiKey: "k", transport: SendRecorder(json: evrenModels))

    let flash = try #require(models.first { $0.id == "deepseek-v4.1-flash" })
    let glm = try #require(models.first { $0.id == "glm-5.3" })
    #expect(flash.acceptsImages == true)
    #expect(flash.acceptsAudio == false)
    #expect(glm.acceptsImages == false)
    #expect(glm.generatesImages == false)
}

@Test func readsOpenRouterArchitecture() async throws {
    let json = #"{"data":[{"id":"google/gemini","architecture":{"input_modalities":["text","image","audio"],"output_modalities":["text","image"]}}]}"#

    let model = try #require(try await LLMClient.listModels(baseURL: "https://a.com/v1", apiKey: "k", transport: SendRecorder(json: json)).first)

    #expect(model.acceptsImages == true)
    #expect(model.acceptsAudio == true)
    #expect(model.generatesImages == true)
}

@Test(arguments: [("image_generation", true), ("text-to-image", true), ("chat", false), ("image-to-text", false)])
func imageGenerationFromTask(_ task: String, _ expected: Bool) {
    #expect(ModelInfo(id: "m", task: task).generatesImages == expected)
}

// MARK: - Ekli mesajlar

@Test func encodesAttachmentsAsContentParts() throws {
    let image = Attachment(kind: .image, mimeType: "image/jpeg", data: Data([1, 2, 3]))
    let audio = Attachment(kind: .audio, mimeType: "audio/wav", data: Data([4, 5]))
    let message = ChatMessage(role: .user, content: "Bu ne?", attachments: [image, audio])

    let body = try #require(try LLMClient(configuration: try makeConfiguration(), transport: MockTransport()).makeRequest([message]).body)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    let sent = try #require((json["messages"] as? [[String: Any]])?.first)
    let parts = try #require(sent["content"] as? [[String: Any]])

    #expect(parts.count == 3)
    #expect(parts[0]["type"] as? String == "text")
    #expect(parts[0]["text"] as? String == "Bu ne?")
    #expect(parts[1]["type"] as? String == "image_url")
    #expect((parts[1]["image_url"] as? [String: Any])?["url"] as? String == "data:image/jpeg;base64,AQID")
    #expect(parts[2]["type"] as? String == "input_audio")
    #expect((parts[2]["input_audio"] as? [String: Any])?["format"] as? String == "wav")
    #expect(sent["attachments"] == nil)
}

@Test func plainMessagesKeepStringContent() throws {
    let body = try #require(try LLMClient(configuration: try makeConfiguration(), transport: MockTransport())
        .makeRequest([ChatMessage(role: .user, content: "Selam")]).body)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])

    #expect((json["messages"] as? [[String: Any]])?.first?["content"] as? String == "Selam")
}

@Test func attachmentsSurvivePersistence() throws {
    let message = ChatMessage(role: .user, content: "x", attachments: [Attachment(kind: .image, mimeType: "image/png", data: Data([9]))])

    let decoded = try JSONDecoder().decode(ChatMessage.self, from: try JSONEncoder().encode(message))

    #expect(decoded == message)
}

@Test func attachmentsCountTowardsContext() {
    let message = ChatMessage(role: .user, content: "", attachments: [Attachment(kind: .image, mimeType: "image/jpeg", data: Data())])

    #expect(ContextCompactor.estimatedTokens([message]) == 1_000)
}

// MARK: - Görsel üretme

/// Sırayla verilen yanıtları dönen `send` transport'u.
private final class QueuedSend: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [HTTPResponse]
    private(set) var requests: [HTTPRequest] = []

    init(_ responses: [HTTPResponse]) {
        self.responses = responses
    }

    func lines(for request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        lock.withLock {
            requests.append(request)
            return responses.removeFirst()
        }
    }
}

private func json(_ text: String, status: Int = 200) -> HTTPResponse {
    HTTPResponse(statusCode: status, contentType: "application/json", body: Data(text.utf8))
}

@Test func generatesImageFromBase64() async throws {
    let transport = QueuedSend([json(#"{"data":[{"b64_json":"AQID"}]}"#)])

    let data = try await ImageGenerator(configuration: try makeConfiguration(), transport: transport).generate(prompt: "kedi")

    #expect(data == Data([1, 2, 3]))
    let request = try #require(transport.requests.first)
    #expect(request.url.absoluteString == "https://router.example.com/v1/images/generations")
    let requestBody = try #require(request.body)
    let body = try #require(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
    #expect(body["model"] as? String == "test-model")
    #expect(body["prompt"] as? String == "kedi")
}

@Test func downloadsImageFromURL() async throws {
    let transport = QueuedSend([
        json(#"{"data":[{"url":"https://cdn.example.com/a.png"}]}"#),
        HTTPResponse(statusCode: 200, contentType: "image/png", body: Data([7, 8])),
    ])

    let data = try await ImageGenerator(configuration: try makeConfiguration(), transport: transport).generate(prompt: "kedi")

    #expect(data == Data([7, 8]))
    #expect(transport.requests.last?.url.absoluteString == "https://cdn.example.com/a.png")
}

@Test func imageGenerationErrorsAreRedacted() async throws {
    let transport = QueuedSend([json(#"{"error":{"message":"bad key sk-test-123"}}"#, status: 400)])

    await #expect(throws: LLMError.http(status: 400, message: "bad key ***")) {
        try await ImageGenerator(configuration: try makeConfiguration(), transport: transport).generate(prompt: "x")
    }
}
