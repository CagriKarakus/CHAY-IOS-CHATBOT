import AgentCore
import Foundation

/// Uygulama dili. Ayarlar'dan seçilir ve uygulama yeniden açılınca uygulanır.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, english, turkish

    var id: String { rawValue }

    private static let storageKey = "app.language"

    static var stored: AppLanguage {
        UserDefaults.standard.string(forKey: storageKey).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Seçimi kaydeder. `AppleLanguages` da ayarlanır ki iOS'un kendi metinleri ve tarih/sayı biçimleri de aynı dilde olsun.
    static func store(_ language: AppLanguage) {
        let defaults = UserDefaults.standard
        defaults.set(language.rawValue, forKey: storageKey)
        switch language {
        case .system: defaults.removeObject(forKey: "AppleLanguages")
        case .english: defaults.set(["en"], forKey: "AppleLanguages")
        case .turkish: defaults.set(["tr"], forKey: "AppleLanguages")
        }
    }

    /// Bu oturumda kullanılan dil; açılışta bir kez belirlenir.
    static let current: Resolved = {
        switch stored {
        case .english: .english
        case .turkish: .turkish
        case .system: Locale.preferredLanguages.first?.hasPrefix("tr") == true ? .turkish : .english
        }
    }()

    enum Resolved {
        case english, turkish
    }

    /// Seçicide her dil kendi adıyla görünür.
    var title: String {
        switch self {
        case .system: L("System", "Sistem")
        case .english: "English"
        case .turkish: "Türkçe"
        }
    }
}

/// İngilizce ve Türkçe karşılığı verilen metinden geçerli dildekini seçer.
func L(_ english: String, _ turkish: String) -> String {
    AppLanguage.current == .turkish ? turkish : english
}

/// Araç adımının arayüzdeki başlığı: "Aranıyor: istanbul hava durumu".
func activityTitle(toolName: String, detail: String?) -> String {
    let verb = switch toolName {
    case "web_search": L("Searching", "Aranıyor")
    case "fetch_page": L("Reading", "Okunuyor")
    case "write_file": L("Writing file", "Dosya yazılıyor")
    case "save_note": L("Saving to memory", "Hafızaya kaydediliyor")
    case "read_notes": L("Reading notes", "Notlar okunuyor")
    case "use_skill": L("Using skill", "Skill kullanılıyor")
    case "calculate": L("Calculating", "Hesaplanıyor")
    case "create_artifact": L("Creating page", "Sayfa oluşturuluyor")
    case "find_connector": L("Finding connector", "Bağlayıcı aranıyor")
    case "connect_connector": L("Connecting", "Bağlanıyor")
    case let name where name.hasPrefix("mcp_"): L("Using", "Kullanılıyor")
    default: toolName
    }
    guard let detail, !detail.isEmpty else { return verb }
    return "\(verb): \(detail)"
}

/// AgentCore hatalarının kullanıcıya gösterilen, seçili dildeki açıklaması.
func localizedDescription(of error: LLMError) -> String {
    switch error {
    case .invalidBaseURL:
        L("Invalid base URL. Enter the full address starting with https:// (e.g. https://router.example.com/v1).",
          "Base URL geçersiz. https:// ile başlayan tam adresi gir (örn. https://router.example.com/v1).")
    case .missingAPIKey:
        L("No API key entered.", "API key girilmemiş.")
    case .missingModel:
        L("No model selected. Add a model in Settings.", "Model seçilmemiş. Ayarlar'dan bir model ekle.")
    case let .http(403, message?):
        // Ör. Evren'de kullanım şartları onaylanmamışsa sunucunun açıklaması gösterilir.
        L("Access denied: \(message)", "Erişim reddedildi: \(message)")
    case .http(503, _):
        L("The model is busy right now. Try again in a moment.", "Model şu an dolu. Biraz sonra tekrar dene.")
    case .http(401, _), .http(403, _):
        L("The API key is invalid or has no access to this model. Check your settings.",
          "API key geçersiz veya bu modele erişim yetkin yok. Ayarları kontrol et.")
    case .http(404, _):
        L("Endpoint or model not found. Check the base URL and model name.",
          "Endpoint veya model bulunamadı. Base URL'i ve model adını kontrol et.")
    case .http(429, _):
        L("Rate limit reached. Wait a moment and try again.", "İstek sınırı aşıldı. Biraz bekleyip tekrar dene.")
    case let .http(status, message):
        L("Server error (\(status))", "Sunucu hatası (\(status))") + (message.map { ": \($0)" } ?? ".")
    case let .server(message):
        L("Server error: \(message)", "Sunucu hatası: \(message)")
    case .invalidResponse:
        L("The server sent an unexpected response.", "Sunucudan beklenmeyen bir yanıt geldi.")
    }
}

func localizedDescription(of error: SkillRepository.RepositoryError) -> String {
    switch error {
    case .invalidName:
        L("Enter the repository as owner/repo or a github.com link.", "Repoyu owner/repo ya da github.com linki olarak yaz.")
    case .notFound:
        L("Repository not found (it must be public).", "Repo bulunamadı (herkese açık olmalı).")
    case .rateLimited:
        L("GitHub's hourly limit was reached. Try again later.", "GitHub'ın saatlik sınırına ulaşıldı. Daha sonra tekrar dene.")
    case let .http(status):
        L("GitHub error (\(status)).", "GitHub hatası (\(status)).")
    }
}
