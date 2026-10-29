import AgentCore
import MarkdownUI
import SwiftData
import SwiftUI

struct ChatView: View {
    private enum Route: Hashable {
        case documents, notes
    }

    @Environment(AppSettings.self) private var settings
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ChatViewModel()
    @State private var path: [Route] = []
    @State private var showingSettings = false
    @State private var openedDocument: DocumentFile?
    @State private var selectingText: SelectableTextItem?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                messageList
                if let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(Palette.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                }
                composer
            }
            .background(Palette.background)
            .navigationTitle("AI Asistan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Dokümanlar", systemImage: "folder") { path.append(.documents) }
                        Button("Hafıza", systemImage: "brain") { path.append(.notes) }
                        Button("Ayarlar", systemImage: "slider.horizontal.3") { showingSettings = true }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(Palette.text)
                    }
                    .accessibilityLabel("Menü")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        inputFocused = false
                        viewModel.startNewChat()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(viewModel.isStreaming ? Palette.textMuted : Palette.text)
                    }
                    .disabled(viewModel.isStreaming)
                    .accessibilityLabel("Yeni sohbet")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .documents: DocumentsView()
                case .notes: NotesView()
                }
            }
            .alert(
                "Hafızaya kaydedilsin mi?",
                isPresented: Binding(
                    get: { viewModel.pendingApproval != nil },
                    set: { if !$0 { viewModel.resolveApproval(false) } }
                ),
                presenting: viewModel.pendingApproval
            ) { _ in
                Button("Reddet", role: .cancel) { viewModel.resolveApproval(false) }
                Button("Kaydet") { viewModel.resolveApproval(true) }
            } message: { pending in
                Text("Asistan bu sohbette web içeriği okudu ve şunu kaydetmek istiyor:\n\n\(pending.request.activity)")
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: $selectingText) { item in
                SelectableTextSheet(item: item)
            }
            .sheet(item: $openedDocument) { document in
                NavigationStack {
                    DocumentView(document: document)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Kapat") { openedDocument = nil }
                            }
                        }
                }
            }
            .onAppear {
                if !settings.isConfigured {
                    showingSettings = true
                }
            }
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.items) { item in
                        switch item.role {
                        case .user:
                            UserMessage(text: item.text)
                                .id(item.id)
                        case .assistant:
                            AssistantMessage(
                                item: item,
                                isStreaming: viewModel.isStreaming && item.id == viewModel.items.last?.id,
                                openDocument: { openedDocument = $0 },
                                selectText: { selectingText = SelectableTextItem(text: $0) }
                            )
                            .id(item.id)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            // Mesajların üzerine dokununca klavye kapanır (linkler çalışmaya devam eder).
            .simultaneousGesture(TapGesture().onEnded { inputFocused = false })
            .overlay {
                if viewModel.items.isEmpty {
                    emptyState
                        .onTapGesture { inputFocused = false }
                }
            }
            .onChange(of: viewModel.items.last?.text) {
                if let id = viewModel.items.last?.id {
                    proxy.scrollTo(id, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkle")
                .font(.system(size: 36))
                .foregroundStyle(Palette.purple)
            if settings.isConfigured {
                Text("Bugün neye bakalım?")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Palette.textBright)
            } else {
                Text("Başlamak için API bilgilerini gir")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Palette.textBright)
                Button("Ayarları aç") { showingSettings = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.blue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .padding()
    }

    /// Claude tarzı yuvarlak giriş kutusu.
    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Bir şey sor…", text: $viewModel.input, prompt: Text("Bir şey sor…").foregroundStyle(Palette.textMuted), axis: .vertical)
                .lineLimit(1...6)
                .focused($inputFocused)
                .foregroundStyle(Palette.textBright)
                .tint(Palette.blue)
            HStack(spacing: 8) {
                ModelMenu()
                EffortMenu()
                Spacer()
                Button {
                    inputFocused = false
                    viewModel.send(using: settings, notes: SwiftDataNoteStore(context: modelContext))
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Palette.background)
                        .frame(width: 32, height: 32)
                        .background(viewModel.canSend ? Palette.blue : Palette.border, in: .circle)
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Gönder")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(Palette.surface, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Palette.border, lineWidth: 1))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .onTapGesture { inputFocused = true }
    }
}

private struct UserMessage: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .foregroundStyle(Palette.textBright)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Palette.elevated, in: .rect(cornerRadius: 18))
                .contextMenu {
                    Button("Kopyala", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = text
                    }
                }
        }
    }
}

