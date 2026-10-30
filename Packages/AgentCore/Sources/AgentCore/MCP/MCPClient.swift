import Foundation

/// MCP sunucusunun bir aracı (`tools/list`).
public struct MCPToolInfo: Codable, Equatable, Sendable {
    public let name: String
    public let title: String?
    public let description: String?
    public let inputSchema: JSONValue?
    /// Sunucu aracı "sadece okur" diye işaretlediyse `true`; işaret yoksa veri değiştirebilir sayılır.
    public let readOnly: Bool

    public init(name: String, title: String? = nil, description: String? = nil, inputSchema: JSONValue? = nil, readOnly: Bool = false) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
        self.readOnly = readOnly
    }
}

public enum MCPError: Error, Equatable, Sendable {
    case insecureURL
    /// Sunucu giriş istiyor. `resourceMetadata`: 401 yanıtındaki OAuth bilgi adresi.
    case unauthorized(resourceMetadata: URL?)
    case http(status: Int, detail: String? = nil)
    case rpc(code: Int, message: String)
    case invalidResponse(detail: String? = nil)
    /// Araç çalıştı ama hata döndürdü (`isError`).
    case toolFailed(String)
}

extension MCPError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .insecureURL: "The connector address must start with https://."
        case .unauthorized: "The connector requires signing in again. The user can do it in Settings > Connectors."
        case let .http(status, _): "Connector HTTP error \(status)."
        case let .rpc(code, _): "Connector error \(code)."
        case .invalidResponse: "The server's response isn't a valid MCP response."
        case .toolFailed: "The tool returned an error."
        }
    }
}

extension MCPError: ServerDetailError {
    public var serverDetail: String? {
        switch self {
        case let .http(_, detail), let .invalidResponse(detail): detail
        case let .rpc(_, message), let .toolFailed(message): message
        default: nil
        }
    }
}

/// MCP isteklerine eklenecek Bearer token'ı sağlar.
public protocol MCPTokenProvider: Sendable {
    /// `nil`: token olmadan bağlan. `forceRefresh`: sunucu 401 verdi; yenilenmiş bir token denenmeli
    /// (yenilenemiyorsa `nil` döner veya hata fırlatır).
    func token(forceRefresh: Bool) async throws -> String?
}

/// Sabit token (veya hiç token). Sunucu reddederse yenilenemez.
public struct StaticToken: MCPTokenProvider {
    private let value: String?

    public init(_ value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.value = trimmed?.isEmpty == false ? trimmed : nil
    }

    public func token(forceRefresh: Bool) async throws -> String? {
        forceRefresh ? nil : value
    }
}

