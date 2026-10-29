import SwiftData
import SwiftUI

/// Kayıtlı sohbetler, en son güncellenen önce.
struct ConversationsView: View {
    /// Şu an açık olan sohbet (işaretlemek ve silinirse kapatmak için).
    let currentID: UUID?
    let open: (ConversationRecord) -> Void
    let deletedCurrent: () -> Void

    @Environment(\.modelContext) private var context
    @Query(sort: \ConversationRecord.updatedAt, order: .reverse) private var conversations: [ConversationRecord]
    @State private var query = ""

    /// Başlıkta veya mesajlarda aranan metni içeren sohbetler.
    private var filtered: [ConversationRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? conversations : conversations.filter { $0.matches(trimmed) }
    }

    var body: some View {
        List {
            ForEach(filtered) { conversation in
                Button {
                    open(conversation)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(conversation.title)
                                .lineLimit(2)
                                .foregroundStyle(Palette.textBright)
                                .multilineTextAlignment(.leading)
                            Text(conversation.updatedAt.formatted(.relative(presentation: .named)))
                                .font(.caption)
                                .foregroundStyle(Palette.textMuted)
                        }
                        Spacer()
                        if conversation.id == currentID {
                            Image(systemName: "circle.fill")
                                .font(.caption2)
                                .foregroundStyle(Palette.blue)
                        }
                    }
                }
                .listRowBackground(Palette.surface)
            }
            .onDelete(perform: delete)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .overlay {
            if conversations.isEmpty {
                ContentUnavailableView(
                    L("No chats yet", "Henüz sohbet yok"),
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text(L("Every chat you send is saved here.", "Gönderdiğin her sohbet burada saklanır."))
                )
                .foregroundStyle(Palette.textMuted)
            }
        }
        .overlay {
            if !conversations.isEmpty, filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
        }
        .searchable(text: $query, prompt: L("Search chats", "Sohbetlerde ara"))
        .navigationTitle(L("Chats", "Sohbetler"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let conversation = filtered[index]
            if conversation.id == currentID {
                deletedCurrent()
            }
            // Sohbetteki görsellerin tam boyutlu kopyalarını da sil.
            AttachmentFiles.delete(conversation.content.items.flatMap { $0.attachments ?? [] }.compactMap(\.file))
            context.delete(conversation)
        }
        try? context.save()
    }
}
