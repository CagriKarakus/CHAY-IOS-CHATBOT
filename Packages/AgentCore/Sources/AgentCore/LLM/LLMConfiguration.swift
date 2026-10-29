import Foundation

/// Akıl yürütme (reasoning) destekleyen modellerde düşünme eforu; istekte `reasoning_effort` olarak gönderilir.
public enum ReasoningEffort: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

/// OpenAI-uyumlu bir endpoint'e bağlanmak için gereken ayarlar.
public struct LLMConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let apiKey: String
    public let model: String
    /// `nil` ise istekte gönderilmez (modelin varsayılanı).
    public let reasoningEffort: ReasoningEffort?

    /// Değerleri temizler ve doğrular. Sadece HTTPS kabul edilir.
    public init(baseURL: String, apiKey: String, model: String, reasoningEffort: ReasoningEffort? = nil) throws {
        let url = try Self.validatedBaseURL(baseURL)

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LLMError.missingAPIKey }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw LLMError.missingModel }

        self.baseURL = url
        self.apiKey = trimmedKey
        self.model = trimmedModel
        self.reasoningEffort = reasoningEffort
    }

    /// Base URL'i temizler; https ve host yoksa `LLMError.invalidBaseURL`.
    public static func validatedBaseURL(_ baseURL: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { throw LLMError.invalidBaseURL }
        return url
    }
}
