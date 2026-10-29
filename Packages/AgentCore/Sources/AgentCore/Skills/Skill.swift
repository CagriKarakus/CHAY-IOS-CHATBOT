import Foundation

/// Agent Skills biçimindeki bir skill: `SKILL.md` = YAML ön bilgi (name, description) + talimatlar.
/// Modele sadece ad ve açıklama gider; model gerektiğinde `use_skill` ile talimatın tamamını yükler.
public struct Skill: Codable, Equatable, Sendable {
    public var name: String
    public var description: String
    public var instructions: String

    public init(name: String, description: String, instructions: String) {
        self.name = name
        self.description = description
        self.instructions = instructions
    }

    /// `SKILL.md` içeriğini ayrıştırır; `name` ve `description` yoksa `nil`.
    /// Basit `anahtar: değer` satırları ve `>`/`|` ile başlayan çok satırlı değerler desteklenir.
    public static func parse(markdown: String) -> Skill? {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return nil }

        var fields: [String: String] = [:]
        var currentKey: String?
        for line in lines[1..<end] {
            let indented = line.first == " " || line.first == "\t"
            if indented, let key = currentKey {
                let part = line.trimmingCharacters(in: .whitespaces)
                fields[key] = [fields[key] ?? "", part].filter { !$0.isEmpty }.joined(separator: " ")
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            var value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value == ">" || value == "|" || value == ">-" || value == "|-" { value = "" }
            fields[key] = unquoted(value)
            currentKey = key
        }

        guard let name = fields["name"], !name.isEmpty,
              let description = fields["description"], !description.isEmpty
        else { return nil }
        let body = lines[(end + 1)...].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return Skill(name: name, description: description, instructions: body)
    }

    private static func unquoted(_ value: String) -> String {
        guard value.count >= 2, let first = value.first, first == value.last, first == "\"" || first == "'" else { return value }
        return String(value.dropFirst().dropLast())
    }
}

/// Modelin bir skill'in tam talimatını yüklediği araç.
public struct UseSkillTool: Tool {
    private struct Arguments: Decodable {
        let name: String
    }

    public let name = "use_skill"
    public let description = "Loads the full instructions of one of the available skills. Call it before doing a task that matches a skill's description, then follow the instructions."
    public let parameters: JSONValue

    private let skills: [Skill]

    public init(skills: [Skill]) {
        self.skills = skills
        parameters = [
            "type": "object",
            "properties": [
                "name": ["type": "string", "enum": .array(skills.map { .string($0.name) }), "description": "Skill name"],
            ],
            "required": ["name"],
        ]
    }

    public func activityDetail(for arguments: String) -> String? {
        (try? decodeArguments(Arguments.self, from: arguments))?.name
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let requested = try decodeArguments(Arguments.self, from: arguments).name
        guard let skill = skills.first(where: { $0.name.caseInsensitiveCompare(requested) == .orderedSame }) else {
            return ToolOutput(content: "No skill named '\(requested)'. Available: \(skills.map(\.name).joined(separator: ", ")).")
        }
        return ToolOutput(content: """
        <skill name="\(skill.name)">
        \(skill.instructions)
        </skill>
        Follow these instructions for the current task. Scripts or files the skill mentions are not available on this device; do what you can with your own tools.
        """)
    }
}
