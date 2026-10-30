import Foundation

/// Akıl yürütme (reasoning) destekleyen modellerde düşünme eforu; istekte `reasoning_effort` olarak gönderilir.
public enum ReasoningEffort: String, Codable, CaseIterable, Sendable {
    case low, medium, high
}

/// Sağlayıcının kendi sunucusunda çalıştırdığı araçlar (ör. OpenRouter web araması).
public struct ServerTools: Equatable, Sendable {
    /// `tools` dizisine olduğu gibi eklenen tanımlar.
    public let tools: [JSONValue]
    /// Bunların yerine geçtiği için modele gönderilmeyen yerel araçlar.
    public let replaces: Set<String>
    /// Bir istekteki sunucu aracı çağrısı sınırı; aramalar ücretli olduğu için düşük tutulur.
    public let maxToolCalls: Int?

    public init(tools: [JSONValue], replaces: Set<String>, maxToolCalls: Int?) {
        self.tools = tools
        self.replaces = replaces
        self.maxToolCalls = maxToolCalls
    }

    public static let openRouterWebSearch = ServerTools(
        tools: [["type": "openrouter:web_search", "parameters": ["max_results": 5]]],
        replaces: ["web_search"],
        maxToolCalls: 5
    )
}

/// Bazı sunucuların reddettiği isteğe bağlı istek alanları.
public enum OptionalParameter: Sendable, CaseIterable {
    case streamOptions, reasoningEffort, maxToolCalls

    /// Hata mesajında geçince bu alanın reddedildiği anlaşılır.
    var errorKeyword: String {
        switch self {
        case .streamOptions: "stream_options"
        case .reasoningEffort: "reasoning"
        case .maxToolCalls: "max_tool_calls"
        }
    }
}

/// OpenAI-uyumlu bir endpoint'e bağlanmak için gereken ayarlar.
public struct LLMConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let apiKey: String
    public let model: String
    /// `nil` ise istekte gönderilmez (modelin varsayılanı).
    public let reasoningEffort: ReasoningEffort?
    /// Bazı gateway'lerin istediği ek HTTP başlıkları (ör. Portkey: `x-portkey-api-key`).
    public let extraHeaders: [String: String]
    /// Sağlayıcının yerleşik araçları; `nil` ise sadece yerel araçlar kullanılır.
    public var serverTools: ServerTools?
    /// Sunucu reddettiği için istekte gönderilmeyen alanlar.
    var omittedParameters: Set<OptionalParameter> = []

    /// Değerleri temizler ve doğrular. Sadece HTTPS kabul edilir.
    public init(
        baseURL: String,
        apiKey: String,
        model: String,
        reasoningEffort: ReasoningEffort? = nil,
        extraHeaders: [String: String] = [:]
    ) throws {
        let url = try Self.validatedBaseURL(baseURL)

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { throw LLMError.missingAPIKey }

        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else { throw LLMError.missingModel }

        self.baseURL = url
        self.apiKey = trimmedKey
        self.model = trimmedModel
        self.reasoningEffort = reasoningEffort
        self.extraHeaders = Self.cleaned(extraHeaders)
    }

    /// Boş adları/değerleri atar; Authorization ve Content-Type gibi temel başlıklar ezilemez.
    static func cleaned(_ headers: [String: String]) -> [String: String] {
        let reserved: Set<String> = ["authorization", "content-type", "accept"]
        var result: [String: String] = [:]
        for (name, value) in headers {
            let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !value.isEmpty, !reserved.contains(name.lowercased()) else { continue }
            result[name] = value
        }
        return result
    }

    /// İstek başlıkları: verilen temel başlıklar + ek başlıklar.
    func headers(_ base: [String: String]) -> [String: String] {
        base.merging(extraHeaders) { current, _ in current }
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
