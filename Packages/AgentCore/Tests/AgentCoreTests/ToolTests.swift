import Foundation
import Testing
@testable import AgentCore

// MARK: - web_search

@Test func webSearchFormatsResultsAsUntrustedData() async throws {
    let json = #"{"results":[{"title":"Haber","url":"https://news.example.com/a","content":"Özet metni","score":0.9}]}"#
    let transport = MockTransport(response: HTTPResponse(statusCode: 200, contentType: "application/json", body: Data(json.utf8)))
    let tool = WebSearchTool(apiKey: "tvly-test", transport: transport)

    let output = try await tool.run(arguments: #"{"query":"bugün"}"#)

    #expect(output.content.contains("<untrusted_content"))
    #expect(output.content.contains("[1] Haber\nhttps://news.example.com/a\nÖzet metni"))
    #expect(output.sources == [Source(title: "Haber", url: URL(string: "https://news.example.com/a")!)])
    #expect(tool.activity(for: #"{"query":"bugün"}"#) == "Aranıyor: bugün")
}

@Test func webSearchRequiresKey() async throws {
    let tool = WebSearchTool(apiKey: " ", transport: MockTransport())

    await #expect(throws: ToolError.missingAPIKey(service: "Tavily")) {
        try await tool.run(arguments: #"{"query":"x"}"#)
    }
}

@Test func webSearchReportsHTTPErrors() async throws {
    let tool = WebSearchTool(apiKey: "k", transport: MockTransport(response: HTTPResponse(statusCode: 401, contentType: nil, body: Data())))

    await #expect(throws: ToolError.http(status: 401)) {
        try await tool.run(arguments: #"{"query":"x"}"#)
    }
}

@Test func webSearchRejectsBadArguments() async throws {
    let tool = WebSearchTool(apiKey: "k", transport: MockTransport())

    await #expect(throws: ToolError.invalidArguments) {
        try await tool.run(arguments: "not json")
    }
    #expect(tool.activity(for: "") == nil)
}

// MARK: - fetch_page

@Test func fetchPageExtractsReadableText() async throws {
    let html = """
    <html><head><title> Örnek Sayfa </title><style>.a{}</style></head>
    <body><nav>Menü</nav><main><h1>Başlık</h1><p>Asıl içerik.</p><script>alert(1)</script></main><footer>Telif</footer></body></html>
    """
    let transport = MockTransport(response: HTTPResponse(statusCode: 200, contentType: "text/html; charset=utf-8", body: Data(html.utf8)))
    let tool = FetchPageTool(transport: transport)

    let output = try await tool.run(arguments: #"{"url":"https://example.com/yazi"}"#)

    #expect(output.content.contains("Başlık: Örnek Sayfa"))
    #expect(output.content.contains("Başlık Asıl içerik."))
    #expect(!output.content.contains("Menü"))
    #expect(!output.content.contains("alert"))
    #expect(!output.content.contains("Telif"))
    #expect(output.content.contains("<untrusted_content source=\"https://example.com/yazi\">"))
    #expect(output.sources == [Source(title: "Örnek Sayfa", url: URL(string: "https://example.com/yazi")!)])
    #expect(tool.activity(for: #"{"url":"https://example.com/yazi"}"#) == "Okunuyor: example.com")
}

@Test func fetchPageTruncatesLongPages() async throws {
    let body = Data(String(repeating: "a", count: 500).utf8)
    let tool = FetchPageTool(transport: MockTransport(response: HTTPResponse(statusCode: 200, contentType: "text/plain", body: body)), maxCharacters: 100)

    let output = try await tool.run(arguments: #"{"url":"https://example.com/x.txt"}"#)

    #expect(output.content.contains(String(repeating: "a", count: 100) + "\n\n[Sayfa 100 karakterde kırpıldı.]"))
    #expect(!output.content.contains(String(repeating: "a", count: 101)))
}

@Test(arguments: [#"{"url":"http://example.com"}"#, #"{"url":"file:///etc/passwd"}"#, #"{"url":"example.com"}"#])
func fetchPageRejectsNonHTTPS(_ arguments: String) async throws {
    let tool = FetchPageTool(transport: MockTransport())

    await #expect(throws: ToolError.invalidURL) {
        try await tool.run(arguments: arguments)
    }
}

@Test func fetchPageRejectsBinaryContent() async throws {
    let tool = FetchPageTool(transport: MockTransport(response: HTTPResponse(statusCode: 200, contentType: "application/pdf", body: Data())))

    await #expect(throws: ToolError.unsupportedContent("application/pdf")) {
        try await tool.run(arguments: #"{"url":"https://example.com/a.pdf"}"#)
    }
}
