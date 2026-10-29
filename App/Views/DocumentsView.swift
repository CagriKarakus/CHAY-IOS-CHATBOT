import MarkdownUI
import SwiftUI

/// Uygulamanın Documents klasöründeki bir dosya (Dosyalar uygulamasında da görünür).
struct DocumentFile: Identifiable, Hashable {
    let url: URL
    var id: URL { url }
    var name: String { url.lastPathComponent }

    static var directory: URL {
        URL.documentsDirectory
    }

    /// Klasördeki .md dosyaları, en yeni önce.
    static func all() -> [DocumentFile] {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        return urls
            .filter { ["md", "html"].contains($0.pathExtension.lowercased()) }
            .sorted { modificationDate($0) > modificationDate($1) }
            .map(DocumentFile.init)
    }

    var modified: Date {
        Self.modificationDate(url)
    }

    private static func modificationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }
}

struct DocumentsView: View {
    @State private var documents: [DocumentFile] = []

    var body: some View {
        List {
            ForEach(documents) { document in
                NavigationLink {
                    if document.isArtifact {
                        ArtifactPage(document: document)
                    } else {
                        DocumentView(document: document)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.name)
                            .foregroundStyle(Palette.textBright)
                        Text(document.modified.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)
                    }
                }
                .listRowBackground(Palette.surface)
            }
            .onDelete(perform: delete)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .overlay {
            if documents.isEmpty {
                ContentUnavailableView(
                    L("No documents yet", "Henüz doküman yok"),
                    systemImage: "doc.text",
                    description: Text(L("Ask the assistant to create an md file about a topic.", "Asistandan bir konu hakkında md dosyası oluşturmasını iste."))
                )
                .foregroundStyle(Palette.textMuted)
            }
        }
        .navigationTitle(L("Documents", "Dokümanlar"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .onAppear { documents = DocumentFile.all() }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            try? FileManager.default.removeItem(at: documents[index].url)
        }
        documents.remove(atOffsets: offsets)
    }
}

/// Markdown dosyasını okuma görünümünde gösterir ve paylaşmayı sağlar.
struct DocumentView: View {
    let document: DocumentFile
    @State private var content: String?

    var body: some View {
        ScrollView {
            Group {
                if let content {
                    Markdown(content)
                        .markdownTheme(.atomOneDark)
                        .textSelection(.enabled)
                } else {
                    Text(L("Couldn't read the file.", "Dosya okunamadı."))
                        .foregroundStyle(Palette.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(Palette.background)
        .navigationTitle(document.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: document.url) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel(L("Share", "Paylaş"))
            }
        }
        .onAppear {
            content = try? String(contentsOf: document.url, encoding: .utf8)
        }
    }
}
