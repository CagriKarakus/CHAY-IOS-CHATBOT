import AgentCore
import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import UIKit

/// Uzak bir MCP sunucusu (bağlayıcı). Token ve OAuth bilgileri Keychain'de, gerisi connectors.json'da.
struct Connector: Codable, Identifiable, Equatable {
    enum Auth: String, Codable, CaseIterable, Identifiable {
        /// Herkese açık sunucu.
        case none
        /// Elle girilen erişim token'ı (Bearer).
        case token
        /// Tarayıcıda giriş (OAuth).
        case oauth

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: L("None", "Yok")
            case .token: L("Access token", "Erişim token'ı")
            case .oauth: L("Sign in with browser", "Tarayıcıyla giriş")
            }
        }
    }

    var id = UUID()
    var name: String
    var url: String
    var auth: Auth = .none
    /// OAuth: sunucu otomatik istemci kaydını desteklemiyorsa elle girilen Client ID.
    var oauthClientID: String?
    /// Yeni sohbetlerde varsayılan olarak açık mı.
    var enabledByDefault = true
    /// Kullanıcının kapattığı araçların adları.
    var disabledTools: [String] = []
    /// Son bağlantıda sunucunun bildirdiği araçlar.
    var tools: [MCPToolInfo] = []
    /// Veri değiştirebilse de sormadan çalışmasına izin verilen araçlar. Eski kayıtlarda yok.
    var alwaysAllowedTools: [String]?

    func isAlwaysAllowed(_ tool: MCPToolInfo) -> Bool {
        alwaysAllowedTools?.contains(tool.name) ?? false
    }

    var enabledTools: [MCPToolInfo] {
        tools.filter { !disabledTools.contains($0.name) }
    }
}

/// Bağlayıcılar, bağlantıları ve girişleri.
@Observable @MainActor
final class ConnectorLibrary {
    static let callbackScheme = "dev.cagri.aiassistant"
    static let redirectURI = "dev.cagri.aiassistant:/oauth/callback"

    private(set) var connectors: [Connector] = []
    /// Token'ı yenilenemeyen, yeniden giriş gereken bağlayıcılar.
    private(set) var needsSignIn: Set<UUID> = []
    /// Son bağlantı hatası (Ayarlar'da gösterilir).
    private(set) var lastErrors: [UUID: String] = [:]
    private var clients: [UUID: MCPClient] = [:]
    private let authenticator = WebAuthenticator()

