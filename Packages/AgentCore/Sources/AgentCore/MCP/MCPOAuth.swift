import Foundation

/// PKCE çifti. Doğrulayıcı rastgele, `challenge` = BASE64URL(SHA256(verifier)); uygulama tarafında üretilir.
public struct PKCE: Sendable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String, challenge: String) {
        self.verifier = verifier
        self.challenge = challenge
    }
}

/// OAuth ile alınmış erişim bilgileri (Keychain'de saklanır).
public struct OAuthCredentials: Codable, Equatable, Sendable {
    public var clientID: String
    public var clientSecret: String?
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date?
    public var tokenEndpoint: URL
    /// İstenen kaynak (MCP sunucusunun adresi); token isteklerinde `resource` olarak gider.
    public var resource: String

    /// Süresi doldu mu (bir dakika pay bırakılır).
    public func isExpired(now: Date = .now) -> Bool {
        expiresAt.map { $0 <= now.addingTimeInterval(60) } ?? false
    }
}

/// Tarayıcıda açılacak, hazırlanmış bir giriş.
public struct OAuthLogin: Sendable {
    public let authorizationURL: URL
    public let state: String
    let verifier: String
    let clientID: String
    let clientSecret: String?
    let tokenEndpoint: URL
    let redirectURI: String
    let resource: String
}

public enum MCPOAuthError: Error, Equatable, Sendable {
    /// Sunucunun giriş (OAuth) bilgileri bulunamadı.
    case discoveryFailed
    /// Sunucu otomatik istemci kaydını desteklemiyor; Client ID elle girilmeli.
    case registrationUnsupported
    case registrationFailed(status: Int, detail: String? = nil)
    /// Tarayıcıdan dönen yanıt bu girişe ait değil.
    case stateMismatch
    /// Kullanıcı reddetti veya sunucu hata döndü.
    case denied(String)
    case tokenFailed(status: Int, message: String?, code: String? = nil)
    /// Token yenilenemiyor; yeniden giriş gerekiyor.
    case loginRequired
}

extension MCPOAuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .discoveryFailed: "The server's sign-in (OAuth) information could not be found."
        case .registrationUnsupported: "The server doesn't support automatic client registration; enter a Client ID."
        case let .registrationFailed(status, _): "Client registration failed (HTTP \(status))."
        case .stateMismatch: "The sign-in response doesn't match this request."
        case .denied: "The service didn't complete the sign-in."
        case let .tokenFailed(status, _, _): "Getting the token failed (HTTP \(status))."
        case .loginRequired: "Signing in again is required."
        }
    }
}

extension MCPOAuthError: ServerDetailError {
    public var serverDetail: String? {
        switch self {
        case let .denied(reason): HTTPResponse.redacted(reason)
        case let .tokenFailed(_, message, _): message.map(HTTPResponse.redacted)
        case let .registrationFailed(_, detail): detail
        default: nil
        }
    }
}

