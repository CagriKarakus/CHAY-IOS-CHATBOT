import Foundation

/// Kullanıcı hakkında kalıcı bir not (hafıza).
public struct Note: Equatable, Sendable {
    public let content: String
    public let createdAt: Date

    public init(content: String, createdAt: Date) {
        self.content = content
        self.createdAt = createdAt
    }
}

/// Notların saklandığı yer. iOS'ta SwiftData, testlerde bellek içi uygulama.
public protocol NoteStore: Sendable {
    /// En eski önce.
    func allNotes() async throws -> [Note]
    func addNote(_ content: String) async throws
}
