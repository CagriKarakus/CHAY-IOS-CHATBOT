import AgentCore
import SwiftUI

/// Skill kütüphanesi: listeleme, varsayılan açık/kapalı, GitHub'dan ekleme, elle oluşturma.
struct SkillsView: View {
    @Environment(SkillLibrary.self) private var library
    @State private var importing = false
    @State private var creating = false

    var body: some View {
        List {
            Section {
                ForEach(library.skills) { installed in
                    NavigationLink {
                        SkillEditorView(installed: installed)
                    } label: {
                        Toggle(isOn: Binding(
                            get: { installed.enabledByDefault },
                            set: { library.setEnabledByDefault($0, for: installed.id) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(installed.skill.name)
                                    .foregroundStyle(Palette.textBright)
                                Text(installed.skill.description)
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundStyle(Palette.textMuted)
                                if let source = installed.source {
                                    Text(source)
                                        .font(.caption2)
                                        .foregroundStyle(Palette.cyan)
                                }
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { library.skills[$0].id }.forEach(library.delete)
                }
            } footer: {
                footer(L(
                    "The switch sets whether a skill is on in new chats; you can change it per chat from the + menu. The assistant sees each skill's name and description and loads the full instructions when a task matches. Scripts inside skills can't run on the phone.",
                    "Anahtar, skill'in yeni sohbetlerde açık olup olmadığını belirler; her sohbette + menüsünden değiştirebilirsin. Asistan her skill'in adını ve açıklamasını görür, uygun bir görevde tam talimatı yükler. Skill'lerdeki script'ler telefonda çalışmaz."
                ))
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .overlay {
            if library.skills.isEmpty {
                ContentUnavailableView(
                    L("No skills yet", "Henüz skill yok"),
                    systemImage: "sparkles",
                    description: Text(L("Add skills from a GitHub repository (e.g. anthropics/skills) or write your own.",
                                        "Bir GitHub reposundan (örn. anthropics/skills) skill ekle ya da kendin yaz."))
                )
                .foregroundStyle(Palette.textMuted)
            }
        }
        .navigationTitle(L("Skills", "Skill'ler"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(L("Add from GitHub", "GitHub'dan ekle"), systemImage: "arrow.down.circle") { importing = true }
                    Button(L("Create Skill", "Skill oluştur"), systemImage: "square.and.pencil") { creating = true }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L("Add Skill", "Skill ekle"))
            }
        }
        .sheet(isPresented: $importing) {
            SkillImportView()
        }
        .sheet(isPresented: $creating) {
            NavigationStack {
                SkillEditorView(installed: nil)
            }
        }
    }
}

/// GitHub reposundaki SKILL.md dosyalarını listeleyip seçilenleri ekler.
private struct SkillImportView: View {
    @Environment(SkillLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var repository = "anthropics/skills"
    @State private var found: [SkillRepository.Found] = []
    @State private var picked: Set<String> = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("owner/repo", text: $repository, prompt: prompt("anthropics/skills"))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(Palette.textBright)
                    Button(action: load) {
                        HStack {
                            Label(L("Find Skills", "Skill'leri bul"), systemImage: "magnifyingglass")
                            if isLoading {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isLoading || repository.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    header(L("GitHub repository or marketplace", "GitHub reposu veya marketplace"))
                } footer: {
                    footer(L(
                        "Every SKILL.md in the repository is listed. Skills are instructions for the assistant; only add them from sources you trust.",
                        "Repodaki tüm SKILL.md dosyaları listelenir. Skill'ler asistana verilen talimatlardır; sadece güvendiğin kaynaklardan ekle."
                    ))
                }
                .listRowBackground(Palette.surface)

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(Palette.red)
                    }
                    .listRowBackground(Palette.surface)
                }

                if !found.isEmpty {
                    Section {
                        ForEach(found, id: \.path) { item in
                            Button {
                                if picked.contains(item.path) { picked.remove(item.path) } else { picked.insert(item.path) }
                            } label: {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.skill.name)
                                            .foregroundStyle(Palette.textBright)
                                        Text(item.skill.description)
                                            .font(.caption)
                                            .lineLimit(3)
                                            .foregroundStyle(Palette.textMuted)
                                    }
                                    Spacer()
                                    if picked.contains(item.path) {
                                        Image(systemName: "checkmark").foregroundStyle(Palette.blue)
                                    }
                                }
                            }
                        }
                    } header: {
                        header(L("\(found.count) skills found", "\(found.count) skill bulundu"))
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(L("Add from GitHub", "GitHub'dan ekle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Vazgeç")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Add (\(picked.count))", "Ekle (\(picked.count))")) {
                        let source = SkillRepository.parseRepository(repository).map { "\($0.owner)/\($0.repo)" }
                        library.add(found.filter { picked.contains($0.path) }.map(\.skill), source: source)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(picked.isEmpty)
                }
            }
        }
    }

    private func load() {
        errorMessage = nil
        isLoading = true
        Task {
            defer { isLoading = false }
            do {
                found = try await SkillRepository.fetchSkills(from: repository, transport: URLSessionTransport())
                picked = []
                if found.isEmpty {
                    errorMessage = L("No SKILL.md files found in this repository.", "Bu repoda SKILL.md dosyası bulunamadı.")
                }
            } catch {
                errorMessage = userFacingMessage(for: error)
            }
        }
    }
}

/// Skill oluşturma/düzenleme. `installed` nil ise yeni skill.
struct SkillEditorView: View {
    let installed: InstalledSkill?
    @Environment(SkillLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var description = ""
    @State private var instructions = ""

    private var isValid: Bool {
        ![name, description, instructions].contains { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var body: some View {
        Form {
            Section {
                TextField(L("Name", "Ad"), text: $name, prompt: prompt(L("e.g. meeting-notes", "örn. toplanti-notlari")))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField(L("Description", "Açıklama"), text: $description,
                          prompt: prompt(L("When should the assistant use it?", "Asistan bunu ne zaman kullanmalı?")), axis: .vertical)
                    .lineLimit(2...5)
            } footer: {
                footer(L("The description decides when the skill is used, so say what it's for.",
                         "Skill'in ne zaman kullanılacağına açıklamaya bakılarak karar verilir; ne işe yaradığını yaz."))
            }
            .listRowBackground(Palette.surface)

            Section {
                TextEditor(text: $instructions)
                    .frame(minHeight: 240)
                    .font(.system(.footnote, design: .monospaced))
                    .scrollContentBackground(.hidden)
            } header: {
                header(L("Instructions (Markdown)", "Talimatlar (Markdown)"))
            }
            .listRowBackground(Palette.surface)

            if let installed {
                Section {
                    Button(L("Delete Skill", "Skill'i sil"), role: .destructive) {
                        library.delete(installed.id)
                        dismiss()
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .foregroundStyle(Palette.textBright)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(installed == nil ? L("New Skill", "Yeni skill") : name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if installed == nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Vazgeç")) { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Save", "Kaydet")) {
                    var updated = installed ?? InstalledSkill(skill: Skill(name: "", description: "", instructions: ""))
                    updated.skill = Skill(
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                        instructions: instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    library.update(updated)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!isValid)
            }
        }
        .onAppear {
            if let installed {
                name = installed.skill.name
                description = installed.skill.description
                instructions = installed.skill.instructions
            }
        }
    }
}
