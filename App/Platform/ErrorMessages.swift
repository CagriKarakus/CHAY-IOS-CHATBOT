import Foundation

/// Ağ hatalarını kullanıcının anlayacağı Türkçe mesaja çevirir; diğer hatalar kendi açıklamasını kullanır.
func userFacingMessage(for error: any Error) -> String {
    guard let urlError = error as? URLError else {
        return error.localizedDescription
    }
    switch urlError.code {
    case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
        return "İnternet bağlantısı yok. Bağlantını kontrol edip tekrar dene."
    case .timedOut:
        return "Sunucu zamanında cevap vermedi. Biraz sonra tekrar dene."
    case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
        return "Sunucuya ulaşılamadı. Ayarlardaki base URL'i kontrol et."
    case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
         .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot:
        return "Sunucuyla güvenli bağlantı kurulamadı."
    default:
        return "Bağlantı hatası: \(urlError.localizedDescription)"
    }
}
