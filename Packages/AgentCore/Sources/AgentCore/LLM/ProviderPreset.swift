import Foundation

/// Bilinen router ve sağlayıcılar için hazır bağlantı ayarı (hepsi OpenAI-uyumlu endpoint).
/// `{...}` içeren adresler hesaba veya sunucuya özeldir; kullanıcı yer tutucuyu doldurur.
public struct ProviderPreset: Identifiable, Equatable, Sendable {
    public enum Category: String, Sendable {
        /// Birçok modele tek key ile erişim sağlayan servisler.
        case router
        /// Modelleri doğrudan sunan şirketler.
        case provider
        /// Kullanıcının kendi sunucusunda çalışan gateway'ler.
        case selfHosted
    }

    public let id: String
    public let name: String
    public let category: Category
    public let baseURL: String
    /// Kullanıcının değerini girmesi gereken ek HTTP başlıkları.
    public let headerNames: [String]

    public init(id: String, name: String, category: Category, baseURL: String, headerNames: [String] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.baseURL = baseURL
        self.headerNames = headerNames
    }

    /// Sağlayıcının `/chat/completions` üzerinden sunduğu yerleşik araçlar. Yeni sağlayıcılar buraya eklenir.
    public var serverTools: ServerTools? {
        id == "openrouter" ? .openRouterWebSearch : nil
    }

    /// Adreste doldurulması gereken yer tutucu var mı.
    public var needsEditing: Bool {
        baseURL.contains("{")
    }

    public static let all: [ProviderPreset] = [
        // Router'lar
        ProviderPreset(id: "evren", name: "EVREN LLM API", category: .router, baseURL: "https://evren-llmapi.ssyz.org.tr/v1"),
        ProviderPreset(id: "openrouter", name: "OpenRouter", category: .router, baseURL: "https://openrouter.ai/api/v1"),
        ProviderPreset(id: "vercel", name: "Vercel AI Gateway", category: .router, baseURL: "https://ai-gateway.vercel.sh/v1"),
        ProviderPreset(id: "portkey", name: "Portkey", category: .router, baseURL: "https://api.portkey.ai/v1",
                       headerNames: ["x-portkey-api-key", "x-portkey-provider"]),
        ProviderPreset(id: "cloudflare", name: "Cloudflare AI Gateway", category: .router,
                       baseURL: "https://gateway.ai.cloudflare.com/v1/{account_id}/{gateway_id}/compat"),
        ProviderPreset(id: "truefoundry", name: "TrueFoundry AI Gateway", category: .router,
                       baseURL: "https://{your-truefoundry-gateway}/api/llm"),

        // Sağlayıcılar
        ProviderPreset(id: "openai", name: "OpenAI", category: .provider, baseURL: "https://api.openai.com/v1"),
        ProviderPreset(id: "anthropic", name: "Anthropic", category: .provider, baseURL: "https://api.anthropic.com/v1"),
        ProviderPreset(id: "gemini", name: "Google Gemini", category: .provider, baseURL: "https://generativelanguage.googleapis.com/v1beta/openai"),
        ProviderPreset(id: "deepseek", name: "DeepSeek", category: .provider, baseURL: "https://api.deepseek.com/v1"),
        ProviderPreset(id: "mistral", name: "Mistral AI", category: .provider, baseURL: "https://api.mistral.ai/v1"),
        ProviderPreset(id: "meta", name: "Meta Llama API", category: .provider, baseURL: "https://api.llama.com/compat/v1"),
        ProviderPreset(id: "cohere", name: "Cohere", category: .provider, baseURL: "https://api.cohere.ai/compatibility/v1"),
        ProviderPreset(id: "groq", name: "Groq", category: .provider, baseURL: "https://api.groq.com/openai/v1"),
        ProviderPreset(id: "together", name: "Together AI", category: .provider, baseURL: "https://api.together.xyz/v1"),

        // Kendi sunucunda
        ProviderPreset(id: "litellm", name: "LiteLLM", category: .selfHosted, baseURL: "https://{your-litellm-host}/v1"),
        ProviderPreset(id: "routellm", name: "RouteLLM", category: .selfHosted, baseURL: "https://{your-routellm-host}/v1"),
        ProviderPreset(id: "bifrost", name: "Bifrost", category: .selfHosted, baseURL: "https://{your-bifrost-host}/v1"),
    ]

    public static func preset(id: String?) -> ProviderPreset? {
        all.first { $0.id == id }
    }

    /// Hazır ayar seçilmeden eklenmiş sağlayıcıyı adresinin host'undan tanır (yer tutuculu ayarlar hariç).
    public static func matching(baseURL: String) -> ProviderPreset? {
        guard let host = URL(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines))?.host?.lowercased() else { return nil }
        return all.first { !$0.needsEditing && URL(string: $0.baseURL)?.host?.lowercased() == host }
    }
}
