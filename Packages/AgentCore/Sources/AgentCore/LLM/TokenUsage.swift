/// Bir veya birkaç model çağrısının token kullanımı.
public struct TokenUsage: Equatable, Codable, Sendable {
    public var promptTokens: Int
    public var completionTokens: Int
    /// İlk ve son akış parçası arasındaki süre (saniye); token/saniye hesabı için.
    public var generationSeconds: Double?
    /// Sağlayıcının kendi yaptığı web araması sayısı.
    public var webSearchRequests: Int?

    public init(promptTokens: Int, completionTokens: Int, generationSeconds: Double? = nil, webSearchRequests: Int? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.generationSeconds = generationSeconds
        self.webSearchRequests = webSearchRequests
    }

    public var totalTokens: Int {
        promptTokens + completionTokens
    }

    /// Çıktı hızı; süre ölçülemediyse veya çok kısaysa `nil`.
    public var tokensPerSecond: Double? {
        guard let generationSeconds, generationSeconds > 0.05, completionTokens > 0 else { return nil }
        return Double(completionTokens) / generationSeconds
    }

    /// Bir istekteki adımların toplamı.
    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        let seconds: Double? = switch (lhs.generationSeconds, rhs.generationSeconds) {
        case let (left?, right?): left + right
        case let (left?, nil): left
        case let (nil, right?): right
        case (nil, nil): nil
        }
        let searches = lhs.webSearchRequests.map { $0 + (rhs.webSearchRequests ?? 0) } ?? rhs.webSearchRequests
        return TokenUsage(
            promptTokens: lhs.promptTokens + rhs.promptTokens,
            completionTokens: lhs.completionTokens + rhs.completionTokens,
            generationSeconds: seconds,
            webSearchRequests: searches
        )
    }
}

extension Duration {
    var seconds: Double {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
