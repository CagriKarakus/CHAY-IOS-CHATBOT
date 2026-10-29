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

extension LLMError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            return "Base URL geçersiz. https:// ile başlayan tam adresi gir (örn. https://router.example.com/v1)."
        case .missingAPIKey:
            return "API key girilmemiş."
        case .missingModel:
            return "Model adı girilmemiş."
        case .http(401, _), .http(403, _):
            return "API key geçersiz veya bu modele erişim yetkin yok. Ayarları kontrol et."
        case .http(404, _):
            return "Endpoint veya model bulunamadı. Base URL'i ve model adını kontrol et."
        case .http(429, _):
            return "İstek sınırı aşıldı. Biraz bekleyip tekrar dene."
        case let .http(status, message):
            return "Sunucu hatası (\(status))" + (message.map { ": \($0)" } ?? ".")
        case let .server(message):
            return "Sunucu hatası: \(message)"
        case .invalidResponse:
            return "Sunucudan beklenmeyen bir yanıt geldi."
        }
    }
}