    private static var fileURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("connectors.json")
    }

    nonisolated private static func tokenKey(_ id: UUID) -> String { "connector.token.\(id.uuidString)" }
    nonisolated private static func oauthKey(_ id: UUID) -> String { "connector.oauth.\(id.uuidString)" }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([Connector].self, from: data) {
            connectors = decoded
        }
    }

    func connector(_ id: UUID) -> Connector? {
        connectors.first { $0.id == id }
    }

    /// Bir sohbetin seçimine göre açık bağlayıcılar; seçim yoksa varsayılan açık olanlar.
    func active(in selection: Set<UUID>?) -> [Connector] {
        connectors.filter { selection?.contains($0.id) ?? $0.enabledByDefault }
    }

    func token(for id: UUID) -> String {
        Keychain.read(Self.tokenKey(id)) ?? ""
    }

    func isSignedIn(_ id: UUID) -> Bool {
        Keychain.read(Self.oauthKey(id)) != nil && !needsSignIn.contains(id)
    }

    /// Kaydeder; adres veya giriş yöntemi değiştiyse eski bağlantı ve giriş bırakılır.
    func save(_ connector: Connector, token: String) {
        var connector = connector
        connector.name = connector.name.trimmingCharacters(in: .whitespacesAndNewlines)
        connector.url = connector.url.trimmingCharacters(in: .whitespacesAndNewlines)
        if let old = self.connector(connector.id), old.url != connector.url || old.auth != connector.auth || old.oauthClientID != connector.oauthClientID {
            Keychain.delete(Self.oauthKey(connector.id))
            if old.url != connector.url { connector.tools = [] }
        }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if connector.auth == .token, !trimmedToken.isEmpty {
            Keychain.save(trimmedToken, for: Self.tokenKey(connector.id))
        } else {
            Keychain.delete(Self.tokenKey(connector.id))
        }
        if let index = connectors.firstIndex(where: { $0.id == connector.id }) {
            connectors[index] = connector
        } else {
            connectors.append(connector)
        }
        clients[connector.id] = nil
        lastErrors[connector.id] = nil
        persist()
    }

    func delete(_ id: UUID) {
        connectors.removeAll { $0.id == id }
        Keychain.delete(Self.tokenKey(id))
        Keychain.delete(Self.oauthKey(id))
        clients[id] = nil
        needsSignIn.remove(id)
        persist()
    }

    func setTool(_ name: String, enabled: Bool, in id: UUID) {
        guard let index = connectors.firstIndex(where: { $0.id == id }) else { return }
        connectors[index].disabledTools.removeAll { $0 == name }
        if !enabled { connectors[index].disabledTools.append(name) }
        persist()
    }

    /// Veri değiştirebilen bir aracın her çalışmadan önce sorup sormayacağı.
    func setAskBeforeRunning(_ ask: Bool, tool name: String, in id: UUID) {
        guard let index = connectors.firstIndex(where: { $0.id == id }) else { return }
        var allowed = connectors[index].alwaysAllowedTools ?? []
        allowed.removeAll { $0 == name }
        if !ask { allowed.append(name) }
        connectors[index].alwaysAllowedTools = allowed
        persist()
    }

    /// Yedekten gelenleri ekler; aynı kimlikte veya adreste bağlayıcı varsa atlar. Token ve girişler yedekte yoktur.
    func importConnectors(_ incoming: [Connector]) -> Int {
        let new = incoming.filter { item in !connectors.contains { $0.id == item.id || $0.url == item.url } }
        connectors += new
        persist()
        return new.count
    }

    func setEnabledByDefault(_ enabled: Bool, for id: UUID) {
        guard let index = connectors.firstIndex(where: { $0.id == id }) else { return }
        connectors[index].enabledByDefault = enabled
        persist()
    }

    /// Sunucuya bağlanıp araç listesini yeniler.
    @discardableResult
    func refreshTools(_ id: UUID) async throws -> [MCPToolInfo] {
        do {
            let tools = try await client(for: id).listTools()
            if let index = connectors.firstIndex(where: { $0.id == id }) {
                connectors[index].tools = tools
                persist()
            }
            lastErrors[id] = nil
            needsSignIn.remove(id)
            return tools
        } catch {
            if case MCPError.unauthorized = error, connector(id)?.auth == .oauth {
                needsSignIn.insert(id)
            }
            lastErrors[id] = connectorErrorMessage(error)
            clients[id] = nil
            throw error
        }
    }

    /// Tarayıcıda giriş yapar, token'ı saklar ve araçları yükler.
    func signIn(_ id: UUID) async throws {
        guard let connector = connector(id), let url = URL(string: connector.url) else { throw MCPError.insecureURL }
        let transport = URLSessionTransport()
        let login = try await MCPOAuth.prepareLogin(
            serverURL: url,
            redirectURI: Self.redirectURI,
            clientName: "CHAY",
            clientID: connector.oauthClientID,
            pkce: Self.makePKCE(),
            state: UUID().uuidString,
            transport: transport
        )
        let callback = try await authenticator.authenticate(url: login.authorizationURL, callbackScheme: Self.callbackScheme)
        let credentials = try await MCPOAuth.finishLogin(login, callback: callback, transport: transport)
        Self.store(credentials, for: id)
        clients[id] = nil
        needsSignIn.remove(id)
        lastErrors[id] = nil
        try await refreshTools(id)
    }

    func signOut(_ id: UUID) {
        Keychain.delete(Self.oauthKey(id))
        clients[id] = nil
    }

    /// Sohbette kullanılacak araçlar. Araç listesi hiç alınmamış bağlayıcılara önce bağlanılır; bağlanamayanlar atlanır.
    func tools(in selection: Set<UUID>?) async -> [any Tool] {
        var tools: [any Tool] = []
        var taken = Set<String>()
        for connector in active(in: selection) {
            if connector.tools.isEmpty {
                _ = try? await refreshTools(connector.id)
            }
            guard let current = self.connector(connector.id), let client = try? client(for: current.id) else { continue }
            for info in current.enabledTools {
                let name = MCPTool.exposedName(server: current.name, tool: info.name, taken: taken)
                taken.insert(name)
                tools.append(MCPTool(info: info, exposedName: name, serverName: current.name, client: client,
                                     alwaysAllowed: current.isAlwaysAllowed(info)))
            }
        }
        return tools
    }

    private func client(for id: UUID) throws -> MCPClient {
        if let client = clients[id] { return client }
        guard let connector = connector(id), let url = URL(string: connector.url) else { throw MCPError.insecureURL }
        let transport = URLSessionTransport()
        let tokens: any MCPTokenProvider
        switch connector.auth {
        case .none:
            tokens = StaticToken(nil)
        case .token:
            tokens = StaticToken(token(for: id))
        case .oauth:
            if let saved = Keychain.read(Self.oauthKey(id)),
               let credentials = try? JSONDecoder().decode(OAuthCredentials.self, from: Data(saved.utf8)) {
                tokens = OAuthTokenProvider(credentials: credentials, transport: transport) { updated in
                    Self.store(updated, for: id)
                }
            } else {
                tokens = StaticToken(nil)
            }
        }
        let client = try MCPClient(url: url, transport: transport, tokens: tokens)
        clients[id] = client
        return client
    }

    nonisolated private static func store(_ credentials: OAuthCredentials, for id: UUID) {
        if let data = try? JSONEncoder().encode(credentials) {
            Keychain.save(String(decoding: data, as: UTF8.self), for: oauthKey(id))
        }
    }

    /// Rastgele doğrulayıcı ve SHA-256 özeti (base64url).
    private static func makePKCE() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URL(Data(bytes))
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        return PKCE(verifier: verifier, challenge: challenge)
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func persist() {
        try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(connectors) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}

