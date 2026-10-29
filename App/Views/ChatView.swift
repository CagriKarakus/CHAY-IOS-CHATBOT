import AgentCore
import MarkdownUI
import PhotosUI
import SwiftData
import SwiftUI

struct ChatView: View {
    private enum Route: Hashable {
        case conversations, documents, notes
    }

    @Environment(AppSettings.self) private var settings
    @Environment(UsageTracker.self) private var usage
    @Environment(SkillLibrary.self) private var skills
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ChatViewModel()
    @State private var path: [Route] = []
    @State private var showingSettings = false
    @State private var openedDocument: DocumentFile?
    @State private var selectingText: SelectableTextItem?
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingPhotoPicker = false
    @State private var recorder = AudioRecorder()
    @State private var showingCamera = false
    @State private var showingFileImporter = false
    @State private var viewedImage: ViewedImage?
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                messageList
                if let errorMessage = viewModel.errorMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if viewModel.canRetry {
                            Button(L("Try Again", "Tekrar dene")) { viewModel.retry(using: settings) }
                                .fontWeight(.semibold)
                                .foregroundStyle(Palette.blue)
                        }
                    }
                    .font(.footnote)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                composer
            }
            .background(Palette.background)
            .navigationTitle(viewModel.isIncognito ? L("Incognito Chat", "Gizli sohbet") : L("AI Assistant", "AI Asistan"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(L("Chats", "Sohbetler"), systemImage: "bubble.left.and.bubble.right") { path.append(.conversations) }
                        Button(L("Documents", "Dokümanlar"), systemImage: "folder") { path.append(.documents) }
                        Button(L("Memory", "Hafıza"), systemImage: "brain") { path.append(.notes) }
                        Button(L("Settings", "Ayarlar"), systemImage: "slider.horizontal.3") { showingSettings = true }
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(Palette.text)
                    }
                    .accessibilityLabel(L("Menu", "Menü"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        inputFocused = false
                        viewModel.startNewChat(incognito: !viewModel.isIncognito)
                    } label: {
                        Image(systemName: viewModel.isIncognito ? "eye.slash.fill" : "eye.slash")
                            .foregroundStyle(viewModel.isIncognito ? Palette.purple : (viewModel.isStreaming ? Palette.textMuted : Palette.text))
                    }
                    .disabled(viewModel.isStreaming)
                    .accessibilityLabel(viewModel.isIncognito ? L("Leave Incognito", "Gizli sohbetten çık") : L("Incognito Chat", "Gizli sohbet"))
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
                    .accessibilityLabel(L("New chat", "Yeni sohbet"))
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .conversations:
                    ConversationsView(
                        currentID: viewModel.conversationID,
                        open: { record in
                            viewModel.open(record)
                            path = []
                        },
                        deletedCurrent: { viewModel.startNewChat() }
                    )
                case .documents: DocumentsView()
                case .notes: NotesView()
                }
            }
            .alert(
                L("Save to memory?", "Hafızaya kaydedilsin mi?"),
                isPresented: Binding(
                    get: { viewModel.pendingApproval != nil },
                    set: { if !$0 { viewModel.resolveApproval(false) } }
                ),
                presenting: viewModel.pendingApproval
            ) { _ in
                Button(L("Decline", "Reddet"), role: .cancel) { viewModel.resolveApproval(false) }
                Button(L("Save", "Kaydet")) { viewModel.resolveApproval(true) }
            } message: { pending in
                Text(L(
                    "The assistant read web content in this chat and wants to save:\n\n\(pending.request.detail ?? "")",
                    "Asistan bu sohbette web içeriği okudu ve şunu kaydetmek istiyor:\n\n\(pending.request.detail ?? "")"
                ))
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .fullScreenCover(item: $viewedImage) { viewed in
                ImageViewer(image: viewed.image)
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { image in
                    if let data = image.jpegData(compressionQuality: 0.9) {
                        viewModel.addImage(data)
                    }
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf, .plainText, .text]) { result in
                guard case let .success(url) = result else { return }
                guard let text = extractDocumentText(from: url) else {
                    viewModel.errorMessage = L("Couldn't read the file.", "Dosya okunamadı.")
                    return
                }
                viewModel.addDocument(text: text, name: url.lastPathComponent)
            }
            .sheet(item: $selectingText) { item in
                SelectableTextSheet(item: item)
            }
            .sheet(item: $openedDocument) { document in
                NavigationStack {
                    DocumentView(document: document)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L("Close", "Kapat")) { openedDocument = nil }
                            }
                        }
                }
            }
            .onAppear {
                viewModel.attach(modelContext, usage: usage, skills: skills)
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
                            UserMessage(text: item.text, attachments: item.attachments ?? []) { viewedImage = ViewedImage(image: $0) }
                                .id(item.id)
                        case .assistant:
                            AssistantMessage(
                                item: item,
                                isStreaming: viewModel.isStreaming && item.id == viewModel.items.last?.id,
                                openDocument: { openedDocument = $0 },
                                selectText: { selectingText = SelectableTextItem(text: $0) },
                                showImage: { viewedImage = ViewedImage(image: $0) }
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
            Image(systemName: viewModel.isIncognito ? "eye.slash" : "sparkle")
                .font(.system(size: 36))
                .foregroundStyle(Palette.purple)
            if viewModel.isIncognito {
                Text(L("Incognito chat", "Gizli sohbet"))
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Palette.textBright)
                Text(L("This chat isn't saved, and memory is neither used nor updated.",
                       "Bu sohbet kaydedilmez; hafıza ne kullanılır ne de güncellenir."))
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Palette.textMuted)
            } else if settings.isConfigured {
                Text(L("What shall we look into today?", "Bugün neye bakalım?"))
                    .font(.title2.weight(.medium))
                    .foregroundStyle(Palette.textBright)
            } else {
                Text(L("Enter your API details to get started", "Başlamak için API bilgilerini gir"))
                    .font(.title3.weight(.medium))
                    .foregroundStyle(Palette.textBright)
                Button(L("Open Settings", "Ayarları aç")) { showingSettings = true }
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
            if !viewModel.pendingAttachments.isEmpty {
                PendingAttachmentStrip(attachments: viewModel.pendingAttachments) { viewModel.removeAttachment($0) }
            }
            if recorder.isRecording {
                RecordingBar(elapsed: recorder.elapsed, cancel: recorder.cancel) {
                    if let recording = recorder.stop() {
                        viewModel.addAudio(recording.data, duration: recording.duration)
                    }
                }
            } else {
                TextField(L("Ask anything…", "Bir şey sor…"), text: $viewModel.input, prompt: Text(L("Ask anything…", "Bir şey sor…")).foregroundStyle(Palette.textMuted), axis: .vertical)
                    .lineLimit(1...6)
                    .focused($inputFocused)
                    .foregroundStyle(Palette.textBright)
                    .tint(Palette.blue)
            }
            HStack(spacing: 8) {
                attachMenu
                ModelMenu()
                EffortMenu()
                Spacer()
                if viewModel.isStreaming {
                    Button {
                        viewModel.stop()
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.footnote)
                            .foregroundStyle(Palette.background)
                            .frame(width: 32, height: 32)
                            .background(Palette.textBright, in: .circle)
                    }
                    .accessibilityLabel(L("Stop", "Durdur"))
                } else {
                    Button {
                        inputFocused = false
                        viewModel.send(using: settings)
                    } label: {
                        Image(systemName: "arrow.up")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Palette.background)
                            .frame(width: 32, height: 32)
                            .background(viewModel.canSend ? Palette.blue : Palette.border, in: .circle)
                    }
                    .disabled(!viewModel.canSend)
                    .accessibilityLabel(L("Send", "Gönder"))
                }
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
        .photosPicker(isPresented: $showingPhotoPicker, selection: $photoItems, maxSelectionCount: 4, matching: .images)
        .onChange(of: photoItems) {
            let items = photoItems
            photoItems = []
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        viewModel.addImage(data)
                    }
                }
            }
        }
    }

    /// Ekler (modelin desteklediklerine göre) ve sohbete özel seçenekler: hafıza ve skill'ler.
    private var attachMenu: some View {
        let model = settings.selected?.model
        return Menu {
            Section {
                if model?.acceptsImages == true {
                    if CameraPicker.isAvailable {
                        Button(L("Camera", "Kamera"), systemImage: "camera") { showingCamera = true }
                    }
                    Button(L("Photo", "Fotoğraf"), systemImage: "photo") { showingPhotoPicker = true }
                }
                Button(L("PDF or Text File", "PDF veya metin dosyası"), systemImage: "doc.text") { showingFileImporter = true }
                if model?.acceptsAudio == true {
                    Button(L("Record Audio", "Ses kaydet"), systemImage: "mic") { startRecording() }
                }
            }
            Section {
                if !viewModel.isIncognito {
                    Toggle(isOn: Binding(get: { viewModel.memoryEnabled }, set: { viewModel.setMemoryEnabled($0) })) {
                        Label(L("Memory in This Chat", "Bu sohbette hafıza"), systemImage: "brain")
                    }
                }
                if !skills.skills.isEmpty {
                    Menu {
                        ForEach(skills.skills) { skill in
                            Toggle(skill.skill.name, isOn: Binding(
                                get: { viewModel.isSkillActive(skill) },
                                set: { viewModel.setSkill(skill, active: $0) }
                            ))
                        }
                    } label: {
                        let active = skills.skills.filter(viewModel.isSkillActive).count
                        Label(L("Skills (\(active) on)", "Skill'ler (\(active) açık)"), systemImage: "sparkles")
                    }
                }
            }
        } label: {
            Image(systemName: "plus")
                .font(.body.weight(.medium))
                .foregroundStyle(Palette.text)
                .frame(width: 30, height: 30)
                .background(Palette.background, in: .circle)
                .overlay(alignment: .topTrailing) {
                    // Hafıza bu sohbette kapalıysa küçük bir işaret
                    if !viewModel.usesMemory && !viewModel.isIncognito {
                        Circle().fill(Palette.yellow).frame(width: 8, height: 8)
                    }
                }
        }
        .disabled(viewModel.isStreaming || recorder.isRecording)
        .accessibilityLabel(L("Attach and options", "Ekle ve seçenekler"))
    }

    private func startRecording() {
        inputFocused = false
        Task {
            do {
                let granted = try await recorder.start()
                if !granted {
                    viewModel.errorMessage = L("Microphone access is off. Turn it on in Settings > AI Assistant.",
                                               "Mikrofon izni kapalı. Ayarlar > AI Assistant'tan açabilirsin.")
                }
            } catch {
                viewModel.errorMessage = userFacingMessage(for: error)
            }
        }
    }
}

