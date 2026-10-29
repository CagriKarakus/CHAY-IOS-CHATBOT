import Foundation

/// Hafızadaki tüm notları döndürür.
public struct ReadNotesTool: Tool {
    public let name = "read_notes"
    public let description = "Lists all notes saved to memory about the user."
    public let parameters: JSONValue = [
        "type": "object",
        "properties": [:],
    ]

    private let store: any NoteStore

    public init(store: any NoteStore) {
        self.store = store
    }

    public func activityDetail(for arguments: String) -> String? {
        nil
    }

    public func run(arguments: String) async throws -> ToolOutput {
        let notes = try await store.allNotes()
        guard !notes.isEmpty else {
            return ToolOutput(content: "No notes saved yet.")
        }
        return ToolOutput(content: notes.map { "- \($0.content)" }.joined(separator: "\n"))
    }
}
