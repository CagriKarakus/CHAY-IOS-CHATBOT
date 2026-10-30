import Foundation

/// Bir bağlayıcının giriş yöntemi.
public enum ConnectorAuthKind: String, Codable, Equatable, Sendable {
    case none, token, oauth
}

/// Bağlayıcı adresinin nereden geldiği; kurulum penceresinde gösterilir.
public enum ConnectorSource: String, Codable, Equatable, Sendable {
    /// Uygulamadaki doğrulanmış liste.
    case verified
    /// Resmi MCP kataloğu; herkes yayınlayabildiği için doğrulanmamış sayılır.
    case registry
    /// Web araması; doğrulanmamış.
    case web
}

/// Sohbetten eklenecek bağlayıcı adreslerinin güvenlik kontrolü.
public enum ConnectorAddress {
    /// Sadece internetteki HTTPS adresleri: yerel ağ, kullanıcı adı içeren veya IPv6 adresler reddedilir.
    /// `fetch_page` de bunu kullanır.
    public static func validated(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "https",
              components.user == nil, components.password == nil,
              let host = components.host?.lowercased(), !host.isEmpty,
              !host.contains(":"), !isPrivate(host),
              let url = components.url
        else { return nil }
        return url
    }

    /// Karşılaştırma için: küçük harf, sonda `/` ve `#` yok.
    public static func normalized(_ text: String) -> String {
        guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return text.lowercased() }
        return MCPOAuth.canonicalResource(url).lowercased()
    }

    private static func isPrivate(_ rawHost: String) -> Bool {
        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        if host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") || host.hasSuffix(".internal") {
            return true
        }
        // Tek sayı veya onaltılık yazılmış IP adresi (2130706433 = 127.0.0.1).
        if Int(host) != nil || host.hasPrefix("0x") { return true }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, host.split(separator: ".").count == 4 else { return false }
        return parts[0] == 0 || parts[0] == 10 || parts[0] == 127
            || (parts[0] == 100 && (64...127).contains(parts[1]))
            || (parts[0] == 169 && parts[1] == 254)
            || (parts[0] == 172 && (16...31).contains(parts[1]))
            || (parts[0] == 192 && parts[1] == 168)
    }
}

/// Doğrulanmış bir bağlayıcı.
public struct ConnectorCatalogEntry: Equatable, Sendable {
    public let name: String
    public let aliases: [String]
    public let url: String
    public let auth: ConnectorAuthKind
    /// Token gerekiyorsa kullanıcının token oluşturacağı sayfa.
    public let tokenURL: String?
    /// Modele verilen kısa not.
    public let note: String?

    init(_ name: String, aliases: [String] = [], url: String, auth: ConnectorAuthKind, tokenURL: String? = nil, note: String? = nil) {
        self.name = name
        self.aliases = aliases
        self.url = url
        self.auth = auth
        self.tokenURL = tokenURL
        self.note = note
    }
}

/// Canlı olarak kontrol edilmiş uzak MCP sunucuları (giriş yöntemleri sunucunun bildirdiği bilgilere göre).
public enum ConnectorCatalog {
    public static let entries: [ConnectorCatalogEntry] = [
        ConnectorCatalogEntry("DeepWiki", aliases: ["devin"], url: "https://mcp.deepwiki.com/mcp", auth: .none,
                              note: "Reads the documentation of public GitHub repositories."),
        ConnectorCatalogEntry("GitHub", url: "https://api.githubcopilot.com/mcp/", auth: .token,
                              tokenURL: "https://github.com/settings/personal-access-tokens/new",
                              note: "Needs a personal access token; automatic browser sign-in isn't available for this server."),
        ConnectorCatalogEntry("Notion", url: "https://mcp.notion.com/mcp", auth: .oauth),
        ConnectorCatalogEntry("Linear", url: "https://mcp.linear.app/mcp", auth: .oauth),
        ConnectorCatalogEntry("Atlassian", aliases: ["jira", "confluence"], url: "https://mcp.atlassian.com/v1/mcp", auth: .oauth),
        ConnectorCatalogEntry("Sentry", url: "https://mcp.sentry.dev/mcp", auth: .oauth),
        ConnectorCatalogEntry("Stripe", url: "https://mcp.stripe.com", auth: .oauth),
        ConnectorCatalogEntry("Asana", url: "https://mcp.asana.com/mcp", auth: .oauth),
        ConnectorCatalogEntry("PayPal", url: "https://mcp.paypal.com/mcp", auth: .oauth),
        ConnectorCatalogEntry("Cloudflare", url: "https://mcp.cloudflare.com/mcp", auth: .oauth),
        ConnectorCatalogEntry("Vercel", url: "https://mcp.vercel.com", auth: .oauth),
        ConnectorCatalogEntry("Supabase", url: "https://mcp.supabase.com/mcp", auth: .oauth),
        ConnectorCatalogEntry("Figma", url: "https://mcp.figma.com/mcp", auth: .oauth),
    ]

    /// Aramayla eşleşen kayıtlar ("github mcp", "jira bağlayıcısı" gibi).
    public static func matches(_ query: String) -> [ConnectorCatalogEntry] {
        let words = Set(query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
        let text = query.lowercased()
        return entries.filter { entry in
            ([entry.name] + entry.aliases).contains { name in
                let name = name.lowercased()
                return words.contains(name) || text.contains(name)
            }
        }
    }

    /// Adres doğrulanmış listede mi. Kaynağı model değil bu kontrol belirler.
    public static func entry(forURL url: String) -> ConnectorCatalogEntry? {
        let target = ConnectorAddress.normalized(url)
        return entries.first { ConnectorAddress.normalized($0.url) == target }
    }
}
