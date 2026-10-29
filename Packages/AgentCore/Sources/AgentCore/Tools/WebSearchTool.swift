import Foundation

/// Tavily ile web araması: başlık + URL + özet döndürür.
public struct WebSearchTool: Tool {
    private struct Arguments: Decodable {
        let query: String
        let max_results: Int?
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
    public let description = "Searches the web and returns the title, URL and snippet of the most relevant results. Use it when current information is needed."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "Search query"],
            "max_results": [
                "type": "integer",
                "minimum": 1,
                "maximum": 10,
                "description": "How many results to return. 1-2 for a single fact (weather, exchange rate, score, date); 3 for normal questions; 5-10 for comparisons or in-depth research.",
            ],
        ],
        "required": ["query"],
    ]

    static let resultLimit = 1...10

    private let apiKey: String
    private let transport: any HTTPTransport
    private let defaultMaxResults: Int
    private let endpoint = URL(string: "https://api.tavily.com/search")!

    /// `defaultMaxResults`: model `max_results` vermezse kullanılır.
    public init(apiKey: String, transport: any HTTPTransport, defaultMaxResults: Int = 3) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.transport = transport
        self.defaultMaxResults = defaultMaxResults
    }

    public func activityDetail(for arguments: String) -> String? {
        (try? decodeArguments(Arguments.self, from: arguments))?.query
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let arguments = try decodeArguments(Arguments.self, from: arguments)
        let query = arguments.query
        guard !apiKey.isEmpty else { throw ToolError.missingAPIKey(service: "Tavily") }
        let maxResults = (arguments.max_results ?? defaultMaxResults).clamped(to: Self.resultLimit)

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
            return ToolOutput(content: "No results found for '\(query)'.")
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

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
