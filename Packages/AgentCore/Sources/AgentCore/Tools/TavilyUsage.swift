import Foundation

/// Tavily hesabının kredi kullanımı (`GET https://api.tavily.com/usage`).
public struct TavilyUsage: Decodable, Equatable, Sendable {
    public struct Key: Decodable, Equatable, Sendable {
        public let usage: Int?
        /// `nil` ise anahtarın sınırı yok.
        public let limit: Int?
    }

    public struct Account: Decodable, Equatable, Sendable {
        public let currentPlan: String?
        public let planUsage: Int?
        public let planLimit: Int?
        public let paygoUsage: Int?
        public let paygoLimit: Int?

        enum CodingKeys: String, CodingKey {
            case currentPlan = "current_plan"
            case planUsage = "plan_usage"
            case planLimit = "plan_limit"
            case paygoUsage = "paygo_usage"
            case paygoLimit = "paygo_limit"
        }
    }

    public let key: Key?
    public let account: Account?

    public static func fetch(apiKey: String, transport: any HTTPTransport) async throws -> TavilyUsage {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw ToolError.missingAPIKey(service: "Tavily") }

        let response = try await transport.send(HTTPRequest(
            url: URL(string: "https://api.tavily.com/usage")!,
            method: "GET",
            headers: ["Authorization": "Bearer \(key)"],
            body: nil
        ))
        guard (200..<300).contains(response.statusCode) else { throw ToolError.http(status: response.statusCode) }
        return try JSONDecoder().decode(TavilyUsage.self, from: response.body)
    }
}
