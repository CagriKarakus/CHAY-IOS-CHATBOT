import Foundation

/// Hafızadaki tüm notları döndürür.
public struct ReadNotesTool: Tool {
    public let name = "read_notes"
    public let description = "Kullanıcı hakkında hafızaya kaydedilmiş tüm notları listeler."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [:],
    ]

    private let store: any NoteStore

    public init(store: any NoteStore) {
        self.store = store
    }

    public func activity(for arguments: String) -> String? {
        "Notlar okunuyor"
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let notes = try await store.allNotes()
        guard !notes.isEmpty else {
            return ToolOutput(content: "Henüz kayıtlı not yok.")
        }
        return ToolOutput(content: notes.map { "- \($0.content)" }.joined(separator: "\n"))
    }
}
