import Foundation

/// Kullanıcıya kurulum penceresinde gösterilecek bağlayıcı önerisi.
public struct ConnectorProposal: Equatable, Sendable {
    public let name: String
    public let url: String
    public let source: ConnectorSource
    public let auth: ConnectorAuthKind
    /// Token oluşturma sayfası (https).
    public let tokenURL: String?
}

/// Kurulumun sonucu. Bilerek sır taşımaz: modele sadece bu bilgi döner.
public enum ConnectorSetupResult: Equatable, Sendable {
    case connected(toolCount: Int)
    /// Bağlayıcı bu sohbette zaten açık.
    case alreadyConnected(toolCount: Int)
    case declined
    case failed(String)
}

/// Bağlayıcıyı kullanıcının onayıyla ekler. Token bu araçtan geçmez: kullanıcı onu uygulamanın
/// güvenli penceresine yazar; o pencere de otomatik geçilemez.
public struct ConnectConnectorTool: Tool {
    private struct Arguments: Decodable {
        let name: String
        let url: String
        let source: String?
        let token_url: String?
    }

    public typealias Setup = @Sendable (ConnectorProposal) async -> ConnectorSetupResult

    public let name = "connect_connector"
    public let description = "Starts connecting a remote MCP connector. The app shows the user a secure confirmation window and handles any token or browser sign-in there. Never ask for tokens in chat. The connector's tools become available right after it succeeds."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "name": ["type": "string", "description": "Service name shown to the user, e.g. GitHub"],
            "url": ["type": "string", "description": "The https address of the MCP server"],
            "source": ["type": "string", "enum": ["registry", "web"], "description": "Where you found the address, if find_connector didn't list it as verified"],
            "token_url": ["type": "string", "description": "Optional https page where the user can create a token"],
        ],
        "required": ["name", "url"],
    ]

    private let transport: any HTTPTransport
    private let setup: Setup

    public init(transport: any HTTPTransport, setup: @escaping Setup) {
        self.transport = transport
        self.setup = setup
    }

    public func activityDetail(for arguments: String) -> String? {
        (try? decodeArguments(Arguments.self, from: arguments))?.name
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let arguments = try decodeArguments(Arguments.self, from: arguments)
        guard let url = ConnectorAddress.validated(arguments.url) else { throw ToolError.invalidURL }

        let proposal: ConnectorProposal
        // Kaynağı model belirleyemez: "doğrulanmış" sadece listedeki adresler için geçerlidir.
        if let entry = ConnectorCatalog.entry(forURL: url.absoluteString) {
            proposal = ConnectorProposal(name: entry.name, url: entry.url, source: .verified, auth: entry.auth, tokenURL: entry.tokenURL)
        } else {
            guard let auth = await MCPOAuth.detectAuth(serverURL: url, transport: transport) else {
                return ToolOutput(content: "Couldn't reach \(url.absoluteString) as an MCP server. Check the address or tell the user.")
            }
            proposal = ConnectorProposal(
                name: arguments.name,
                url: url.absoluteString,
                source: arguments.source == ConnectorSource.registry.rawValue ? .registry : .web,
                auth: auth,
                tokenURL: arguments.token_url.flatMap(ConnectorAddress.validated)?.absoluteString
            )
        }

        switch await setup(proposal) {
        case let .connected(count):
            return ToolOutput(content: "\(proposal.name) is connected with \(count) tools. Its tools are available now; continue the user's request.")
        case let .alreadyConnected(count):
            return ToolOutput(content: "\(proposal.name) is already connected with \(count) tools.")
        case .declined:
            return ToolOutput(content: "The user declined this connection; do not retry it.")
        case let .failed(reason):
            return ToolOutput(content: "Connecting \(proposal.name) failed: \(reason)")
        }
    }
}
