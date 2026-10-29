import Foundation

/// Kullanıcı hakkında kalıcı bir notu hafızaya kaydeder.
/// Sohbette web içeriği okunduysa kayıt için kullanıcı onayı istenir (prompt injection'a karşı).
public struct SaveNoteTool: Tool {
    private struct Arguments: Decodable {
        let content: String
    }

    public static let maxLength = 500

    public let name = "save_note"
    public let description = "Kullanıcı hakkında kalıcı bir bilgiyi veya tercihi hafızaya kısa bir not olarak kaydeder. Not sonraki sohbetlerde de hatırlanır."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "content": ["type": "string", "description": "Tek cümlelik not, örn. 'Kullanıcı emoji kullanılmasını sevmiyor.'"],
        ],
        "required": ["content"],
    ]
    public let requiresApprovalAfterUntrustedContent = true

    private let store: any NoteStore

    public init(store: any NoteStore) {
        self.store = store
    }

    public func activity(for arguments: String) -> String? {
        (try? decodeArguments(Arguments.self, from: arguments)).map { "Hafızaya kaydediliyor: \($0.content.trimmingCharacters(in: .whitespacesAndNewlines))" }
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let content = try decodeArguments(Arguments.self, from: arguments).content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw ToolError.invalidArguments }
        guard content.count <= Self.maxLength else { throw ToolError.tooLong(limit: Self.maxLength) }

        let existing = try await store.allNotes()
        if existing.contains(where: { $0.content.caseInsensitiveCompare(content) == .orderedSame }) {
            return ToolOutput(content: "Bu not zaten kayıtlı.")
        }
        try await store.addNote(content)
        return ToolOutput(content: "Hafızaya kaydedildi: \(content)")
    }
}
