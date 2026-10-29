import Foundation
import SwiftSoup

/// Bir web sayfasını indirip okunabilir metne çevirir.
public struct FetchPageTool: Tool {
    private struct Arguments: Decodable {
        let url: String
    }

    public let name = "fetch_page"
    public let description = "Reads the text of a web page, or the latest items of an RSS/Atom feed. Use it when you need the details of a page from the search results or when the user gives feed URLs."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "url": ["type": "string", "description": "https:// URL of the page to read"],
        ],
        "required": ["url"],
    ]

    private let transport: any HTTPTransport
    private let maxCharacters: Int

    /// `maxCharacters`: modele gönderilecek en fazla karakter (bağlam ve maliyet için).
    public init(transport: any HTTPTransport, maxCharacters: Int = 8_000) {
        self.transport = transport
        self.maxCharacters = maxCharacters
    }

    public func activityDetail(for arguments: String) -> String? {
        guard let raw = try? decodeArguments(Arguments.self, from: arguments).url else { return nil }
        return URL(string: raw)?.host ?? raw
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let raw = try decodeArguments(Arguments.self, from: arguments).url
        guard let url = URL(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.scheme?.lowercased() == "https", url.host != nil
        else { throw ToolError.invalidURL }

        let request = HTTPRequest(
            url: url,
            method: "GET",
            headers: ["Accept": "text/html,text/plain;q=0.9,*/*;q=0.5"],
            body: nil
        )
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw ToolError.http(status: response.statusCode) }

        let contentType = response.contentType?.lowercased() ?? "text/html"
        let body = String(data: response.body, encoding: .utf8) ?? String(decoding: response.body, as: UTF8.self)

        let title: String
        let text: String
        if let feed = FeedText.parse(response.body) {
            // RSS/Atom: haber listesi (başlık, tarih, bağlantı, kısa özet).
            (title, text) = (url.host ?? raw, feed)
        } else if contentType.contains("html") {
            (title, text) = try readableText(fromHTML: body)
        } else if contentType.hasPrefix("text/") || contentType.contains("json") || contentType.contains("markdown") || contentType.contains("xml") {
            (title, text) = (url.host ?? raw, body)
        } else {
            throw ToolError.unsupportedContent(contentType)
        }

        var content = "Title: \(title)\n\n" + String(text.prefix(maxCharacters))
        if text.count > maxCharacters {
            content += "\n\n[Page truncated at \(maxCharacters) characters.]"
        }
        return ToolOutput(content: untrustedContent(content, source: url.absoluteString), sources: [Source(title: title, url: url)])
    }

    /// Script, stil ve menü gibi gürültüyü atıp görünen metni çıkarır.
    func readableText(fromHTML html: String) throws -> (title: String, text: String) {
        let document = try SwiftSoup.parse(html)
        try document.select("script, style, noscript, svg, nav, header, footer, aside, form, iframe").remove()
        let title = try document.title().trimmingCharacters(in: .whitespacesAndNewlines)
        let root = try document.select("article, main").first() ?? document.body()
        let text = try root?.text() ?? ""
        return (title.isEmpty ? "Untitled page" : title, text)
    }
}
