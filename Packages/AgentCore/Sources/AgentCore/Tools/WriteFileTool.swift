import Foundation

/// Markdown dosyasını verilen klasöre (iOS'ta uygulamanın Documents klasörü) yazar.
/// Sadece düz dosya adı kabul edilir: klasör, `..` veya mutlak yol reddedilir; aynı adlı dosyanın üzerine yazılmaz.
public struct WriteFileTool: Tool {
    private struct Arguments: Decodable {
        let filename: String
        let content: String
    }

    public let name = "write_file"
    public let description = "Markdown (.md) dosyası oluşturur ve kullanıcının Dosyalar uygulamasında görünen klasöre kaydeder. Kullanıcı doküman, rapor veya özet dosyası istediğinde kullan."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "filename": ["type": "string", "description": "Dosya adı, örn. 'yapay-zeka-ozeti.md'. Klasör içermez."],
            "content": ["type": "string", "description": "Dosyanın Markdown içeriği"],
        ],
        "required": ["filename", "content"],
    ]

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func activity(for arguments: String) -> String? {
        guard let raw = try? decodeArguments(Arguments.self, from: arguments).filename else { return nil }
        return "Dosya yazılıyor: \((try? Self.sanitizedFilename(raw)) ?? raw)"
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let arguments = try decodeArguments(Arguments.self, from: arguments)
        let filename = try Self.sanitizedFilename(arguments.filename)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = uniqueURL(for: filename)
        try Data(arguments.content.utf8).write(to: url, options: .atomic)

        return ToolOutput(
            content: "Dosya kaydedildi: \(url.lastPathComponent) (\(arguments.content.count) karakter). Kullanıcı dosyayı uygulamadaki Dokümanlar ekranında veya Dosyalar uygulamasında açabilir.",
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

    /// Aynı adlı dosya varsa "ad (2).md", "ad (3).md"… dener.
    private func uniqueURL(for filename: String) -> URL {
        let base = String(filename.dropLast(".md".count))
        var candidate = directory.appendingPathComponent(filename)
        var counter = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) (\(counter)).md")
            counter += 1
        }
        return candidate
    }
}