/// Uzak MCP sunucusu istemcisi (Streamable HTTP, JSON-RPC 2.0). Oturumu ilk istekte açar.
public actor MCPClient {
    public static let protocolVersion = "2025-06-18"

    private let url: URL
    private let transport: any HTTPTransport
    private let tokens: any MCPTokenProvider
    private var sessionID: String?
    private var negotiatedVersion: String?
    private var initialized = false
    private var nextID = 1

    public init(url: URL, transport: any HTTPTransport, tokens: any MCPTokenProvider = StaticToken(nil)) throws {
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false else { throw MCPError.insecureURL }
        self.url = url
        self.transport = transport
        self.tokens = tokens
    }

    public func listTools() async throws -> [MCPToolInfo] {
        try await ensureInitialized()
        var tools: [MCPToolInfo] = []
        var cursor: String?
        repeat {
            let params: JSONValue = cursor.map { ["cursor": .string($0)] } ?? [:]
            let page = try Self.decode(ToolsPage.self, from: try await request("tools/list", params: params))
            tools += page.tools.map(\.info)
            cursor = page.nextCursor
        } while cursor != nil && tools.count < 500
        return tools
    }

    /// Aracı çalıştırır ve sonucunu metin olarak döndürür. `arguments` modelin ürettiği JSON'dur.
    public func callTool(_ name: String, arguments: String) async throws -> String {
        try await ensureInitialized()
        // Bozuk argümanlar boş sayılıp araç yanlış çalıştırılmasın.
        let json = arguments.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "{}" : arguments
        guard let parsed = try? JSONDecoder().decode(JSONValue.self, from: Data(json.utf8)), case .object = parsed else {
            throw ToolError.invalidArguments
        }
        let result = try Self.decode(CallResult.self, from: try await request("tools/call", params: ["name": .string(name), "arguments": parsed]))
        if result.isError == true { throw MCPError.toolFailed(result.text) }
        return result.text
    }

    private func ensureInitialized() async throws {
        guard !initialized else { return }
        let result = try await request("initialize", params: [
            "protocolVersion": .string(Self.protocolVersion),
            "capabilities": [:],
            "clientInfo": ["name": "CHAY", "version": "1.0"],
        ])
        negotiatedVersion = (try? Self.decode(InitializeResult.self, from: result))?.protocolVersion ?? Self.protocolVersion
        initialized = true
        let notification = try JSONEncoder().encode(RPCNotification(method: "notifications/initialized"))
        _ = try? await post(notification)
    }

    private func request(_ method: String, params: JSONValue, isRetry: Bool = false) async throws -> JSONValue {
        let id = nextID
        nextID += 1
        let body = try JSONEncoder().encode(RPCRequest(id: id, method: method, params: params))
        let response = try await post(body)

        // Oturumun süresi dolduysa sunucu 404 döner: yeni oturum açıp bir kez tekrar dene.
        if response.statusCode == 404, sessionID != nil, method != "initialize", !isRetry {
            sessionID = nil
            initialized = false
            try await ensureInitialized()
            return try await request(method, params: params, isRetry: true)
        }
        guard (200..<300).contains(response.statusCode) else {
            throw MCPError.http(status: response.statusCode, detail: response.diagnostic)
        }
        if method == "initialize", let session = response.header("mcp-session-id") {
            sessionID = session
        }
        let message = try Self.responseMessage(in: response, id: id)
        if let error = message.error {
            throw MCPError.rpc(code: error.code, message: error.message)
        }
        return message.result ?? .null
    }

    /// İsteği gönderir; 401'de token bir kez yenilenip tekrar denenir.
    private func post(_ body: Data) async throws -> HTTPResponse {
        let response = try await transport.send(httpRequest(body, token: try await tokens.token(forceRefresh: false)))
        guard response.statusCode == 401 else { return response }
        let metadata = Self.resourceMetadataURL(fromChallenge: response.header("www-authenticate"))
        // Sadece gerçekten giriş gerekiyorsa "yeniden giriş yap" denir; bağlantı sorunları olduğu gibi iletilir.
        let fresh: String?
        do {
            fresh = try await tokens.token(forceRefresh: true)
        } catch MCPOAuthError.loginRequired {
            fresh = nil
        }
        guard let fresh else { throw MCPError.unauthorized(resourceMetadata: metadata) }
        let retried = try await transport.send(httpRequest(body, token: fresh))
        if retried.statusCode == 401 { throw MCPError.unauthorized(resourceMetadata: metadata) }
        return retried
    }

    private func httpRequest(_ body: Data, token: String?) -> HTTPRequest {
        var headers = [
            "Content-Type": "application/json",
            "Accept": "application/json, text/event-stream",
        ]
        if let sessionID { headers["Mcp-Session-Id"] = sessionID }
        if initialized, let negotiatedVersion { headers["MCP-Protocol-Version"] = negotiatedVersion }
        if let token { headers["Authorization"] = "Bearer \(token)" }
        return HTTPRequest(url: url, method: "POST", headers: headers, body: body)
    }

    // MARK: - Ayrıştırma

    /// Yanıttaki (JSON veya SSE akışı) bu isteğe ait JSON-RPC mesajı.
    static func responseMessage(in response: HTTPResponse, id: Int) throws -> RPCResponse {
        let messages = response.contentType?.lowercased().contains("text/event-stream") == true
            ? sseMessages(String(decoding: response.body, as: UTF8.self))
            : [response.body]
        for data in messages {
            guard let message = try? JSONDecoder().decode(RPCResponse.self, from: data) else { continue }
            if message.id == .number(Double(id)) || message.id == .string(String(id)) {
                return message
            }
        }
        throw MCPError.invalidResponse(detail: response.diagnostic)
    }

    /// SSE gövdesindeki olayların `data:` içerikleri (çok satırlı veri birleştirilir).
    static func sseMessages(_ text: String) -> [Data] {
        var messages: [Data] = []
        var buffer: [String] = []
        func flush() {
            if !buffer.isEmpty { messages.append(Data(buffer.joined(separator: "\n").utf8)) }
            buffer = []
        }
        // Swift "\r\n"yi tek karakter sayar; önce tek biçime çevrilir (sunucular ikisini de kullanır).
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("data:") {
                let value = line.dropFirst(5)
                buffer.append(String(value.hasPrefix(" ") ? value.dropFirst() : value))
            }
        }
        flush()
        return messages
    }

    /// `WWW-Authenticate: Bearer resource_metadata="https://…"` içindeki adres.
    static func resourceMetadataURL(fromChallenge header: String?) -> URL? {
        guard let header,
              let range = header.range(of: #"resource_metadata="([^"]+)""#, options: .regularExpression)
        else { return nil }
        let value = header[range].dropFirst("resource_metadata=\"".count).dropLast()
        return URL(string: String(value))
    }

    static func decode<T: Decodable>(_ type: T.Type, from value: JSONValue) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: try JSONEncoder().encode(value))
        } catch {
            throw MCPError.invalidResponse(detail: "Unexpected result format for \(T.self).")
        }
    }
}

