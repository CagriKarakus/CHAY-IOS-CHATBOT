import Foundation

/// Bir GitHub reposundaki (ör. `anthropics/skills` veya bir Claude plugin marketplace'i) `SKILL.md` dosyalarını bulur ve okur.
public enum SkillRepository {
    public struct Found: Equatable, Sendable {
        public let path: String
        public let skill: Skill
    }

    public enum RepositoryError: Error, Equatable, Sendable {
        case invalidName
        case notFound
        case rateLimited
        case http(status: Int)
    }

    private struct Tree: Decodable {
        struct Entry: Decodable {
            let path: String
            let type: String
        }
        let tree: [Entry]
    }

    /// "owner/repo" veya "https://github.com/owner/repo" kabul eder.
    public static func parseRepository(_ input: String) -> (owner: String, repo: String)? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "github.com/"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        if text.hasSuffix(".git") { text = String(text.dropLast(4)) }
        let parts = text.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let owner = parts[0], repo = parts[1]
        guard !owner.isEmpty, !repo.isEmpty,
              !owner.hasPrefix("."), repo != ".", repo != "..",
              owner.unicodeScalars.allSatisfy(allowed.contains),
              repo.unicodeScalars.allSatisfy(allowed.contains)
        else { return nil }
        return (owner, repo)
    }

    /// Repodaki tüm skill'leri (en fazla `limit`) ad sırasıyla döndürür.
    public static func fetchSkills(from input: String, transport: any HTTPTransport, limit: Int = 50) async throws -> [Found] {
        guard let (owner, repo) = parseRepository(input) else { throw RepositoryError.invalidName }

        let tree = try await get("https://api.github.com/repos/\(owner)/\(repo)/git/trees/HEAD?recursive=1", transport: transport)
        guard let entries = try? JSONDecoder().decode(Tree.self, from: tree).tree else { throw RepositoryError.notFound }

        let paths = entries
            .filter { $0.type == "blob" && ($0.path == "SKILL.md" || $0.path.hasSuffix("/SKILL.md")) }
            .map(\.path)
            .prefix(limit)

        var found: [Found] = []
        for path in paths {
            let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
            let data = try await get("https://raw.githubusercontent.com/\(owner)/\(repo)/HEAD/\(encoded)", transport: transport)
            if let skill = Skill.parse(markdown: String(decoding: data, as: UTF8.self)) {
                found.append(Found(path: path, skill: skill))
            }
        }
        return found.sorted { $0.skill.name.localizedStandardCompare($1.skill.name) == .orderedAscending }
    }

    private static func get(_ link: String, transport: any HTTPTransport) async throws -> Data {
        let response = try await transport.send(HTTPRequest(
            url: URL(string: link)!,
            method: "GET",
            headers: ["Accept": "application/vnd.github+json", "User-Agent": "CHAY-iOS"],
            body: nil
        ))
        switch response.statusCode {
        case 200..<300: return response.body
        case 404: throw RepositoryError.notFound
        case 403, 429: throw RepositoryError.rateLimited
        default: throw RepositoryError.http(status: response.statusCode)
        }
    }
}
