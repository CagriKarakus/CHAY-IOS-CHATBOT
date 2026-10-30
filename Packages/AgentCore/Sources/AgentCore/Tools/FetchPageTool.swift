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

    /// İndirilecek en fazla bayt; sonsuz akan veya dev dosyalar belleği doldurmasın.
    static let maxBytes = 2_000_000

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

    /// Sohbette kullanıcının veya bir aracın vermediği adres, okunan içeriğin yönlendirmesiyle sohbetteki
    /// bilgileri dışarı taşıyor olabilir; bu yüzden önce sorulur. Arama sonuçlarından gelen adresler sorulmaz.
    public func needsApprovalAfterUntrustedContent(arguments: String, conversation: [ChatMessage]) -> Bool {
        guard let url = try? decodeArguments(Arguments.self, from: arguments).url else { return false }
        var target = url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fragment = target.firstIndex(of: "#") { target = String(target[..<fragment]) }
        while target.hasSuffix("/") { target.removeLast() }
        return !conversation.contains { message in
            (message.role == .user || message.role == .tool) && (message.content?.contains(target) ?? false)
        }
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let raw = try decodeArguments(Arguments.self, from: arguments).url
        guard let url = ConnectorAddress.validated(raw) else { throw ToolError.invalidURL }

        var request = HTTPRequest(
            url: url,
            method: "GET",
            headers: ["Accept": "text/html,text/plain;q=0.9,*/*;q=0.5"],
            body: nil
        )
        request.webFetchLimit = Self.maxBytes
        let response = try await transport.send(request)
        guard (200..<300).contains(response.statusCode) else { throw ToolError.httpFailure(response) }

        let contentType = response.contentType?.lowercased() ?? "text/html"
        let body = WebText.decode(response.body, contentType: response.contentType)

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