/// Bağlayıcı hatalarının kullanıcıya gösterilen açıklaması.
func connectorErrorMessage(_ error: any Error) -> String {
    switch error {
    case MCPError.insecureURL:
        L("The address must start with https://.", "Adres https:// ile başlamalı.")
    case MCPError.unauthorized:
        L("The server requires signing in, or the token is invalid.", "Sunucu giriş istiyor veya token geçersiz.")
    case let MCPError.http(status):
        L("The server returned HTTP \(status).", "Sunucu HTTP \(status) döndürdü.")
    case MCPError.invalidResponse:
        L("The server didn't respond like an MCP server. Check the address.", "Sunucu bir MCP sunucusu gibi yanıt vermedi. Adresi kontrol et.")
    case MCPOAuthError.discoveryFailed:
        L("The server's sign-in information couldn't be found. It may not support browser sign-in; try an access token.",
          "Sunucunun giriş bilgileri bulunamadı. Tarayıcıyla girişi desteklemiyor olabilir; erişim token'ı dene.")
    case MCPOAuthError.registrationUnsupported:
        L("The server doesn't allow automatic registration. Enter a Client ID from the service's developer settings.",
          "Sunucu otomatik kayda izin vermiyor. Servisin geliştirici ayarlarından aldığın Client ID'yi gir.")
    case MCPOAuthError.loginRequired:
        L("Sign in again.", "Yeniden giriş yap.")
    case let error as ASWebAuthenticationSessionError where error.code == .canceledLogin:
        L("Sign-in was cancelled.", "Giriş iptal edildi.")
    case let error as URLError:
        L("Couldn't reach the server (\(error.localizedDescription)).", "Sunucuya ulaşılamadı (\(error.localizedDescription)).")
    default:
        error.localizedDescription
    }
}

/// Giriş sayfasını uygulama içi güvenli tarayıcıda açar ve dönüş adresini bekler.
@MainActor
final class WebAuthenticator: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? ASWebAuthenticationSessionError(.canceledLogin))
                }
            }
            session.presentationContextProvider = self
            // Tarayıcıdaki mevcut oturumlar kullanılsın (servise tekrar şifre girmek gerekmesin).
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let windows = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
            return windows.first { $0.isKeyWindow } ?? windows.first ?? ASPresentationAnchor()
        }
    }
}