private struct UserMessage: View {
    let text: String
    let attachments: [AttachmentPreview]
    let showImage: (UIImage) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if !attachments.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(attachments.enumerated()), id: \.offset) { _, preview in
                        AttachmentThumbnail(preview: preview, size: 72)
                            .onTapGesture {
                                // Tam boyutlu kopya yoksa (eski sohbetler) küçük resim gösterilir.
                                if let image = preview.file.flatMap(AttachmentFiles.image(named:))
                                    ?? preview.thumbnail.flatMap(UIImage.init(data:)) {
                                    showImage(image)
                                }
                            }
                    }
                }
            }
            if !text.isEmpty {
                Text(text)
                    .foregroundStyle(Palette.textBright)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Palette.elevated, in: .rect(cornerRadius: 18))
                    .contextMenu {
                        Button(L("Copy", "Kopyala"), systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = text
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.leading, 48)
    }
}

/// Balonsuz, tam genişlikte asistan cevabı; üstte araç etkinlikleri, altta dosyalar ve kaynaklar.
private struct AssistantMessage: View {
    @Environment(SpeechReader.self) private var speech
    let item: ChatItem
    let isStreaming: Bool
    let openDocument: (DocumentFile) -> Void
    let selectText: (String) -> Void
    let showImage: (UIImage) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !item.activities.isEmpty {
                ToolLog(activities: item.activities, isStreaming: isStreaming)
            }

