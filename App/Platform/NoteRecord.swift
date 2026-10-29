import AgentCore
import Foundation
import SwiftData

/// Hafıza notunun SwiftData kaydı.
@Model
final class NoteRecord {
    var content: String
    var createdAt: Date

    init(content: String, createdAt: Date = .now) {
        self.content = content
        self.createdAt = createdAt
    }
}

/// `NoteStore`'un SwiftData uygulaması. Ana context'i kullanır ki Notlar ekranı (`@Query`) anında güncellensin.
@MainActor
final class SwiftDataNoteStore: NoteStore {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func allNotes() async throws -> [Note] {
        let records = try context.fetch(FetchDescriptor<NoteRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        return records.map { Note(content: $0.content, createdAt: $0.createdAt) }
    }

    func addNote(_ content: String) async throws {
        context.insert(NoteRecord(content: content))
        try context.save()
    }
}
