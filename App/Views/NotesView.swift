import SwiftData
import SwiftUI

/// Hafıza notlarını görüntüleme, düzenleme, ekleme ve silme.
struct NotesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \NoteRecord.createdAt, order: .reverse) private var notes: [NoteRecord]
    @State private var editing: NoteRecord?
    @State private var addingNew = false

    var body: some View {
        List {
            Section {
                ForEach(notes) { note in
                    Button {
                        editing = note
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.content)
                                .foregroundStyle(Palette.textBright)
                                .multilineTextAlignment(.leading)
                            Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                    .listRowBackground(Palette.surface)
                }
                .onDelete { offsets in
                    offsets.map { notes[$0] }.forEach(context.delete)
                    try? context.save()
                }
            } footer: {
                if !notes.isEmpty {
                    Text("Bu notlar her sohbette asistana iletilir. Silmek için sola kaydır.")
                        .foregroundStyle(Palette.textMuted)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView(
                    "Hafıza boş",
                    systemImage: "brain",
                    description: Text("Asistana kendinden veya tercihlerinden bahsettiğinde burada not olarak görünür.")
                )
                .foregroundStyle(Palette.textMuted)
            }
        }
        .navigationTitle("Hafıza")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    addingNew = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Not ekle")
            }
        }
        .sheet(item: $editing) { note in
            NoteEditor(initialText: note.content) { text in
                note.content = text
                try? context.save()
            }
        }
        .sheet(isPresented: $addingNew) {
            NoteEditor(initialText: "") { text in
                context.insert(NoteRecord(content: text))
                try? context.save()
            }
        }
    }
}

private struct NoteEditor: View {
    let initialText: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Not", text: $text, prompt: Text("Örn. Kahveyi şekersiz içerim.").foregroundStyle(Palette.textMuted), axis: .vertical)
                    .lineLimit(3...12)
                    .foregroundStyle(Palette.textBright)
                    .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(initialText.isEmpty ? "Yeni not" : "Notu düzenle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        save(trimmed)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { text = initialText }
        }
        .presentationDetents([.medium])
    }
}