// MARK: - JSON-RPC kabı

struct RPCRequest: Encodable {
    let jsonrpc = "2.0"
    let id: Int
    let method: String
    let params: JSONValue
}

struct RPCNotification: Encodable {
    let jsonrpc = "2.0"
    let method: String
}

struct RPCResponse: Decodable {
    struct ErrorBody: Decodable {
        let code: Int
        let message: String
    }

    let id: JSONValue?
    let result: JSONValue?
    let error: ErrorBody?
}

private struct InitializeResult: Decodable {
    let protocolVersion: String?
}

private struct ToolsPage: Decodable {
    struct Item: Decodable {
        struct Annotations: Decodable {
            let title: String?
            let readOnlyHint: Bool?
        }

        let name: String
        let title: String?
        let description: String?
        let inputSchema: JSONValue?
        let annotations: Annotations?

        var info: MCPToolInfo {
            MCPToolInfo(
                name: name,
                title: title ?? annotations?.title,
                description: description,
                inputSchema: inputSchema,
                readOnly: annotations?.readOnlyHint ?? false
            )
        }
    }

    let tools: [Item]
    let nextCursor: String?
}

private struct CallResult: Decodable {
    struct Item: Decodable {
        struct Resource: Decodable {
            let uri: String?
            let text: String?
        }

        let type: String
        let text: String?
        let mimeType: String?
        let uri: String?
        let name: String?
        let resource: Resource?
    }

    let content: [Item]?
    let structuredContent: JSONValue?
    let isError: Bool?

    /// Modele gidecek metin: metin parçaları; görsel gibi ikili içerikler yalnızca adıyla.
    var text: String {
        let parts = (content ?? []).map { item -> String in
            switch item.type {
            case "text": item.text ?? ""
            case "resource": item.resource?.text ?? "[resource: \(item.resource?.uri ?? "")]"
            case "resource_link": "\(item.name ?? "link"): \(item.uri ?? "")"
            default: "[\(item.type)\(item.mimeType.map { " \($0)" } ?? "")]"
            }
        }.filter { !$0.isEmpty }
        if parts.isEmpty, let structuredContent,
           let data = try? JSONEncoder.sorted.encode(structuredContent) {
            return String(decoding: data, as: UTF8.self)
        }
        return parts.joined(separator: "\n\n")
    }
}

extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
