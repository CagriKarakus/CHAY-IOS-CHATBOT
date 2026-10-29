/// Sohbetin ait olduğu proje: her sohbette geçerli talimatlar ve bilgi dosyaları.
public struct ProjectContext: Equatable, Sendable {
    public struct Document: Equatable, Sendable {
        public let name: String
        public let text: String

        public init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    public let name: String
    public let instructions: String
    public let documents: [Document]

    /// Dosyaların system prompt'a eklenebilecek toplam karakter sınırı; aşan dosyalar kırpılır veya atlanır.
    public static let knowledgeLimit = 120_000

    public init(name: String, instructions: String, documents: [Document]) {
        self.name = name
        self.instructions = instructions
        self.documents = documents
    }

    /// System prompt'a eklenecek bölüm.
    var promptSection: String {
        var section = "You are working inside the user's project \"\(name)\". Use its instructions and files in every answer."
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            section += "\n\nProject instructions:\n\(trimmed)"
        }
        guard !documents.isEmpty else { return section }

        section += "\n\nProject files:"
        var remaining = Self.knowledgeLimit
        var omitted: [String] = []
        for document in documents {
            guard remaining > 0 else {
                omitted.append(document.name)
                continue
            }
            let text = document.text.count > remaining
                ? String(document.text.prefix(remaining)) + "\n[…truncated]"
                : document.text
            remaining -= min(document.text.count, remaining)
            section += "\n<document name=\"\(document.name)\">\n\(text)\n</document>"
        }
        if !omitted.isEmpty {
            section += "\n(Not included because the project files are too large: \(omitted.joined(separator: ", ")).)"
        }
        return section
    }
}
