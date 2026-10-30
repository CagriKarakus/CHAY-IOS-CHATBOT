import SwiftData
import SwiftUI

/// Projeler: talimatları ve dosyaları olan, sohbetleri gruplayan klasörler.
struct ProjectsView: View {
    /// Projede yeni sohbet başlatır.
    let startChat: (ProjectRecord) -> Void
    /// Projedeki bir sohbeti açar.
    let openChat: (ConversationRecord) -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \ProjectRecord.createdAt, order: .reverse) private var projects: [ProjectRecord]
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(projects) { project in
                NavigationLink {
                    ProjectDetailView(project: project, startChat: startChat, openChat: openChat)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .foregroundStyle(Palette.textBright)
                        Text(L(
                            "\(project.files.count) files" + (project.instructions.isEmpty ? "" : " · instructions"),
                            "\(project.files.count) dosya" + (project.instructions.isEmpty ? "" : " · talimat")
                        ))
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                    }
                }
                .listRowBackground(Palette.surface)
            }
            .onDelete { offsets in
                offsets.map { projects[$0] }.forEach(delete)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .overlay {
            if projects.isEmpty {
                ContentUnavailableView(
                    L("No projects yet", "Henüz proje yok"),
                    systemImage: "folder.badge.gearshape",
                    description: Text(L(
                        "A project keeps related chats together with shared instructions and files.",
                        "Proje; ilgili sohbetleri ortak talimatlar ve dosyalarla bir arada tutar."
                    ))
                )
                .foregroundStyle(Palette.textMuted)
            }
        }
        .navigationTitle(L("Projects", "Projeler"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newName = ""
                    creating = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L("New Project", "Yeni proje"))
            }
        }
        .alert(L("New Project", "Yeni proje"), isPresented: $creating) {
            TextField(L("Project name", "Proje adı"), text: $newName)
            Button(L("Cancel", "Vazgeç"), role: .cancel) {}
            Button(L("Create", "Oluştur")) {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { return }
                context.insert(ProjectRecord(name: name))
                try? context.save()
            }
        }
    }

    /// Projeyi siler; sohbetleri kalır ama projeden çıkar.
    private func delete(_ project: ProjectRecord) {
        let id = project.id
        let chats = (try? context.fetch(FetchDescriptor<ConversationRecord>(predicate: #Predicate { $0.projectID == id }))) ?? []
        chats.forEach { $0.projectID = nil }
        context.delete(project)
        try? context.save()
    }
}

/// Proje ayrıntısı: yeni sohbet, talimatlar, dosyalar ve projedeki sohbetler.
struct ProjectDetailView: View {
    @Bindable var project: ProjectRecord
    let startChat: (ProjectRecord) -> Void
    let openChat: (ConversationRecord) -> Void

    @Environment(\.modelContext) private var context
    @Query private var chats: [ConversationRecord]
    @State private var importing = false
    @State private var reading = false
    @State private var errorMessage: String?

    init(project: ProjectRecord, startChat: @escaping (ProjectRecord) -> Void, openChat: @escaping (ConversationRecord) -> Void) {
        self.project = project
        self.startChat = startChat
        self.openChat = openChat
        let id = project.id
        _chats = Query(filter: #Predicate<ConversationRecord> { $0.projectID == id }, sort: \.updatedAt, order: .reverse)
    }

    var body: some View {
        Form {
            Section {
                Button {
                    startChat(project)
                } label: {
                    Label(L("New Chat in Project", "Projede yeni sohbet"), systemImage: "square.and.pencil")
                        .fontWeight(.semibold)
                }
            }
            .listRowBackground(Palette.surface)

            Section {
                TextField(L("Name", "Ad"), text: $project.name)
                    .foregroundStyle(Palette.textBright)
            } header: {
                header(L("Name", "Ad"))
            }
            .listRowBackground(Palette.surface)

            Section {
                TextEditor(text: $project.instructions)
                    .frame(minHeight: 120)
                    .scrollContentBackground(.hidden)
                    .foregroundStyle(Palette.textBright)
            } header: {
                header(L("Instructions", "Talimatlar"))
            } footer: {
                footer(L("Applied to every chat in this project, on top of your personal instructions.",
                         "Kişisel talimatlarına ek olarak bu projedeki her sohbette uygulanır."))
            }
            .listRowBackground(Palette.surface)

            Section {
                ForEach(project.files) { file in
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundStyle(Palette.yellow)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.name)
                                .foregroundStyle(Palette.textBright)
                            Text(L("\(file.text.count.formatted()) characters", "\(file.text.count.formatted()) karakter"))
                                .font(.caption)
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                }
                .onDelete { offsets in
                    var files = project.files
                    files.remove(atOffsets: offsets)
                    project.files = files
                    try? context.save()
                }
                Button {
                    importing = true
                } label: {
                    Label(L("Add File", "Dosya ekle"), systemImage: "plus")
                }
                if reading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text(L("Reading document…", "Doküman okunuyor…"))
                    }
                    .font(.footnote)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Palette.red)
                }
            } header: {
                header(L("Files", "Dosyalar"))
            } footer: {
                footer(L("PDF, Word, Excel, PowerPoint or text files. Their text is shared with the assistant in every chat of this project (up to about 120,000 characters in total).",
                         "PDF, Word, Excel, PowerPoint veya metin dosyaları. Metinleri bu projedeki her sohbette asistana iletilir (toplam yaklaşık 120.000 karaktere kadar)."))
            }
            .listRowBackground(Palette.surface)

            if !chats.isEmpty {
                Section {
                    ForEach(chats) { chat in
                        Button {
                            openChat(chat)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chat.title)
                                    .lineLimit(2)
                                    .foregroundStyle(Palette.textBright)
                                Text(chat.updatedAt.formatted(.relative(presentation: .named)))
                                    .font(.caption)
                                    .foregroundStyle(Palette.textMuted)
                            }
                        }
                    }
                } header: {
                    header(L("Chats", "Sohbetler"))
                }
                .listRowBackground(Palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(project.name)
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $importing, allowedContentTypes: documentContentTypes) { result in
            guard case let .success(url) = result else { return }
            reading = true
            errorMessage = nil
            Task {
                let document = await readDocument(from: url)
                reading = false
                guard let document else {
                    errorMessage = L("No text found in this file.", "Bu dosyada metin bulunamadı.")
                    return
                }
                errorMessage = document.skippedPages > 0 ? skippedPagesNote(document.skippedPages) : nil
                project.files.append(ProjectFile(name: url.lastPathComponent, text: document.text))
                try? context.save()
            }
        }
        .onDisappear { try? context.save() }
    }
}
