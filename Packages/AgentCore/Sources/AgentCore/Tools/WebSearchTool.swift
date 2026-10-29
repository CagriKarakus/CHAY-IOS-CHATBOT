import Foundation
import SwiftSoup

/// Web aramasını yapan servis. Kullanıcı Ayarlar'dan seçer.
public enum SearchBackend: Equatable, Sendable {
    /// Tavily (api.tavily.com), API key ile.
    case tavily(apiKey: String)
    /// Brave Search API, API key ile.
    case brave(apiKey: String)
    /// Kendi sunucunda veya herkese açık bir SearXNG örneği (JSON çıktısı açık olmalı).
    case searxng(baseURL: String)
    /// DuckDuckGo'nun JavaScript'siz HTML sayfası; key gerekmez. Resmi API değil, sayfa değişirse veya
    /// DuckDuckGo otomatik aramaları engellerse çalışmayabilir.
    case duckDuckGo

    var serviceName: String {
        switch self {
        case .tavily: "Tavily"
        case .brave: "Brave Search"
        case .searxng: "SearXNG"
        case .duckDuckGo: "DuckDuckGo"
        }
    }
}

/// Web araması: başlık + URL + özet döndürür.
public struct WebSearchTool: Tool {
    private struct Arguments: Decodable {
        let query: String
        let max_results: Int?
    }

    struct Result: Equatable {
        let title: String
        let url: String
        let snippet: String
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

    private let backend: SearchBackend
    private let transport: any HTTPTransport
    private let defaultMaxResults: Int
    private let fallback: SearchBackend?
    private let onSearch: (@Sendable (SearchBackend) -> Void)?

    /// `defaultMaxResults`: model `max_results` vermezse kullanılır.
    /// `fallback`: asıl servis key veya kota hatası verirse aynı arama bununla tekrarlanır.
    /// `onSearch`: başarılı her aramada kullanılan servisle çağrılır (sayaç için).
    public init(
        backend: SearchBackend,
        transport: any HTTPTransport,
        defaultMaxResults: Int = 3,
        fallback: SearchBackend? = nil,
        onSearch: (@Sendable (SearchBackend) -> Void)? = nil
    ) {
        self.backend = backend
        self.transport = transport
        self.defaultMaxResults = defaultMaxResults
        self.fallback = fallback
        self.onSearch = onSearch
    }

    /// Tavily ile arama.
    public init(apiKey: String, transport: any HTTPTransport, defaultMaxResults: Int = 3) {
        self.init(backend: .tavily(apiKey: apiKey), transport: transport, defaultMaxResults: defaultMaxResults)
    }

    public func activityDetail(for arguments: String) -> String? {
        (try? decodeArguments(Arguments.self, from: arguments))?.query
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let arguments = try decodeArguments(Arguments.self, from: arguments)
        let query = arguments.query
        let maxResults = (arguments.max_results ?? defaultMaxResults).clamped(to: Self.resultLimit)

        var used = backend
        var note = ""
        var found: [Result]
        do {
            found = try await search(query, maxResults: maxResults, on: backend)
        } catch let error as ToolError where fallback != nil && Self.isAccountProblem(error) {
            used = fallback!
            found = try await search(query, maxResults: maxResults, on: used)
            note = "Note: \(backend.serviceName) failed (\(error.localizedDescription)), so these results come from \(used.serviceName).\n\n"
        }
        onSearch?(used)
        let results = Array(found.prefix(maxResults))
        guard !results.isEmpty else {
            return ToolOutput(content: note + "No results found for '\(query)'.")
        }

        let listing = results.enumerated().map { index, result in
            "[\(index + 1)] \(result.title)\n\(result.url)\n\(result.snippet)"
        }.joined(separator: "\n\n")
        let sources = results.compactMap { result in
            URL(string: result.url).map { Source(title: result.title, url: $0) }
        }
        return ToolOutput(content: note + untrustedContent(listing, source: "web_search: \(query)"), sources: sources)
    }

    /// Yedeğe geçmeyi gerektiren hatalar: key yok/geçersiz veya kota bitti (Tavily 432/433, Brave 429).
    static func isAccountProblem(_ error: ToolError) -> Bool {
        switch error {
        case .missingAPIKey: true
        case let .http(status): [401, 403, 429, 432, 433].contains(status)
        default: false
        }
    }

