import Foundation
import Testing
@testable import AgentCore

@Test func parsesRSS() throws {
    let rss = """
    <?xml version="1.0"?><rss version="2.0"><channel><title>Haberler</title>
    <item><title>Birinci haber</title><link>https://n.com/1</link><pubDate>Thu, 29 Oct 2026 07:00:00 +0300</pubDate>
    <description><![CDATA[<p>Kısa <b>özet</b> &amp; detay</p>]]></description></item>
    <item><title>İkinci</title><link>https://n.com/2</link></item>
    </channel></rss>
    """

    let text = try #require(FeedText.parse(Data(rss.utf8)))

    #expect(text == "Feed: Haberler\n- [Thu, 29 Oct 2026 07:00:00 +0300] Birinci haber\n  https://n.com/1\n  Kısa özet & detay\n- İkinci\n  https://n.com/2")
}

@Test func parsesAtom() throws {
    let atom = """
    <feed xmlns="http://www.w3.org/2005/Atom"><title>Blog</title>
    <entry><title>Yazı</title><link rel="alternate" href="https://b.com/yazi"/><updated>2026-10-29T07:00:00Z</updated><summary>Özet</summary></entry>
    </feed>
    """

    #expect(FeedText.parse(Data(atom.utf8)) == "Feed: Blog\n- [2026-10-29T07:00:00Z] Yazı\n  https://b.com/yazi\n  Özet")
}

@Test func nonFeedsReturnNil() {
    #expect(FeedText.parse(Data("<html><body>x</body></html>".utf8)) == nil)
}

@Test func fetchPageReadsFeeds() async throws {
    let rss = #"<rss><channel><title>T</title><item><title>Haber</title><link>https://n.com/1</link></item></channel></rss>"#
    let transport = MockTransport(response: HTTPResponse(statusCode: 200, contentType: "application/rss+xml", body: Data(rss.utf8)))

    let output = try await FetchPageTool(transport: transport).run(arguments: #"{"url":"https://n.com/feed"}"#)

    #expect(output.content.contains("- Haber\n  https://n.com/1"))
}
