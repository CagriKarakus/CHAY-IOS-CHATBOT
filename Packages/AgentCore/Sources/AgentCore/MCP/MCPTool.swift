import Foundation

/// Bir MCP sunucusunun aracını modele normal bir araç olarak sunar.
public struct MCPTool: Tool {
    /// Tek araç sonucunun modele giden en fazla uzunluğu.
    static let outputLimit = 20_000

    public let name: String
    public let description: String
    public let parameters: JSONValue
    /// Sadece okuyan araçlar doğrudan çalışır; diğerleri her seferinde kullanıcıya sorulur.
    public let requiresApproval: Bool

    private let info: MCPToolInfo
    private let serverName: String
    private let client: MCPClient

    public init(info: MCPToolInfo, exposedName: String, serverName: String, client: MCPClient) {
        self.info = info
        self.serverName = serverName
        self.client = client
        name = exposedName
        description = "[\(serverName) connector] " + (info.description ?? info.title ?? info.name)
        if case let .object(schema)? = info.inputSchema, schema["type"] == "object" {
            parameters = info.inputSchema!
        } else {
            parameters = ["type": "object", "properties": [:]]
        }
        requiresApproval = !info.readOnly
    }

    public func activityDetail(for arguments: String) -> String? {
        "\(serverName) · \(info.title ?? info.name)"
    }

    public func run(arguments: String) async throws -> ToolOutput {
        var text = try await client.callTool(info.name, arguments: arguments)
        if text.count > Self.outputLimit {
            text = String(text.prefix(Self.outputLimit)) + "\n[…truncated]"
        }
        return ToolOutput(content: untrustedContent(text, source: "\(serverName) · \(info.name)"))
    }

    /// Modele gidecek araç adı: `mcp_<sunucu>_<araç>`, yalnızca [a-zA-Z0-9_-], en fazla 64 karakter.
    /// Çakışırsa sonuna sayı eklenir.
    public static func exposedName(server: String, tool: String, taken: Set<String>) -> String {
        func clean(_ text: String) -> String {
            String(text.unicodeScalars.map { scalar in
                scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-")
                    ? Character(scalar) : "_"
            })
        }
        let prefix = "mcp_" + clean(server.lowercased()).prefix(16) + "_"
        let base = String((prefix + clean(tool)).prefix(64))
        var candidate = base
        var counter = 2
        while taken.contains(candidate) {
            let suffix = "_\(counter)"
            candidate = String(base.prefix(64 - suffix.count)) + suffix
            counter += 1
        }
        return candidate
    }
}
