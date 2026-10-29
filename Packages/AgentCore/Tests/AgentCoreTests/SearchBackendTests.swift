import Foundation
import Testing
@testable import AgentCore

@Test func braveSearchParsesResults() async throws {
    let json = #"{"web":{"results":[{"title":"<strong>Çay</strong> tarihi","url":"https://a.com/cay","description":"Çayın &amp; <strong>hikayesi</strong>"},{"title":"İki","url":"https://b.com","description":"x"}]}}"#
    let transport = SendRecorder(json: json)
    let tool = WebSearchTool(backend: .brave(apiKey: " bk "), transport: transport)

    let output = try await tool.run(arguments: #"{"query":"çay tarihi","max_results":1}"#)

    let request = try #require(transport.requests.first)
    #expect(request.url.absoluteString.hasPrefix("https://api.search.brave.com/res/v1/web/search?q="))
    #expect(request.url.absoluteString.contains("count=1"))
    #expect(request.headers["X-Subscription-Token"] == "bk")
    #expect(output.content.contains("[1] Çay tarihi\nhttps://a.com/cay\nÇayın & hikayesi"))
    #expect(!output.content.contains("[2]"))
    #expect(output.sources == [Source(title: "Çay tarihi", url: URL(string: "https://a.com/cay")!)])
}

@Test func searxngParsesResults() async throws {
    let json = #"{"query":"x","results":[{"title":"Sonuç","url":"https://c.com","content":"özet"},{"url":"https://d.com"}]}"#
    let transport = SendRecorder(json: json)
    let tool = WebSearchTool(backend: .searxng(baseURL: "https://search.example.com/"), transport: transport)

    let output = try await tool.run(arguments: #"{"query":"x","max_results":5}"#)

    #expect(transport.requests.first?.url.absoluteString == "https://search.example.com/search?q=x&format=json")
    #expect(output.content.contains("[1] Sonuç\nhttps://c.com\nözet"))
    #expect(output.content.contains("[2] https://d.com\nhttps://d.com"))
}

@Test func duckDuckGoParsesHTMLResults() async throws {
    let html = """
    <div class="result results_links result--ad"><a class="result__a" href="https://duckduckgo.com/y.js?ad=1">Reklam</a></div>
    <div class="result results_links web-result">
      <h2><a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fa.com%2Fcay%3Fx%3D1&amp;rut=abc">Çay <b>tarihi</b></a></h2>
      <a class="result__snippet" href="#">Çayın &amp; hikayesi</a>
    </div>
    <div class="result web-result"><a class="result__a" href="https://b.com/">İki</a></div>
    """
    let transport = SendRecorder(json: html)
    let tool = WebSearchTool(backend: .duckDuckGo, transport: transport)

    let output = try await tool.run(arguments: #"{"query":"çay tarihi & fiyat","max_results":5}"#)

    let request = try #require(transport.requests.first)
    #expect(request.url.absoluteString == "https://html.duckduckgo.com/html/")
    #expect(request.method == "POST")
    #expect(String(decoding: try #require(request.body), as: UTF8.self) == "q=%C3%A7ay+tarihi+%26+fiyat&b=")
    #expect(output.content.contains("[1] Çay tarihi\nhttps://a.com/cay?x=1\nÇayın & hikayesi"))
    #expect(output.content.contains("[2] İki\nhttps://b.com/"))
    #expect(!output.content.contains("Reklam"))
}

@Test func duckDuckGoReportsBlocking() async throws {
    await #expect(throws: ToolError.searchBlocked(service: "DuckDuckGo")) {
        try await WebSearchTool(backend: .duckDuckGo, transport: SendRecorder(status: 202, json: "")).run(arguments: #"{"query":"x"}"#)
    }
    let challenge = #"<html><div class="anomaly-modal__title">Unfortunately, bots use DuckDuckGo too.</div></html>"#
    await #expect(throws: ToolError.searchBlocked(service: "DuckDuckGo")) {
        try await WebSearchTool(backend: .duckDuckGo, transport: SendRecorder(json: challenge)).run(arguments: #"{"query":"x"}"#)
    }
    let empty = try await WebSearchTool(backend: .duckDuckGo, transport: SendRecorder(json: "<html></html>")).run(arguments: #"{"query":"x"}"#)
    #expect(empty.content == "No results found for 'x'.")
}

@Test func fallsBackToDuckDuckGoOnQuotaOrKeyErrors() async throws {
    let used = UsedBackends()
    let quota = WebSearchTool(backend: .tavily(apiKey: "k"), transport: HostTransport(statuses: ["api.tavily.com": 432]),
                              fallback: .duckDuckGo, onSearch: { used.append($0) })
    let output = try await quota.run(arguments: #"{"query":"x"}"#)
    #expect(output.content.hasPrefix("Note: Tavily failed (HTTP error 432.), so these results come from DuckDuckGo."))
    #expect(used.all == [.duckDuckGo])

    let noKey = WebSearchTool(backend: .brave(apiKey: ""), transport: SendRecorder(json: "<html></html>"), fallback: .duckDuckGo)
    #expect(try await noKey.run(arguments: #"{"query":"x"}"#).content.contains("Brave Search failed"))

    // Sunucu hatası yedeğe geçirmez.
    await #expect(throws: ToolError.http(status: 500)) {
        try await WebSearchTool(backend: .tavily(apiKey: "k"), transport: SendRecorder(status: 500, json: ""), fallback: .duckDuckGo)
            .run(arguments: #"{"query":"x"}"#)
    }
}

/// Her sunucuya ayrı durum kodu döndürür; listede olmayanlar 200 ve boş sayfa alır.
struct HostTransport: HTTPTransport {
    let statuses: [String: Int]

    func lines(for request: HTTPRequest) -> AsyncThrowingStream<String, any Error> {
        AsyncThrowingStream { $0.finish() }
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(statusCode: statuses[request.url.host ?? ""] ?? 200, contentType: "text/html", body: Data("<html></html>".utf8))
    }
}

final class UsedBackends: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [SearchBackend] = []
    var all: [SearchBackend] { lock.withLock { items } }
    func append(_ backend: SearchBackend) { lock.withLock { items.append(backend) } }
}

@Test func searchBackendsValidateSettings() async throws {
    await #expect(throws: ToolError.missingAPIKey(service: "Brave Search")) {
        try await WebSearchTool(backend: .brave(apiKey: ""), transport: MockTransport()).run(arguments: #"{"query":"x"}"#)
    }
    await #expect(throws: ToolError.invalidURL) {
        try await WebSearchTool(backend: .searxng(baseURL: "http://insecure.local"), transport: MockTransport()).run(arguments: #"{"query":"x"}"#)
    }
}
