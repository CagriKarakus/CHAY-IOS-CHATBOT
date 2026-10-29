import Foundation

/// Markdown dosyasını verilen klasöre (iOS'ta uygulamanın Documents klasörü) yazar.
/// Sadece düz dosya adı kabul edilir: klasör, `..` veya mutlak yol reddedilir. Aynı adlı dosya varsa yerinde güncellenir.
public struct WriteFileTool: Tool {
    private struct Arguments: Decodable {
        let filename: String
        let content: String
    }

    public let name = "write_file"
    public let description = "Creates a Markdown (.md) file in the folder the user sees in the Files app. Use it when the user asks for a document, report or summary file. Writing to an existing name replaces that file."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "filename": ["type": "string", "description": "File name, e.g. 'ai-summary.md'. No folders."],
            "content": ["type": "string", "description": "Markdown content of the file"],
        ],
        "required": ["filename", "content"],
    ]

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func activityDetail(for arguments: String) -> String? {
        guard let raw = try? decodeArguments(Arguments.self, from: arguments).filename else { return nil }
        return (try? Self.sanitizedFilename(raw)) ?? raw
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let arguments = try decodeArguments(Arguments.self, from: arguments)
        let filename = try Self.sanitizedFilename(arguments.filename)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        let existed = FileManager.default.fileExists(atPath: url.path)
        try Data(arguments.content.utf8).write(to: url, options: .atomic)

        return ToolOutput(
            content: "File \(existed ? "updated" : "saved"): \(url.lastPathComponent) (\(arguments.content.count) characters). The user can open it from the Documents screen or the Files app.",
            files: [url]
        )
    }

    /// Modelin verdiği adı güvenli bir `.md` dosya adına çevirir.
    static func sanitizedFilename(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"), !trimmed.contains("\\"),
              !trimmed.contains(".."), !trimmed.hasPrefix("~")
        else { throw ToolError.invalidFilename }

        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " -_.()"))
        var base = String(String.UnicodeScalarView(trimmed.unicodeScalars.filter { allowed.contains($0) }))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))

        // Uzantıyı at (.md dahil); sonuna her zaman .md eklenir. ".md" gibi adlar boş kalır ve reddedilir.
        if trimmed.hasPrefix(".") && !base.contains(".") {
            base = ""
        } else if let dot = base.lastIndex(of: ".") {
            base = String(base[..<dot])
        }
        base = String(base.trimmingCharacters(in: CharacterSet(charactersIn: " .")).prefix(80))
            .trimmingCharacters(in: .whitespaces)

        guard !base.isEmpty else { throw ToolError.invalidFilename }
        return base + ".md"
    }
}
