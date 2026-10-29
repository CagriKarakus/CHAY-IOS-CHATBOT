import Foundation

/// Tavily ile web araması: başlık + URL + özet döndürür.
public struct WebSearchTool: Tool {
    private struct Arguments: Decodable {
        let query: String
    }

    private struct TavilyRequest: Encodable {
        let query: String
        let max_results: Int
        let search_depth = "basic"
    }

    private struct TavilyResponse: Decodable {
        struct Result: Decodable {
            let title: String
            let url: String
            let content: String?
        }
        let results: [Result]
    }

    public let name = "web_search"
    public let description = "Web'de arama yapar ve en alakalı sonuçların başlık, URL ve özetlerini döndürür. Güncel bilgi gerektiğinde kullan."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "Arama sorgusu"],
        ],
        "required": ["query"],
    ]

    private let apiKey: String
    private let transport: any HTTPTransport
    private let maxResults: Int
    private let endpoint = URL(string: "https://api.tavily.com/search")!

    public init(apiKey: String, transport: any HTTPTransport, maxResults: Int = 5) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
        self.maxResults = maxResults
    }

    public func activity(for arguments: String) -> String? {
        (try? decodeArguments(Arguments.self, from: arguments)).map { "Aranıyor: \($0.query)" }
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let query = try decodeArguments(Arguments.self, from: arguments).query
        guard !apiKey.isEmpty else { throw ToolError.missingAPIKey(service: "Tavily") }

        let request = HTTPRequest(
            url: endpoint,
            method: "POST",
            headers: ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"],
            body: try JSONEncoder().encode(TavilyRequest(query: query, max_results: maxResults))
        )
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw ToolError.http(status: response.statusCode) }

        let results = try JSONDecoder().decode(TavilyResponse.self, from: response.body).results
        guard !results.isEmpty else {
            return ToolOutput(content: "'\(query)' için sonuç bulunamadı.")
        }

        let listing = results.enumerated().map { index, result in
            "[\(index + 1)] \(result.title)\n\(result.url)\n\(result.content ?? "")"
        }.joined(separator: "\n\n")
        let sources = results.compactMap { result in
            URL(string: result.url).map { Source(title: result.title, url: $0) }
        }
        return ToolOutput(content: untrustedContent(listing, source: "web_search: \(query)"), sources: sources)
    }
}