/// MCP yetkilendirme akışı: korunan kaynak ve yetki sunucusu keşfi (RFC 9728, RFC 8414),
/// dinamik istemci kaydı (RFC 7591), PKCE ile yetki kodu ve token yenileme.
public enum MCPOAuth {
    /// Girişi hazırlar: sunucuyu yoklar, yetki sunucusunu bulur, gerekirse istemci kaydeder.
    /// `clientID` verilirse kayıt yapılmaz.
    public static func prepareLogin(
        serverURL: URL,
        redirectURI: String,
        clientName: String,
        clientID: String?,
        clientSecret: String? = nil,
        pkce: PKCE,
        state: String,
        transport: any HTTPTransport
    ) async throws -> OAuthLogin {
        guard serverURL.scheme?.lowercased() == "https" else { throw MCPError.insecureURL }

        // 1-2. Korunan kaynak ve yetki sunucusu bilgisi.
        let probed = await probe(serverURL, transport: transport)
        let found = await discover(serverURL, challenged: probed?.metadata, transport: transport)
        let resource = found.resource
        var metadata = found.metadata
        if metadata == nil, resource == nil {
            metadata = AuthorizationServer(
                authorization_endpoint: origin(of: serverURL).appendingPathComponent("authorize"),
                token_endpoint: origin(of: serverURL).appendingPathComponent("token"),
                registration_endpoint: origin(of: serverURL).appendingPathComponent("register"),
                scopes_supported: nil
            )
        }
        guard let metadata else { throw MCPOAuthError.discoveryFailed }

        // 3. İstemci: elle girilen veya dinamik kayıt.
        var client = (id: clientID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "", secret: clientSecret)
        if client.id.isEmpty {
            guard let endpoint = metadata.registration_endpoint else { throw MCPOAuthError.registrationUnsupported }
            client = try await register(at: endpoint, redirectURI: redirectURI, clientName: clientName, transport: transport)
        }

        // 4. Tarayıcıda açılacak adres.
        let resourceID = resource?.resource ?? canonicalResource(serverURL)
        let scopes = resource?.scopes_supported ?? metadata.scopes_supported
        guard var components = URLComponents(url: metadata.authorization_endpoint, resolvingAgainstBaseURL: false) else {
            throw MCPOAuthError.discoveryFailed
        }
        var items = components.queryItems ?? []
        items += [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: client.id),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "resource", value: resourceID),
        ]
        if let scopes, !scopes.isEmpty {
            items.append(URLQueryItem(name: "scope", value: scopes.joined(separator: " ")))
        }
        components.queryItems = items
        guard let url = components.url else { throw MCPOAuthError.discoveryFailed }

        return OAuthLogin(
            authorizationURL: url,
            state: state,
            verifier: pkce.verifier,
            clientID: client.id,
            clientSecret: client.secret,
            tokenEndpoint: metadata.token_endpoint,
            redirectURI: redirectURI,
            resource: resourceID
        )
    }

    /// Tarayıcıdan dönen adresteki kodu token'a çevirir.
    public static func finishLogin(_ login: OAuthLogin, callback: URL, transport: any HTTPTransport) async throws -> OAuthCredentials {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
        if let error = value("error") {
            throw MCPOAuthError.denied(value("error_description") ?? error)
        }
        guard value("state") == login.state else { throw MCPOAuthError.stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw MCPOAuthError.denied("no code") }

        var form = [
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", login.redirectURI),
            ("client_id", login.clientID),
            ("code_verifier", login.verifier),
            ("resource", login.resource),
        ]
        if let secret = login.clientSecret { form.append(("client_secret", secret)) }
        let token = try await requestToken(login.tokenEndpoint, form: form, transport: transport)
        return OAuthCredentials(
            clientID: login.clientID,
            clientSecret: login.clientSecret,
            accessToken: token.access_token,
            refreshToken: token.refresh_token,
            expiresAt: token.expiresAt,
            tokenEndpoint: login.tokenEndpoint,
            resource: login.resource
        )
    }

    /// Refresh token ile yeni erişim token'ı alır; sunucu yeni refresh token vermezse eskisi korunur.
    public static func refresh(_ credentials: OAuthCredentials, transport: any HTTPTransport) async throws -> OAuthCredentials {
        guard let refreshToken = credentials.refreshToken else { throw MCPOAuthError.loginRequired }
        var form = [
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", credentials.clientID),
            ("resource", credentials.resource),
        ]
        if let secret = credentials.clientSecret { form.append(("client_secret", secret)) }
        let token: TokenResponse
        do {
            token = try await requestToken(credentials.tokenEndpoint, form: form, transport: transport)
        } catch let MCPOAuthError.tokenFailed(status, _, code) where requiresLogin(status: status, code: code) {
            throw MCPOAuthError.loginRequired
        }
        var updated = credentials
        updated.accessToken = token.access_token
        updated.refreshToken = token.refresh_token ?? refreshToken
        updated.expiresAt = token.expiresAt
        return updated
    }

    /// Yenileme gerçekten reddedildi mi: geçici hatalarda (429, sunucu sorunu) kullanıcıdan giriş istenmez.
    private static func requiresLogin(status: Int, code: String?) -> Bool {
        code.map { ["invalid_grant", "invalid_client", "unauthorized_client"].contains($0) } ?? (status == 400 || status == 401)
    }

    // MARK: - Keşif

    /// Sunucunun nasıl giriş istediğini bulur. Tarayıcı girişi için otomatik istemci kaydı gerekir;
    /// yoksa token istenir. Sunucuya ulaşılamazsa veya MCP gibi yanıt vermezse `nil`.
    public static func detectAuth(serverURL: URL, transport: any HTTPTransport) async -> ConnectorAuthKind? {
        guard let probed = await probe(serverURL, transport: transport) else { return nil }
        if (200..<300).contains(probed.status) { return ConnectorAuthKind.none }
        guard probed.status == 401 || probed.status == 403 else { return nil }
        let found = await discover(serverURL, challenged: probed.metadata, transport: transport)
        return found.metadata?.registration_endpoint == nil ? .token : .oauth
    }

    /// Korunan kaynak bilgisi (önce 401 yanıtındaki adres, sonra bilinen yollar) ve yetki sunucusu bilgisi.
    /// Eski sunucularda (kaynak bilgisi yok) MCP sunucusunun kökü kullanılır.
    private static func discover(
        _ serverURL: URL,
        challenged: URL?,
        transport: any HTTPTransport
    ) async -> (resource: ProtectedResource?, metadata: AuthorizationServer?) {
        var resource: ProtectedResource?
        for candidate in [challenged].compactMap({ $0 }).filter(isSecure) + protectedResourceCandidates(for: serverURL) {
            if let found: ProtectedResource = try? await getJSON(candidate, transport: transport),
               !found.authorization_servers.isEmpty, found.describes(serverURL) {
                resource = found
                break
            }
        }
        let issuer = resource?.authorization_servers.compactMap(URL.init(string:)).first(where: isSecure) ?? origin(of: serverURL)
        for candidate in authorizationServerCandidates(for: issuer) {
            if let found: AuthorizationServer = try? await getJSON(candidate, transport: transport), found.isSecure {
                return (resource, found)
            }
        }
        return (resource, nil)
    }

    /// Token'sız bir istek atar: durum kodu ve 401 yanıtındaki kaynak bilgisi adresi.
    static func probe(_ serverURL: URL, transport: any HTTPTransport) async -> (status: Int, metadata: URL?)? {
        let body = try? JSONEncoder().encode(RPCRequest(id: 0, method: "initialize", params: [
            "protocolVersion": .string(MCPClient.protocolVersion),
            "capabilities": [:],
            "clientInfo": ["name": "CHAY", "version": "1.0"],
        ]))
        let request = HTTPRequest(
            url: serverURL,
            method: "POST",
            headers: ["Content-Type": "application/json", "Accept": "application/json, text/event-stream"],
            body: body
        )
        guard let response = try? await transport.send(request) else { return nil }
        return (response.statusCode, MCPClient.resourceMetadataURL(fromChallenge: response.header("www-authenticate")))
    }

    fileprivate static func isSecure(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false
    }

    static func origin(of url: URL) -> URL {
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        return components.url ?? url
    }

    /// Yoldaki son `/` atılmış adres (kaynak kimliği).
    static func canonicalResource(_ url: URL) -> String {
        var text = url.absoluteString
        if let hash = text.firstIndex(of: "#") { text = String(text[..<hash]) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    private static func path(of url: URL) -> String {
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.path ?? ""
        return path == "/" ? "" : (path.hasSuffix("/") ? String(path.dropLast()) : path)
    }

    static func protectedResourceCandidates(for serverURL: URL) -> [URL] {
        let base = origin(of: serverURL).absoluteString + "/.well-known/oauth-protected-resource"
        let path = path(of: serverURL)
        return (path.isEmpty ? [base] : [base + path, base]).compactMap(URL.init(string:))
    }

    static func authorizationServerCandidates(for issuer: URL) -> [URL] {
        let root = origin(of: issuer).absoluteString
        let path = path(of: issuer)
        let candidates = path.isEmpty
            ? [root + "/.well-known/oauth-authorization-server", root + "/.well-known/openid-configuration"]
            : [
                root + "/.well-known/oauth-authorization-server" + path,
                root + "/.well-known/openid-configuration" + path,
                root + path + "/.well-known/openid-configuration",
            ]
        return candidates.compactMap(URL.init(string:))
    }

    // MARK: - İstekler

    private static func register(
        at endpoint: URL,
        redirectURI: String,
        clientName: String,
        transport: any HTTPTransport
    ) async throws -> (id: String, secret: String?) {
        struct Body: Encodable {
            let client_name: String
            let redirect_uris: [String]
            let grant_types = ["authorization_code", "refresh_token"]
            let response_types = ["code"]
            let token_endpoint_auth_method = "none"
        }
        struct Response: Decodable {
            let client_id: String
            let client_secret: String?
        }
        let response = try await transport.send(HTTPRequest(
            url: endpoint,
            method: "POST",
            headers: ["Content-Type": "application/json", "Accept": "application/json"],
            body: try JSONEncoder().encode(Body(client_name: clientName, redirect_uris: [redirectURI]))
        ))
        guard (200..<300).contains(response.statusCode) else {
            throw MCPOAuthError.registrationFailed(status: response.statusCode, detail: response.diagnostic)
        }
        guard let decoded = try? JSONDecoder().decode(Response.self, from: response.body) else {
            throw MCPOAuthError.registrationFailed(status: response.statusCode, detail: response.diagnostic)
        }
        return (decoded.client_id, decoded.client_secret)
    }

    private struct TokenResponse: Decodable {
        enum CodingKeys: String, CodingKey {
            case access_token, refresh_token, expires_in
        }

        let access_token: String
        let refresh_token: String?
        /// Bazı sunucular sayıyı metin olarak yazar; okunamazsa süresiz sayılır.
        let expires_in: LenientInt?

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            access_token = try container.decode(String.self, forKey: .access_token)
            refresh_token = try container.decodeIfPresent(String.self, forKey: .refresh_token)
            expires_in = try? container.decodeIfPresent(LenientInt.self, forKey: .expires_in)
        }

        var expiresAt: Date? {
            expires_in.map { Date.now.addingTimeInterval(TimeInterval($0.value)) }
        }
    }

    private static func requestToken(_ endpoint: URL, form: [(String, String)], transport: any HTTPTransport) async throws -> TokenResponse {
        let body = form.map { "\($0.0)=\(WebSearchTool.formEncoded($0.1))" }.joined(separator: "&")
        let response = try await transport.send(HTTPRequest(
            url: endpoint,
            method: "POST",
            headers: ["Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"],
            body: Data(body.utf8)
        ))
        guard (200..<300).contains(response.statusCode),
              let token = try? JSONDecoder().decode(TokenResponse.self, from: response.body)
        else {
            struct ErrorBody: Decodable {
                let error: String?
                let error_description: String?
            }
            let error = try? JSONDecoder().decode(ErrorBody.self, from: response.body)
            throw MCPOAuthError.tokenFailed(status: response.statusCode, message: error?.error_description ?? error?.error, code: error?.error)
        }
        return token
    }

    private static func getJSON<T: Decodable>(_ url: URL, transport: any HTTPTransport) async throws -> T {
        let response = try await transport.send(HTTPRequest(url: url, method: "GET", headers: ["Accept": "application/json"], body: nil))
        guard (200..<300).contains(response.statusCode) else { throw MCPOAuthError.discoveryFailed }
        return try JSONDecoder().decode(T.self, from: response.body)
    }

    private struct ProtectedResource: Decodable {
        let resource: String?
        let authorization_servers: [String]
        let scopes_supported: [String]?

        /// Bilgi bu sunucuya mı ait; başka bir sitenin yetki sunucusuna yönlendirilmeyelim.
        func describes(_ serverURL: URL) -> Bool {
            resource.map { URL(string: $0)?.host?.lowercased() == serverURL.host?.lowercased() } ?? true
        }
    }

    private struct AuthorizationServer: Decodable {
        let authorization_endpoint: URL
        let token_endpoint: URL
        let registration_endpoint: URL?
        let scopes_supported: [String]?

        /// Token ve kodlar sadece HTTPS üzerinden gider.
        var isSecure: Bool {
            MCPOAuth.isSecure(authorization_endpoint) && MCPOAuth.isSecure(token_endpoint)
                && (registration_endpoint.map(MCPOAuth.isSecure) ?? true)
        }
    }
}

