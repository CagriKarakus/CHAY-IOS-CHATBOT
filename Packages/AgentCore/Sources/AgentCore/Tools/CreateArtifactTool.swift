import Foundation

/// Etkileşimli HTML sayfası (artifact) oluşturur: grafik, hesaplayıcı, mini uygulama, oyun…
/// Sayfa Documents klasörüne `.html` olarak kaydedilir ve uygulamada izole bir web görünümünde açılır.
public struct CreateArtifactTool: Tool {
    private struct Arguments: Decodable {
        let title: String
        let html: String
    }

    static let maxLength = 500_000

    public let name = "create_artifact"
    public let description = "Creates an interactive web page (artifact) the user can open in the app: charts, visualizations, calculators, small apps or games. Write one self-contained HTML document with inline CSS and JavaScript; external libraries only from cdnjs.cloudflare.com or cdn.jsdelivr.net. Use the same title to update an existing artifact."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "title": ["type": "string", "description": "Short title, also used as the file name"],
            "html": ["type": "string", "description": "Complete HTML document (or body content) with inline CSS and JavaScript"],
        ],
        "required": ["title", "html"],
    ]

    private let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    public func activityDetail(for arguments: String) -> String? {
        (try? decodeArguments(Arguments.self, from: arguments))?.title
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let arguments = try decodeArguments(Arguments.self, from: arguments)
        let filename = try WriteFileTool.sanitizedFilename(arguments.title, extension: "html")
        guard !arguments.html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw ToolError.invalidArguments }
        guard arguments.html.count <= Self.maxLength else { throw ToolError.tooLong(limit: Self.maxLength) }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        let existed = FileManager.default.fileExists(atPath: url.path)
        try Data(Self.document(title: arguments.title, html: arguments.html).utf8).write(to: url, options: .atomic)

        return ToolOutput(
            content: "Artifact \(existed ? "updated" : "created"): \(filename). The user can open it in the chat as an interactive page.",
            files: [url]
        )
    }

    /// Tam bir HTML belgesi değilse mobil uyumlu bir iskelete yerleştirir.
    static func document(title: String, html: String) -> String {
        if html.range(of: "<html", options: .caseInsensitive) != nil {
            return html
        }
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(escapedTitle)</title>
        </head>
        <body>
        \(html)
        </body>
        </html>
        """
    }
}
