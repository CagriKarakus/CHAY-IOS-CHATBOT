import Foundation

public enum LLMError: Error, Equatable, Sendable {
    case invalidBaseURL
    case missingAPIKey
    case missingModel
    /// 2xx dışı HTTP yanıtı. `message` sunucunun hata metnidir, API key'den arındırılmıştır.
    case http(status: Int, message: String?)
    /// Akışın içinde gelen hata (`data: {"error": ...}`).
    case server(message: String)
    case invalidResponse
}

extension LLMError {
    /// Yoğunluk veya sunucu sorunu: başka bir modelle çalışabilir. Ayar hataları (key, model adı) buna girmez.
    public var isTemporary: Bool {
        switch self {
        case let .http(status, _): status == 408 || status == 429 || (500..<600).contains(status)
        case .server: true
        default: false
        }
    }
}

extension LLMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Invalid base URL. Enter the full address starting with https:// (e.g. https://router.example.com/v1)."
        case .missingAPIKey:
            return "No API key entered."
        case .missingModel:
            return "No model name entered."
        case .http(401, _), .http(403, _):
            return "The API key is invalid or has no access to this model. Check your settings."
        case .http(404, _):
            return "Endpoint or model not found. Check the base URL and model name."
        case .http(429, _):
            return "Rate limit reached. Wait a moment and try again."
        case let .http(status, message):
            return "Server error (\(status))" + (message.map { ": \($0)" } ?? ".")
        case let .server(message):
            return "Server error: \(message)"
        case .invalidResponse:
            return "The server sent an unexpected response."
        }
    }
}
