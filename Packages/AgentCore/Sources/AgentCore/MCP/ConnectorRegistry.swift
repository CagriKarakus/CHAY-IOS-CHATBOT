import Foundation

/// Resmi MCP kataloğundaki uzak sunucu. Herkes yayınlayabildiği için içeriği güvenilmez veridir.
public struct ConnectorRegistryResult: Equatable, Sendable {
    public let name: String
    public let description: String
    public let url: String
    /// Sunucu zorunlu bir başlık (API key) istiyor.
    public let requiresKey: Bool
}

/// registry.modelcontextprotocol.io araması.
public enum ConnectorRegistry {
    static let endpoint = "https://registry.modelcontextprotocol.io/v0/servers"

    public static func search(_ query: String, limit: Int = 20, transport: any HTTPTransport) async throws -> [ConnectorRegistryResult] {
        guard var components = URLComponents(string: endpoint) else { throw ToolError.invalidURL }
        components.queryItems = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        guard let url = components.url else { throw ToolError.invalidURL }
        let response = try await transport.send(HTTPRequest(url: url, method: "GET", headers: ["Accept": "application/json"], body: nil))
        guard (200..<300).contains(response.statusCode) else { throw ToolError.http(status: response.statusCode) }
        return parse(response.body)
    }

    /// Sadece etkin, son sürüm ve Streamable HTTP uzak sunucular; aynı adres bir kez.
    static func parse(_ data: Data) -> [ConnectorRegistryResult] {
        guard let page = try? JSONDecoder().decode(Page.self, from: data) else { return [] }
        var seen = Set<String>()
        var results: [ConnectorRegistryResult] = []
        for entry in page.servers {
            guard entry.meta?.official?.status == "active", entry.meta?.official?.isLatest == true else { continue }
            for remote in entry.server.remotes ?? [] where remote.type == "streamable-http" {
                // `{tenant}` gibi şablonlu adresler kullanıcıya özeldir; bağlanılamaz.
                guard !remote.url.contains("{"), ConnectorAddress.validated(remote.url) != nil,
                      seen.insert(ConnectorAddress.normalized(remote.url)).inserted
                else { continue }
                results.append(ConnectorRegistryResult(
                    name: entry.server.title ?? entry.server.name,
                    description: entry.server.description ?? "",
                    url: remote.url,
                    requiresKey: (remote.headers ?? []).contains { $0.isRequired == true }
                ))
            }
        }
        return results
    }

    private struct Page: Decodable {
        struct Entry: Decodable {
            struct Server: Decodable {
                struct Remote: Decodable {
                    struct Header: Decodable {
                        let isRequired: Bool?
                    }

                    let type: String
                    let url: String
                    let headers: [Header]?
                }

                let name: String
                let title: String?
                let description: String?
                let remotes: [Remote]?
            }

            struct Meta: Decodable {
                struct Official: Decodable {
                    let status: String?
                    let isLatest: Bool?
                }

                let official: Official?

                enum CodingKeys: String, CodingKey {
                    case official = "io.modelcontextprotocol.registry/official"
                }
            }

            let server: Server
            let meta: Meta?

            enum CodingKeys: String, CodingKey {
                case server
                case meta = "_meta"
            }
        }

        let servers: [Entry]
    }
}
