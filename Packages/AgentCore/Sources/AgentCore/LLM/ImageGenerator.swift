import Foundation

/// Görsel üreten modeller için OpenAI-uyumlu `POST /images/generations`.
public struct ImageGenerator: Sendable {
    private struct Request: Encodable {
        let model: String
        let prompt: String
        let n = 1
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            let b64_json: String?
            let url: String?
        }
        let data: [Item]
    }

    private let configuration: LLMConfiguration
    private let transport: any HTTPTransport

    public init(configuration: LLMConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    /// Üretilen görselin verisi. Sunucu base64 yerine URL dönerse görsel indirilir.
    public func generate(prompt: String) async throws -> Data {
        let response = try await transport.send(HTTPRequest(
            url: configuration.baseURL.appendingPathComponent("images/generations"),
            method: "POST",
            headers: [
                "Authorization": "Bearer \(configuration.apiKey)",
                "Content-Type": "application/json",
            ],
            body: try JSONEncoder().encode(Request(model: configuration.model, prompt: prompt))
        ))
        guard (200..<300).contains(response.statusCode) else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: response.body))?.error.message
            throw LLMError.http(status: response.statusCode, message: message?.replacingOccurrences(of: configuration.apiKey, with: "***"))
        }
        guard let item = (try? JSONDecoder().decode(Response.self, from: response.body))?.data.first else {
            throw LLMError.invalidResponse
        }
        if let base64 = item.b64_json, let data = Data(base64Encoded: base64) {
            return data
        }
        guard let link = item.url, let url = URL(string: link), url.scheme?.lowercased() == "https" else {
            throw LLMError.invalidResponse
        }
        let download = try await transport.send(HTTPRequest(url: url, method: "GET", headers: [:], body: nil))
        guard (200..<300).contains(download.statusCode), !download.body.isEmpty else {
            throw LLMError.http(status: download.statusCode, message: nil)
        }
        return download.body
    }
}
