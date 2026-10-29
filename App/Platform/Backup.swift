import AgentCore
import Foundation
import SwiftData

/// Tüm verinin tek bir JSON dosyasına yedeği. API key'ler güvenlik nedeniyle dahil edilmez.
struct Backup: Codable {
    struct StoredNote: Codable {
        let content: String
        let createdAt: Date
    }

    struct StoredConversation: Codable {
        let id: UUID
        let title: String
        let createdAt: Date
        let updatedAt: Date
        let content: ConversationContent
        var projectID: UUID?
    }

    struct StoredProject: Codable {
        let id: UUID
        let name: String
        let instructions: String
        let createdAt: Date
        let files: [ProjectFile]
    }

    struct StoredDocument: Codable {
        let name: String
        let text: String
    }

    var version = 1
    var exportedAt = Date.now
    var providers: [Provider]
    var userInstructions: String
    var notes: [StoredNote]
    var conversations: [StoredConversation]
    var skills: [InstalledSkill]
    var prompts: [SavedPrompt]
    var documents: [StoredDocument]
    /// Eski yedeklerde yok.
    var projects: [StoredProject]?
}

/// İçe aktarmada eklenenlerin sayısı.
struct ImportSummary {
    var conversations = 0
    var notes = 0
    var skills = 0
    var prompts = 0
    var providers = 0
    var documents = 0
    var projects = 0
}

@MainActor
enum BackupService {
    static func export(context: ModelContext, settings: AppSettings, skills: SkillLibrary, prompts: PromptLibrary) throws -> URL {
        let notes = try context.fetch(FetchDescriptor<NoteRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        let conversations = try context.fetch(FetchDescriptor<ConversationRecord>(sortBy: [SortDescriptor(\.createdAt)]))
        let documents = DocumentFile.all().compactMap { file -> Backup.StoredDocument? in
            (try? String(contentsOf: file.url, encoding: .utf8)).map { Backup.StoredDocument(name: file.name, text: $0) }
        }

        let backup = Backup(
            providers: settings.providers,
            userInstructions: settings.userInstructions,
            notes: notes.map { Backup.StoredNote(content: $0.content, createdAt: $0.createdAt) },
            conversations: conversations.map {
                Backup.StoredConversation(
                    id: $0.id, title: $0.title, createdAt: $0.createdAt, updatedAt: $0.updatedAt,
                    content: $0.content, projectID: $0.projectID
                )
            },
            skills: skills.skills,
            prompts: prompts.prompts,
            documents: documents,
            projects: try context.fetch(FetchDescriptor<ProjectRecord>()).map {
                Backup.StoredProject(id: $0.id, name: $0.name, instructions: $0.instructions, createdAt: $0.createdAt, files: $0.files)
            }
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("CHAY-backup-\(formatter.string(from: .now)).json")
        try encoder.encode(backup).write(to: url, options: .atomic)
        return url
    }

    /// Yedeği mevcut verilere ekler; zaten var olanlar (aynı kimlik veya içerik) atlanır, hiçbir şey silinmez.
    static func importBackup(
        from url: URL,
        context: ModelContext,
        settings: AppSettings,
        skills: SkillLibrary,
        prompts: PromptLibrary
    ) throws -> ImportSummary {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(Backup.self, from: Data(contentsOf: url))
        var summary = ImportSummary()

        let existingConversations = Set(try context.fetch(FetchDescriptor<ConversationRecord>()).map(\.id))
        for conversation in backup.conversations where !existingConversations.contains(conversation.id) {
            context.insert(ConversationRecord(
                id: conversation.id,
                title: conversation.title,
                createdAt: conversation.createdAt,
                updatedAt: conversation.updatedAt,
                content: conversation.content,
                projectID: conversation.projectID
            ))
            summary.conversations += 1
        }

        let existingProjects = Set(try context.fetch(FetchDescriptor<ProjectRecord>()).map(\.id))
        for project in backup.projects ?? [] where !existingProjects.contains(project.id) {
            context.insert(ProjectRecord(id: project.id, name: project.name, instructions: project.instructions,
                                         createdAt: project.createdAt, files: project.files))
            summary.projects += 1
        }

        let existingNotes = Set(try context.fetch(FetchDescriptor<NoteRecord>()).map { $0.content.lowercased() })
        for note in backup.notes where !existingNotes.contains(note.content.lowercased()) {
            context.insert(NoteRecord(content: note.content, createdAt: note.createdAt))
            summary.notes += 1
        }
        try context.save()

        summary.skills = skills.importSkills(backup.skills)
        summary.prompts = prompts.importPrompts(backup.prompts)
        summary.providers = settings.importProviders(backup.providers)
        settings.importUserInstructions(backup.userInstructions)

        try FileManager.default.createDirectory(at: DocumentFile.directory, withIntermediateDirectories: true)
        for document in backup.documents {
            // Sadece düz dosya adları; yol içerenler atlanır.
            guard !document.name.contains("/"), !document.name.contains(".."),
                  document.name.lowercased().hasSuffix(".md") else { continue }
            let target = DocumentFile.directory.appendingPathComponent(document.name)
            guard !FileManager.default.fileExists(atPath: target.path) else { continue }
            try Data(document.text.utf8).write(to: target, options: .atomic)
            summary.documents += 1
        }
        return summary
    }
}