/// OAuth token'ını gerektiğinde yeniler; yenilenen bilgiler `onUpdate` ile saklanır.
public actor OAuthTokenProvider: MCPTokenProvider {
    private var credentials: OAuthCredentials
    private let transport: any HTTPTransport
    private let onUpdate: @Sendable (OAuthCredentials) -> Void
    /// Süren yenileme. Refresh token çoğu sunucuda tek kullanımlıktır; aynı anda iki istek giriş düşürür.
    private var refreshing: Task<OAuthCredentials, any Error>?

    public init(credentials: OAuthCredentials, transport: any HTTPTransport, onUpdate: @escaping @Sendable (OAuthCredentials) -> Void) {
        self.credentials = credentials
        self.transport = transport
        self.onUpdate = onUpdate
    }

    public func token(forceRefresh: Bool) async throws -> String? {
        if forceRefresh || credentials.isExpired() {
            guard credentials.refreshToken != nil else {
                if forceRefresh { throw MCPOAuthError.loginRequired }
                return credentials.accessToken
            }
            if let refreshing {
                credentials = try await refreshing.value
            } else {
                let task = Task { [credentials, transport] in try await MCPOAuth.refresh(credentials, transport: transport) }
                refreshing = task
                defer { refreshing = nil }
                credentials = try await task.value
                onUpdate(credentials)
            }
        }
        return credentials.accessToken
    }
}
