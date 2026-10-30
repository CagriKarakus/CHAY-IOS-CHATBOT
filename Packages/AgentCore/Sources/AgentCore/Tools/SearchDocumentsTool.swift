import Foundation

/// Kayıtlı Markdown dokümanlarında arar veya bir dokümanı okur. Sadece verilen klasöre bakar.
public struct SearchDocumentsTool: Tool {
    private struct Arguments: Decodable {
        let query: String?
        let file: String?
    }

    /// Aramada dönen en fazla dosya.
    static let resultLimit = 5
    /// Tek dosya okumada modele giden en fazla uzunluk.
    static let fileLimit = 20_000
    private static let excerptRadius = 150
    private static let matchOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    public let name = "search_documents"
    public let description = "Searches the user's saved Markdown documents, or reads one. Use it when the user refers to their documents or notes in files, or when a saved document may hold the answer."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "Words to search for"],
            "file": ["type": "string", "description": "Name of a document to read in full, e.g. 'report.md'"],
        ],
    ]

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func activityDetail(for arguments: String) -> String? {
        let arguments = try? decodeArguments(Arguments.self, from: arguments)
        return arguments?.file ?? arguments?.query
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let arguments = try decodeArguments(Arguments.self, from: arguments)
        if let file = arguments.file, !file.isEmpty {
            return try read(file)
        }
        guard let query = arguments.query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            throw ToolError.invalidArguments
        }
        return search(query)
    }

    private func read(_ raw: String) throws -> ToolOutput {
        let filename = try WriteFileTool.sanitizedFilename(raw)
        guard let text = try? String(contentsOf: directory.appendingPathComponent(filename), encoding: .utf8) else {
            return ToolOutput(content: "There is no document named \(filename).")
        }
        let limited = text.count > Self.fileLimit ? String(text.prefix(Self.fileLimit)) + "\n[…truncated]" : text
        return ToolOutput(content: untrustedContent(limited, source: "document: \(filename)"))
    }

    private func search(_ query: String) -> ToolOutput {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count >= 3 }
        let terms = [query] + (words.count > 1 ? words : [])
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []

        let matches = files
            .filter { $0.pathExtension.lowercased() == "md" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url -> (name: String, score: Int, excerpt: String)? in
                guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
                let hits = terms.filter { text.range(of: $0, options: Self.matchOptions) != nil }
                guard let first = hits.first, let range = text.range(of: first, options: Self.matchOptions) else { return nil }
                return (url.lastPathComponent, hits.count, Self.excerpt(of: text, around: range))
            }
            .sorted { $0.score > $1.score }
            .prefix(Self.resultLimit)

        guard !matches.isEmpty else {
            return ToolOutput(content: "No saved document contains '\(query)'.")
        }
        let listing = matches.map { "\($0.name)\n\($0.excerpt)" }.joined(separator: "\n\n")
        return ToolOutput(content: untrustedContent(listing, source: "documents: \(query)")
            + "\nCall search_documents with file to read one in full.")
    }

    private static func excerpt(of text: String, around range: Range<String.Index>) -> String {
        let start = text.index(range.lowerBound, offsetBy: -excerptRadius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: excerptRadius, limitedBy: text.endIndex) ?? text.endIndex
        return (start > text.startIndex ? "…" : "") + text[start..<end].trimmingCharacters(in: .whitespacesAndNewlines)
            + (end < text.endIndex ? "…" : "")
    }
}
