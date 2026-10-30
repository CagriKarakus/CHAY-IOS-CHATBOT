import Foundation

/// Etkileşimli HTML sayfası (artifact) oluşturur: grafik, hesaplayıcı, mini uygulama, oyun…
/// Sayfa Documents klasörüne `.html` olarak kaydedilir ve uygulamada izole bir web görünümünde açılır.
public struct CreateArtifactTool: Tool {
    private struct Arguments: Decodable {
        let title: String
        let html: String
    }

    static let maxLength = 500_000
    /// Sayfa dışarıya veri gönderemesin: ağ isteği, form ve dış görsel kapalı; sadece bilinen CDN'lerden kütüphane yüklenir.
    static let contentSecurityPolicy = [
        "default-src 'none'",
        "script-src 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://unpkg.com",
        "style-src 'unsafe-inline' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://unpkg.com https://fonts.googleapis.com",
        "font-src data: https://cdn.jsdelivr.net https://cdnjs.cloudflare.com https://unpkg.com https://fonts.gstatic.com",
        "img-src data: blob:",
        "media-src data: blob:",
        "worker-src blob:",
        "connect-src 'none'",
        "form-action 'none'",
        "base-uri 'none'",
    ].joined(separator: "; ")

    public let name = "create_artifact"
    public let description = "Creates an interactive web page (artifact) the user can open in the app: charts, visualizations, calculators, small apps or games. Write one self-contained HTML document with inline CSS and JavaScript; external libraries only from cdnjs.cloudflare.com, cdn.jsdelivr.net or unpkg.com. The page can't make network requests or load remote images, so put all data inline. Use the same title to update an existing artifact."
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
    /// Güvenlik politikası en başa yazılır: sayfadaki hiçbir betik ondan önce çalışamaz.
    static func document(title: String, html: String) -> String {
        let policy = "<meta charset=\"utf-8\">\n<meta http-equiv=\"Content-Security-Policy\" content=\"\(contentSecurityPolicy)\">"
        if html.range(of: "<html", options: .caseInsensitive) != nil {
            let body = html.replacingOccurrences(of: #"^\s*<!doctype[^>]*>"#, with: "", options: [.regularExpression, .caseInsensitive])
            return "<!doctype html>\n\(policy)\n\(body)"
        }
        let escapedTitle = title
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
        return """
        <!doctype html>
        <html>
        <head>
        \(policy)
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