            if !item.text.isEmpty {
                Markdown(item.text)
                    .markdownTheme(.atomOneDark)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .contextMenu {
                        Button(L("Copy", "Kopyala"), systemImage: "doc.on.doc") {
                            UIPasteboard.general.string = plainText(fromMarkdown: item.text)
                        }
                        Button(L("Select Text", "Metni seç"), systemImage: "selection.pin.in.out") {
                            selectText(plainText(fromMarkdown: item.text))
                        }
                        if speech.speakingID == item.id {
                            Button(L("Stop Reading", "Okumayı durdur"), systemImage: "stop.circle") {
                                speech.stop()
                            }
                        } else {
                            Button(L("Read Aloud", "Sesli oku"), systemImage: "speaker.wave.2") {
                                speech.toggle(item.id, text: plainText(fromMarkdown: item.text))
                            }
                        }
                    }
                    .disabled(isStreaming)
            } else if isStreaming, item.activities.allSatisfy({ $0.state != .running }) {
                ProgressView()
                    .tint(Palette.textMuted)
            }

            ForEach(item.images ?? [], id: \.self) { name in
                GeneratedImageView(name: name, show: showImage)
            }

            ForEach(item.files, id: \.self) { name in
                let document = DocumentFile(url: DocumentFile.directory.appendingPathComponent(name))
                FileCard(document: document) {
                    openDocument(document)
                }
            }

            if !isStreaming, item.usage != nil || item.stopped == true {
                MessageFooter(usage: item.usage, stopped: item.stopped == true)
            }

            if !item.sources.isEmpty {
                SourceList(sources: item.sources)
            }
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
                    Text(L("Markdown · tap to open", "Markdown · dokun ve aç"))
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
