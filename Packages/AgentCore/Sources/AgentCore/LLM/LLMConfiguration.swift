import Foundation

/// OpenAI-uyumlu bir endpoint'e bağlanmak için gereken ayarlar.
public struct LLMConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let apiKey: String
    public let model: String

    /// Değerleri temizler ve doğrular. Sadece HTTPS kabul edilir.
    public init(baseURL: String, apiKey: String, model: String) throws {
        let trimmedURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmedURL),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { throw LLMError.invalidBaseURL }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LLMError.missingAPIKey }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw LLMError.missingModel }

        self.baseURL = url
        self.apiKey = trimmedKey
        self.model = trimmedModel
    }
}
