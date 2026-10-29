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

@Test func searchBackendsValidateSettings() async throws {
    await #expect(throws: ToolError.missingAPIKey(service: "Brave Search")) {
        try await WebSearchTool(backend: .brave(apiKey: ""), transport: MockTransport()).run(arguments: #"{"query":"x"}"#)
    }
    await #expect(throws: ToolError.invalidURL) {
        try await WebSearchTool(backend: .searxng(baseURL: "http://insecure.local"), transport: MockTransport()).run(arguments: #"{"query":"x"}"#)
    }
}
