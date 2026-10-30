import Foundation

/// Bağlayıcı adresi bulur: önce doğrulanmış liste, sonra resmi MCP kataloğu.
public struct FindConnectorTool: Tool {
    private struct Arguments: Decodable {
        let query: String
    }

    /// Katalogdan modele gösterilen en fazla sonuç.
    static let registryResultLimit = 5

    public let name = "find_connector"
    public let description = "Finds the address of a remote MCP connector for a service. Use it when the user wants to connect a service (e.g. GitHub, Notion, Jira). Then call connect_connector."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "query": ["type": "string", "description": "Service name, e.g. GitHub"],
        ],
        "required": ["query"],
    ]

    private let transport: any HTTPTransport

    public init(transport: any HTTPTransport) {
        self.transport = transport
    }

    public func activityDetail(for arguments: String) -> String? {
        (try? decodeArguments(Arguments.self, from: arguments))?.query
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let query = try decodeArguments(Arguments.self, from: arguments).query

        let verified = ConnectorCatalog.matches(query)
        if !verified.isEmpty {
            let listing = verified.map { entry in
                var line = "- \(entry.name): \(entry.url) (sign-in: \(entry.auth.rawValue))"
                if let note = entry.note { line += ". \(note)" }
                return line
            }.joined(separator: "\n")
            return ToolOutput(content: "Verified connectors. Call connect_connector with the URL:\n\(listing)")
        }

        let found = (try? await ConnectorRegistry.search(query, transport: transport)) ?? []
        guard !found.isEmpty else {
            return ToolOutput(content: "No connector found for '\(query)'. Search the web with web_search for the service's official remote MCP server URL (Streamable HTTP over https). If you find one on the service's own site, call connect_connector with source \"web\". If not, tell the user.")
        }
        let listing = found.prefix(Self.registryResultLimit).map { result in
            "- \(result.name): \(result.url)\(result.requiresKey ? " (needs a key)" : "")\n  \(result.description)"
        }.joined(separator: "\n")
        return ToolOutput(content: untrustedContent(
            "Unverified results from the public MCP registry. Anyone can publish there:\n\(listing)",
            source: "mcp registry: \(query)"
        ) + "\nIf one clearly belongs to the service the user asked for, call connect_connector with source \"registry\". If none does, use web_search to find the official one.")
    }
}