/// Balonsuz, tam genişlikte asistan cevabı; üstte araç etkinlikleri, altta dosyalar ve kaynaklar.
private struct AssistantMessage: View {
    let item: ChatItem
    let isStreaming: Bool
    let openDocument: (DocumentFile) -> Void
    let selectText: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !item.activities.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(item.activities) { activity in
                        ActivityRow(activity: activity)
                    }
                }
            }

            if !item.text.isEmpty {
                Markdown(item.text)
                    .markdownTheme(.atomOneDark)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button("Kopyala", systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = plainText(fromMarkdown: item.text)
                        }
                        Button("Metni seç", systemImage: "selection.pin.in.out") {
                            selectText(plainText(fromMarkdown: item.text))
                        }
                    }
                    .disabled(isStreaming)
            } else if isStreaming, item.activities.allSatisfy({ $0.state != .running }) {
                ProgressView()
                    .tint(Palette.textMuted)
            }

            ForEach(item.files, id: \.self) { url in
                FileCard(document: DocumentFile(url: url)) {
                    openDocument(DocumentFile(url: url))
                }
            }

            if !item.sources.isEmpty {
                SourceList(sources: item.sources)
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: ToolActivity

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch activity.state {
                case .running:
                    ProgressView()
                        .controlSize(.mini)
                        .tint(Palette.textMuted)
                case .done:
                    Image(systemName: icon)
                        .foregroundStyle(Palette.cyan)
                case .failed:
                    Image(systemName: "exclamationmark.circle")
                        .foregroundStyle(Palette.red)
                }
            }
            .frame(width: 16)
            Text(activity.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(Palette.textMuted)
        }
        .font(.footnote)
    }

    private var icon: String {
        switch activity.toolName {
        case "web_search": "magnifyingglass"
        case "fetch_page": "doc.text"
        case "write_file": "doc.badge.plus"
        case "save_note": "brain"
        case "read_notes": "list.bullet.rectangle"
        default: "wrench.and.screwdriver"
        }
    }
}

/// Asistanın oluşturduğu dosya; dokununca açılır.
private struct FileCard: View {
    let document: DocumentFile
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 12) {
                Image(systemName: "doc.richtext")
                    .font(.title3)
                    .foregroundStyle(Palette.blue)
                    .frame(width: 36, height: 36)
                    .background(Palette.background, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.name)
                        .lineLimit(1)
                        .foregroundStyle(Palette.textBright)
                    Text("Markdown · dokun ve aç")
                        .font(.caption)
                        .foregroundStyle(Palette.textMuted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(Palette.textMuted)
            }
            .padding(10)
            .background(Palette.surface, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct SourceList: View {
    let sources: [Source]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(sources.enumerated()), id: \.element.url) { index, source in
                    Link(destination: source.url) {
                        HStack(spacing: 6) {
                            Text("\(index + 1)")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(Palette.background)
                                .frame(width: 16, height: 16)
                                .background(Palette.yellow, in: .circle)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.title)
                                    .lineLimit(1)
                                    .foregroundStyle(Palette.textBright)
                                Text(source.url.host ?? source.url.absoluteString)
                                    .lineLimit(1)
                                    .foregroundStyle(Palette.textMuted)
                            }
                            .font(.caption)
                        }
                        .frame(maxWidth: 200, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Palette.surface, in: .rect(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Palette.border, lineWidth: 1))
                    }
                }
            }
        }
    }
}
