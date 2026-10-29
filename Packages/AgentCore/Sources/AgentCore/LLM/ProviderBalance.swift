import Foundation

/// Sağlayıcı hesabındaki kullanım ve kalan bakiye. Sadece bunu normal API key ile sunan sağlayıcılarda vardır.
public struct ProviderBalance: Equatable, Sendable {
    public var used: Double?
    /// Toplam kredi veya bütçe.
    public var limit: Double?
    public var remaining: Double?
    public var currency: String?

    public init(used: Double? = nil, limit: Double? = nil, remaining: Double? = nil, currency: String? = nil) {
        self.used = used
        self.limit = limit
        self.remaining = remaining
        self.currency = currency
    }

    /// Bakiye sorgusunu destekleyen hazır ayarlar.
    public static let supportedPresets: Set<String> = ["openrouter", "deepseek", "litellm"]

    /// - Parameter preset: sağlayıcının hazır ayarı (`ProviderPreset.id`); desteklenmiyorsa `nil` döner.
    public static func fetch(preset: String?, baseURL: String, apiKey: String, transport: any HTTPTransport) async throws -> ProviderBalance? {
        let headers = ["Authorization": "Bearer \(apiKey.trimmingCharacters(in: .whitespacesAndNewlines))"]
        switch preset {
        case "openrouter":
            if let credits: OpenRouterCredits = try? await get("https://openrouter.ai/api/v1/credits", headers, transport) {
                let total = credits.data.total_credits, used = credits.data.total_usage
                return ProviderBalance(used: used, limit: total, remaining: total - used, currency: "USD")
            }
            // Kredi uç noktası açık değilse key'in kendi limiti.
            let key: OpenRouterKey = try await get("https://openrouter.ai/api/v1/key", headers, transport)
            return ProviderBalance(used: key.data.usage, limit: key.data.limit, remaining: key.data.limit_remaining, currency: "USD")

        case "deepseek":
            let balance: DeepSeekBalance = try await get("https://api.deepseek.com/user/balance", headers, transport)
            guard let info = balance.balance_infos.first(where: { $0.currency == "USD" }) ?? balance.balance_infos.first else { return nil }
            return ProviderBalance(remaining: Double(info.total_balance), currency: info.currency)

        case "litellm":
            // LiteLLM proxy: /key/info sunucunun kökünde, /v1'in dışında.
            let root = try LLMConfiguration.validatedBaseURL(baseURL).absoluteString
                .replacingOccurrences(of: #"/v1/?$"#, with: "", options: .regularExpression)
            let info: LiteLLMKeyInfo = try await get(root + "/key/info", headers, transport)
            let used = info.info.spend
            let limit = info.info.max_budget
            return ProviderBalance(used: used, limit: limit, remaining: limit.map { $0 - (used ?? 0) }, currency: "USD")

        default:
            return nil
        }
    }

    private static func get<T: Decodable>(_ link: String, _ headers: [String: String], _ transport: any HTTPTransport) async throws -> T {
        guard let url = URL(string: link) else { throw LLMError.invalidBaseURL }
        let response = try await transport.send(HTTPRequest(url: url, method: "GET", headers: headers, body: nil))
        guard (200..<300).contains(response.statusCode) else { throw LLMError.http(status: response.statusCode, message: nil) }
        do {
            return try JSONDecoder().decode(T.self, from: response.body)
        } catch {
            throw LLMError.invalidResponse
        }
    }

    private struct OpenRouterCredits: Decodable {
        struct Data: Decodable {
            let total_credits: Double
            let total_usage: Double
        }
        let data: Data
    }

    private struct OpenRouterKey: Decodable {
        struct Data: Decodable {
            let usage: Double?
            let limit: Double?
            let limit_remaining: Double?
        }
        let data: Data
    }

    private struct DeepSeekBalance: Decodable {
        struct Info: Decodable {
            let currency: String
            let total_balance: String
        }
        let balance_infos: [Info]
    }

    private struct LiteLLMKeyInfo: Decodable {
        struct Info: Decodable {
            let spend: Double?
            let max_budget: Double?
        }
        let info: Info
    }
}
