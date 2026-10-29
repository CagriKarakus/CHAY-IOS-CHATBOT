import SwiftUI

/// Hazır komutları yönetme: ekle, düzenle, sil, sırala.
struct PromptsView: View {
    @Environment(PromptLibrary.self) private var library
    @State private var editing: SavedPrompt?

    var body: some View {
        List {
            Section {
                ForEach(library.prompts) { prompt in
                    Button {
                        editing = prompt
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.title)
                                .foregroundStyle(Palette.textBright)
                            Text(prompt.text.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.caption)
                                .lineLimit(2)
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                }
                .onDelete(perform: library.delete)
                .onMove(perform: library.move)
            } footer: {
                footer(L("Pick a prompt from the + menu in the chat to insert it into the message box.",
                         "Sohbetteki + menüsünden bir komut seçince mesaj kutusuna eklenir."))
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(L("Prompts", "Hazır komutlar"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = SavedPrompt(title: "", text: "")
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(L("Add Prompt", "Komut ekle"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(item: $editing) { prompt in
            PromptEditor(original: prompt)
        }
    }
}

/// Komut oluşturma/düzenleme.
struct PromptEditor: View {
    /// Düzenlenen komut (yeni ise boş başlık ve metinle).
    let original: SavedPrompt
    @Environment(PromptLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var text = ""

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("Title", "Başlık"), text: $title, prompt: prompt(L("e.g. Make it formal", "örn. Resmi dile çevir")))
                } header: {
                    header(L("Title", "Başlık"))
                }
                .listRowBackground(Palette.surface)

                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .scrollContentBackground(.hidden)
                } header: {
                    header(L("Prompt", "Komut"))
                } footer: {
                    footer(L("End it with a blank line if you'll paste text after it.",
                             "Arkasına metin yapıştıracaksan sonuna boş bir satır bırak."))
                }
                .listRowBackground(Palette.surface)
            }
            .foregroundStyle(Palette.textBright)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(original.title.isEmpty ? L("New Prompt", "Yeni komut") : original.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Vazgeç")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Save", "Kaydet")) {
                        var updated = original
                        updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        updated.text = text
                        library.update(updated)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
            .onAppear {
                title = original.title
                text = original.text
            }
        }
    }
}
