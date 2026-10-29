import Foundation

/// Kullanıcı hakkında kalıcı bir notu hafızaya kaydeder.
/// Sohbette web içeriği okunduysa kayıt için kullanıcı onayı istenir (prompt injection'a karşı).
public struct SaveNoteTool: Tool {
    private struct Arguments: Decodable {
        let content: String
    }

    public static let maxLength = 500

    public let name = "save_note"
    public let description = "Saves a lasting fact or preference about the user to memory as a short note. The note is remembered in future chats."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [
            "content": ["type": "string", "description": "One-sentence note, e.g. 'The user dislikes emoji.'"],
        ],
        "required": ["content"],
    ]
    public let requiresApprovalAfterUntrustedContent = true

    private let store: any NoteStore

    public init(store: any NoteStore) {
        self.store = store
    }

    public func activityDetail(for arguments: String) -> String? {
        (try? decodeArguments(Arguments.self, from: arguments))?.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let content = try decodeArguments(Arguments.self, from: arguments).content
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw ToolError.invalidArguments }
        guard content.count <= Self.maxLength else { throw ToolError.tooLong(limit: Self.maxLength) }

        let existing = try await store.allNotes()
        if existing.contains(where: { $0.content.caseInsensitiveCompare(content) == .orderedSame }) {
            return ToolOutput(content: "This note is already saved.")
        }
        try await store.addNote(content)
        return ToolOutput(content: "Saved to memory: \(content)")
    }
}
