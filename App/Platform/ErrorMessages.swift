import Foundation

import AgentCore

/// Hataları seçili dilde, kullanıcının anlayacağı mesaja çevirir.
func userFacingMessage(for error: any Error) -> String {
    if let llmError = error as? LLMError {
        return localizedDescription(of: llmError)
    }
    guard let urlError = error as? URLError else {
        return error.localizedDescription
    }
    switch urlError.code {
    case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
        return L("No internet connection. Check your connection and try again.", "İnternet bağlantısı yok. Bağlantını kontrol edip tekrar dene.")
    case .timedOut:
        return L("The server didn't respond in time. Try again in a moment.", "Sunucu zamanında cevap vermedi. Biraz sonra tekrar dene.")
    case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
        return L("Couldn't reach the server. Check the base URL in Settings.", "Sunucuya ulaşılamadı. Ayarlardaki base URL'i kontrol et.")
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
         .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
        return L("Couldn't establish a secure connection to the server.", "Sunucuyla güvenli bağlantı kurulamadı.")
    default:
        return L("Connection error: \(urlError.localizedDescription)", "Bağlantı hatası: \(urlError.localizedDescription)")
    }
}
