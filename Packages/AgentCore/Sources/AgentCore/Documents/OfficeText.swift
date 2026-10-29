import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

/// Office Open XML (docx, xlsx, pptx) dosyalarından düz metin çıkarır.
/// Dosyalar ZIP arşividir; arşivi açmak uygulamaya kalır (`read` ile içteki dosyalar verilir).
public enum OfficeText {
    public enum Kind: String, Sendable {
        case word = "docx", spreadsheet = "xlsx", presentation = "pptx"
    }

    /// En fazla bu kadar satır alınır (çok büyük tablolar bağlamı doldurmasın).
    static let maxRowsPerSheet = 2_000

    /// - Parameters:
    ///   - entries: arşivdeki dosya yolları.
    ///   - read: arşivdeki bir dosyanın içeriği.
    public static func extract(kind: Kind, entries: [String], read: (String) -> Data?) -> String? {
        switch kind {
        case .word:
            return read("word/document.xml").map(wordText)
        case .presentation:
            let slides = entries
                .filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
                .sorted { number(in: $0) < number(in: $1) }
            guard !slides.isEmpty else { return nil }
            return slides.enumerated().compactMap { index, path in
                read(path).map { "## Slide \(index + 1)\n\(paragraphText($0, text: "a:t", paragraph: "a:p"))" }
            }.joined(separator: "\n\n")
        case .spreadsheet:
            let strings = read("xl/sharedStrings.xml").map(sharedStrings) ?? []
            let sheets = sheetList(workbook: read("xl/workbook.xml"), relationships: read("xl/_rels/workbook.xml.rels"), entries: entries)
            guard !sheets.isEmpty else { return nil }
            return sheets.compactMap { name, path in
                read(path).map { xml in
                    let rows = sheetRows(xml, sharedStrings: strings)
                    return "## \(name)\n" + rows.map { $0.joined(separator: "\t") }.joined(separator: "\n")
                }
            }.joined(separator: "\n\n")
        }
    }

    // MARK: - Word / PowerPoint

    static func wordText(_ xml: Data) -> String {
        paragraphText(xml, text: "w:t", paragraph: "w:p", tab: "w:tab", lineBreak: "w:br")
    }

    /// Paragraf sonlarını satır sonuna çevirerek metin düğümlerini birleştirir.
    static func paragraphText(_ xml: Data, text: String, paragraph: String, tab: String? = nil, lineBreak: String? = nil) -> String {
        var output = ""
        var collecting = false
        parse(xml) { event in
            switch event {
            case let .start(name, _):
                if name == text { collecting = true }
                if name == tab { output += "\t" }
                if name == lineBreak { output += "\n" }
            case let .end(name):
                if name == text { collecting = false }
                if name == paragraph { output += "\n" }
            case let .characters(value):
                if collecting { output += value }
            }
        }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Excel

    static func sharedStrings(_ xml: Data) -> [String] {
        var strings: [String] = []
        var current = ""
        var inText = false
        var inPhonetic = false
        parse(xml) { event in
            switch event {
            case let .start(name, _):
                if name == "si" { current = "" }
                if name == "rPh" { inPhonetic = true }
                if name == "t" && !inPhonetic { inText = true }
            case let .end(name):
                if name == "t" { inText = false }
                if name == "rPh" { inPhonetic = false }
                if name == "si" { strings.append(current) }
            case let .characters(value):
                if inText { current += value }
            }
        }
        return strings
    }

    /// Hücreleri satır/sütun konumuna göre yerleştirir; boş hücreler boş metin olur.
    static func sheetRows(_ xml: Data, sharedStrings: [String]) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var cellColumn = 0
        var cellType: String?
        var value = ""
        var collecting = false
        parse(xml) { event in
            switch event {
            case let .start(name, attributes):
                switch name {
                case "row": row = []
                case "c":
                    cellColumn = attributes["r"].map(columnIndex) ?? row.count
                    cellType = attributes["t"]
                    value = ""
                case "v", "t": collecting = true
                default: break
                }
            case let .end(name):
                switch name {
                case "v", "t": collecting = false
                case "c":
                    let text: String = switch cellType {
                    case "s": Int(value).flatMap { sharedStrings.indices.contains($0) ? sharedStrings[$0] : nil } ?? ""
                    case "b": value == "1" ? "TRUE" : "FALSE"
                    default: value
                    }
                    if row.count < cellColumn { row += Array(repeating: "", count: cellColumn - row.count) }
                    if row.count == cellColumn { row.append(text) } else { row[cellColumn] = text }
                case "row":
                    while row.last == "" { row.removeLast() }
                    if !row.isEmpty, rows.count < maxRowsPerSheet { rows.append(row) }
                default: break
                }
            case let .characters(text):
                if collecting { value += text }
            }
        }
        return rows
    }

    /// "C12" → 2 (sıfırdan başlayan sütun).
    static func columnIndex(_ reference: String) -> Int {
        reference.prefix { $0.isLetter }.uppercased().unicodeScalars.reduce(0) { $0 * 26 + Int($1.value) - 64 } - 1
    }

    /// Sayfa adları ve dosya yolları, çalışma kitabındaki sırayla.
    static func sheetList(workbook: Data?, relationships: Data?, entries: [String]) -> [(name: String, path: String)] {
        var targets: [String: String] = [:]
        if let relationships {
            parse(relationships) { event in
                if case let .start("Relationship", attributes) = event, let id = attributes["Id"], let target = attributes["Target"] {
                    targets[id] = target.hasPrefix("/") ? String(target.dropFirst()) : "xl/" + target
                }
            }
        }
        var sheets: [(String, String)] = []
        if let workbook {
            parse(workbook) { event in
                if case let .start("sheet", attributes) = event,
                   let name = attributes["name"], let id = attributes["r:id"], let path = targets[id] {
                    sheets.append((name, path))
                }
            }
        }
        if sheets.isEmpty {
            // İlişki dosyası okunamazsa sayfa dosyalarını sırayla al.
            sheets = entries
                .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
                .sorted { number(in: $0) < number(in: $1) }
                .map { ("Sheet \(number(in: $0))", $0) }
        }
        return sheets
    }

    private static func number(in path: String) -> Int {
        Int(path.filter(\.isNumber)) ?? 0
    }

    // MARK: - XML

    enum Event {
        case start(String, [String: String])
        case end(String)
        case characters(String)
    }

    private final class Collector: NSObject, XMLParserDelegate {
        let handle: (Event) -> Void
        init(_ handle: @escaping (Event) -> Void) { self.handle = handle }

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String] = [:]) {
            handle(.start(name, attributes))
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            handle(.end(name))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            handle(.characters(string))
        }
    }

    static func parse(_ xml: Data, handle: @escaping (Event) -> Void) {
        let parser = XMLParser(data: xml)
        let collector = Collector(handle)
        parser.delegate = collector
        parser.shouldProcessNamespaces = false
        parser.parse()
    }
}