    private func search(_ query: String, maxResults: Int, on backend: SearchBackend) async throws -> [Result] {
        switch backend {
        case let .tavily(apiKey):
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw ToolError.missingAPIKey(service: backend.serviceName) }
            struct Body: Encodable {
                let query: String
                let max_results: Int
                let search_depth = "basic"
            }
            struct Response: Decodable {
                struct Item: Decodable {
                    let title: String
                    let url: String
                    let content: String?
                }
                let results: [Item]
            }
            let response: Response = try await fetch(HTTPRequest(
                url: URL(string: "https://api.tavily.com/search")!,
                method: "POST",
                headers: ["Authorization": "Bearer \(key)", "Content-Type": "application/json"],
                body: try JSONEncoder().encode(Body(query: query, max_results: maxResults))
            ))
            return response.results.map { Result(title: $0.title, url: $0.url, snippet: $0.content ?? "") }

        case let .brave(apiKey):
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { throw ToolError.missingAPIKey(service: backend.serviceName) }
            struct Response: Decodable {
                struct Web: Decodable {
                    struct Item: Decodable {
                        let title: String
                        let url: String
                        let description: String?
                    }
                    let results: [Item]
                }
                let web: Web?
            }
            var components = URLComponents(string: "https://api.search.brave.com/res/v1/web/search")!
            components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "count", value: String(maxResults))]
            let response: Response = try await fetch(HTTPRequest(
                url: components.url!,
                method: "GET",
                headers: ["X-Subscription-Token": key, "Accept": "application/json"],
                body: nil
            ))
            return (response.web?.results ?? []).map {
                Result(title: Self.strippingTags($0.title), url: $0.url, snippet: Self.strippingTags($0.description ?? ""))
            }

        case let .searxng(baseURL):
            guard let base = try? LLMConfiguration.validatedBaseURL(baseURL),
                  var components = URLComponents(url: base.appendingPathComponent("search"), resolvingAgainstBaseURL: false)
            else { throw ToolError.invalidURL }
            components.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "format", value: "json")]
            struct Response: Decodable {
                struct Item: Decodable {
                    let title: String?
                    let url: String
                    let content: String?
                }
                let results: [Item]
            }
            let response: Response = try await fetch(HTTPRequest(
                url: components.url!,
                method: "GET",
                headers: ["Accept": "application/json"],
                body: nil
            ))
            return response.results.map { Result(title: $0.title ?? $0.url, url: $0.url, snippet: $0.content ?? "") }

        case .duckDuckGo:
            let response = try await transport.send(HTTPRequest(
                url: URL(string: "https://html.duckduckgo.com/html/")!,
                method: "POST",
                headers: [
                    "Content-Type": "application/x-www-form-urlencoded",
                    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
                ],
                body: Data("q=\(Self.formEncoded(query))&b=".utf8)
            ))
            // DuckDuckGo şüphelendiğinde 202 ile doğrulama (CAPTCHA) sayfası döndürür.
            if response.statusCode == 202 { throw ToolError.searchBlocked(service: backend.serviceName) }
            guard (200..<300).contains(response.statusCode) else { throw ToolError.http(status: response.statusCode) }
            let html = String(decoding: response.body, as: UTF8.self)
            let results = try Self.duckDuckGoResults(html)
            if results.isEmpty, html.contains("anomaly-modal") || html.contains("challenge-form") {
                throw ToolError.searchBlocked(service: backend.serviceName)
            }
            return results
        }
    }

    /// DuckDuckGo HTML sonuçları: reklamlar atlanır, yönlendirme linkleri asıl adrese çevrilir.
    static func duckDuckGoResults(_ html: String) throws -> [Result] {
        let document = try SwiftSoup.parse(html)
        return try document.select("div.result").compactMap { element in
            guard !element.hasClass("result--ad"),
                  let link = try element.select("a.result__a").first(),
                  let url = duckDuckGoTarget(try link.attr("href"))
            else { return nil }
            let snippet = try element.select(".result__snippet").first()?.text() ?? ""
            return Result(title: try link.text(), url: url, snippet: snippet)
        }
    }

    /// `//duckduckgo.com/l/?uddg=<adres>` → asıl adres. DuckDuckGo'nun kendi sayfaları (reklam) elenir.
    static func duckDuckGoTarget(_ href: String) -> String? {
        let absolute = href.hasPrefix("//") ? "https:" + href : href
        guard let components = URLComponents(string: absolute) else { return nil }
        let target: String
        if components.host?.hasSuffix("duckduckgo.com") == true {
            guard components.path == "/l/",
                  let uddg = components.queryItems?.first(where: { $0.name == "uddg" })?.value
            else { return nil }
            target = uddg
        } else {
            target = absolute
        }
        guard let url = URL(string: target), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.hasSuffix("duckduckgo.com") != true
        else { return nil }
        return target
    }

    /// application/x-www-form-urlencoded: harf/rakam dışındaki her bayt kodlanır, boşluk `+` olur.
    static func formEncoded(_ text: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~ ")
        return (text.addingPercentEncoding(withAllowedCharacters: allowed) ?? "").replacingOccurrences(of: " ", with: "+")
    }

    private func fetch<T: Decodable>(_ request: HTTPRequest) async throws -> T {
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw ToolError.http(status: response.statusCode) }
        return try JSONDecoder().decode(T.self, from: response.body)
    }

    /// Brave özetlerindeki `<strong>` gibi HTML etiketlerini atar.
    static func strippingTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
