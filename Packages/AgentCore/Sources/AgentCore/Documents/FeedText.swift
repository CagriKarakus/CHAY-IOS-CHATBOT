import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// RSS 2.0 ve Atom beslemelerini modelin okuyacağı haber listesine çevirir.
public enum FeedText {
    struct Item: Equatable {
        var title = ""
        var link = ""
        var date = ""
        var summary = ""
    }

    /// En fazla bu kadar haber alınır.
    static let maxItems = 30

    /// Veri bir RSS/Atom beslemesi değilse `nil`.
    public static func parse(_ data: Data) -> String? {
        let head = String(decoding: data.prefix(2_000), as: UTF8.self).lowercased()
        guard head.contains("<rss") || head.contains("<feed") || head.contains("<rdf:rdf") else { return nil }

        let collector = Collector()
        let parser = XMLParser(data: data)
        parser.delegate = collector
        parser.shouldProcessNamespaces = false
        parser.parse()
        guard !collector.items.isEmpty else { return nil }

        var lines: [String] = []
        if !collector.feedTitle.isEmpty {
            lines.append("Feed: \(collector.feedTitle)")
        }
        for item in collector.items.prefix(maxItems) {
            var entry = "- " + (item.date.isEmpty ? "" : "[\(item.date)] ") + item.title
            if !item.link.isEmpty { entry += "\n  \(item.link)" }
            let summary = cleaned(item.summary)
            if !summary.isEmpty { entry += "\n  \(String(summary.prefix(400)))" }
            lines.append(entry)
        }
        return lines.joined(separator: "\n")
    }

    /// HTML etiketlerini ve fazla boşlukları atar.
    static func cleaned(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private final class Collector: NSObject, XMLParserDelegate {
        var feedTitle = ""
        var items: [Item] = []
        private var current: Item?
        private var text = ""

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            switch name {
            case "item", "entry":
                current = Item()
            case "link" where current != nil:
                // Atom: <link href="..."/>; alternatif bağlantı tercih edilir.
                if let href = attributes["href"], current?.link.isEmpty == true || attributes["rel"] == "alternate" {
                    current?.link = href
                }
            default:
                break
            }
            text = ""
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            text += string
        }

        func parser(_ parser: XMLParser, foundCDATA block: Data) {
            text += String(decoding: block, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            defer { text = "" }
            guard current != nil else {
                if name == "title", feedTitle.isEmpty { feedTitle = value }
                return
            }
            switch name {
            case "item", "entry":
                if let current { items.append(current) }
                current = nil
            case "title":
                current?.title = FeedText.cleaned(value)
            case "link" where !value.isEmpty:
                current?.link = value
            case "pubDate", "published", "updated", "dc:date":
                if current?.date.isEmpty == true { current?.date = value }
            case "description", "summary", "content", "content:encoded":
                if current?.summary.isEmpty == true { current?.summary = value }
            default:
                break
            }
        }
    }
}
