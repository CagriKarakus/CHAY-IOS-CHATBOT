import AgentCore
import Foundation
import SwiftData

/// Projeye eklenmiş bir bilgi dosyası (PDF/Office/metin dosyasından çıkarılmış metin).
struct ProjectFile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var text: String
}

/// Proje: kendi talimatları ve dosyaları olan, sohbetleri gruplayan klasör.
@Model
final class ProjectRecord {
    @Attribute(.unique) var id: UUID
    var name: String
    var instructions: String
    var createdAt: Date
    @Attribute(.externalStorage) var filesData: Data

    init(id: UUID = UUID(), name: String, instructions: String = "", createdAt: Date = .now, files: [ProjectFile] = []) {
        self.id = id
        self.name = name
        self.instructions = instructions
        self.createdAt = createdAt
        filesData = (try? JSONEncoder().encode(files)) ?? Data()
    }

    var files: [ProjectFile] {
        get { (try? JSONDecoder().decode([ProjectFile].self, from: filesData)) ?? [] }
        set { filesData = (try? JSONEncoder().encode(newValue)) ?? filesData }
    }

    /// System prompt'a giden proje bağlamı.
    var context: ProjectContext {
        ProjectContext(
            name: name,
            instructions: instructions,
            documents: files.map { ProjectContext.Document(name: $0.name, text: $0.text) }
        )
    }

    static func find(_ id: UUID, in context: ModelContext) -> ProjectRecord? {
        try? context.fetch(FetchDescriptor<ProjectRecord>(predicate: #Predicate { $0.id == id })).first
    }
}
