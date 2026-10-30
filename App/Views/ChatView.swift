import AgentCore
import MarkdownUI
import PhotosUI
import SwiftData
import SwiftUI

struct ChatView: View {
    private enum Route: Hashable {
        case conversations, projects, documents, scheduled
        case project(UUID)
    }

    @Environment(AppSettings.self) private var settings
    @Environment(UsageTracker.self) private var usage
    @Environment(SkillLibrary.self) private var skills
    @Environment(ConnectorLibrary.self) private var connectors
    @Environment(PromptLibrary.self) private var prompts
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
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
    @State private var sharedFile: SharedFile?
    @State private var newPrompt: SavedPrompt?
    @State private var sidebarOpen = false
    /// Kenar menüsü sürüklenirken parmağın yatay yer değiştirmesi.
    @State private var dragTranslation: CGFloat = 0
    @State private var renaming: ConversationRecord?
    @State private var renameText = ""
    @State private var deleting: ConversationRecord?
    @Query(sort: \ProjectRecord.createdAt, order: .reverse) private var projects: [ProjectRecord]
    @Query private var conversations: [ConversationRecord]
    @FocusState private var inputFocused: Bool

    /// Açık sohbetin kaydı; henüz kaydedilmemişse veya gizliyse `nil`.
    private var currentRecord: ConversationRecord? {
        viewModel.conversationID.flatMap { id in conversations.first { $0.id == id } }
    }

    var body: some View {
        GeometryReader { geometry in
            let width = min(geometry.size.width * 0.85, 360)
            let offset = min(max((sidebarOpen ? width : 0) + dragTranslation, 0), width)
            ZStack(alignment: .leading) {
                sidebar
                    .frame(width: width)
                    .offset(x: offset - width)
                chatStack
                    .offset(x: offset)
                    .overlay {
                        if offset > 0 {
                            Color.black
                                .opacity(0.3 * offset / width)
                                .ignoresSafeArea()
                                .offset(x: offset)
                                .onTapGesture { setSidebar(open: false) }
                        }
                    }
            }
            // Sohbetin her yerinden sağa çekince açılır; açık sayfalarda (geri kaydırma) devre dışı.
            .simultaneousGesture(sidebarDrag(width: width), including: path.isEmpty ? .all : .subviews)
        }
    }

    private var sidebar: some View {
        SidebarView(
            currentID: viewModel.conversationID,
            openChat: { record in
                viewModel.open(record)
                path = []
                setSidebar(open: false)
            },
            openProjects: { show(.projects) },
            openProject: { show(.project($0.id)) },
            openDocuments: { show(.documents) },
            openScheduled: { show(.scheduled) },
            search: { show(.conversations) },
            openSettings: {
                showingSettings = true
                setSidebar(open: false)
            },
            newChat: {
                viewModel.startNewChat()
                path = []
                setSidebar(open: false)
            },
            chatMenu: { record in chatMenu(for: record) }
        )
    }

    private func show(_ route: Route) {
        path = [route]
        setSidebar(open: false)
    }

    private func setSidebar(open: Bool) {
        inputFocused = false
        withAnimation(.snappy(duration: 0.25)) {
            sidebarOpen = open
            dragTranslation = 0
        }
    }

    private func sidebarDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Dikey kaydırmayı (mesaj listesi) bölmesin: yatay hareket baskınsa başla.
                guard dragTranslation != 0 || abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
                if dragTranslation == 0 { inputFocused = false }
                dragTranslation = value.translation.width
            }
            .onEnded { value in
                guard dragTranslation != 0 else { return }
                let end = (sidebarOpen ? width : 0) + value.predictedEndTranslation.width
                setSidebar(open: end > width / 2)
            }
    }

    private var chatStack: some View {
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
                    if viewModel.fallbackPromptProviderID != nil {
                        fallbackPrompt
                    }
                }
                composer
            }
            .background(Palette.background)
            .navigationTitle(viewModel.isIncognito ? L("Incognito Chat", "Gizli sohbet") : (viewModel.projectName ?? "CHAY"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        setSidebar(open: true)
                    } label: {
                        Image(systemName: "line.3.horizontal")
                            .foregroundStyle(Palette.text)
                    }
                    .accessibilityLabel(L("Menu", "Menü"))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Yeni sohbette gizli sohbet düğmesi; mesaj gönderilince yerini sohbet menüsü alır.
                    if viewModel.isIncognito || viewModel.items.isEmpty {
                        Button {
                            inputFocused = false
                            viewModel.startNewChat(incognito: !viewModel.isIncognito)
                        } label: {
                            Image(systemName: viewModel.isIncognito ? "eye.slash.fill" : "eye.slash")
                                .foregroundStyle(viewModel.isIncognito ? Palette.purple : (viewModel.isStreaming ? Palette.textMuted : Palette.text))
                        }
                        .disabled(viewModel.isStreaming)
                        .accessibilityLabel(viewModel.isIncognito ? L("Leave Incognito", "Gizli sohbetten çık") : L("Incognito Chat", "Gizli sohbet"))
                    } else if let record = currentRecord {
                        Menu {
                            chatMenu(for: record)
                        } label: {
                            Image(systemName: "ellipsis")
                                .foregroundStyle(viewModel.isStreaming ? Palette.textMuted : Palette.text)
                        }
                        .disabled(viewModel.isStreaming)
                        .accessibilityLabel(L("Chat options", "Sohbet seçenekleri"))
                    }
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
                case .projects:
                    ProjectsView(
                        startChat: { project in
                            viewModel.startNewChat(project: project)
                            path = []
                        },
                        openChat: { record in
                            viewModel.open(record)
                            path = []
                        }
                    )
                case .documents: DocumentsView()
                case .scheduled:
                    // Kestirme isteğiyle aynı yoldan: yeni sohbet, görevin modeli.
                    ScheduledTasksView(run: { ShortcutInbox.put($0.request) })
                case let .project(id):
                    if let project = projects.first(where: { $0.id == id }) {
                        ProjectDetailView(
                            project: project,
                            startChat: { project in
                                viewModel.startNewChat(project: project)
                                path = []
                            },
                            openChat: { record in
                                viewModel.open(record)
                                path = []
                            }
                        )
                    }
                }
            }
            .alert(
                viewModel.pendingApproval?.request.toolName == "save_note"
                    ? L("Save to memory?", "Hafızaya kaydedilsin mi?")
                    : L("Allow this action?", "Bu işleme izin verilsin mi?"),
                isPresented: Binding(
                    get: { viewModel.pendingApproval != nil },
                    set: { if !$0 { viewModel.resolveApproval(false) } }
                ),
                presenting: viewModel.pendingApproval
            ) { pending in
                let isNote = pending.request.toolName == "save_note"
                Button(L("Decline", "Reddet"), role: .cancel) { viewModel.resolveApproval(false) }
                Button(isNote ? L("Save", "Kaydet") : L("Allow", "İzin ver")) { viewModel.resolveApproval(true) }
            } message: { pending in
                if pending.request.toolName == "save_note" {
                    Text(L(
                        "The assistant read web content in this chat and wants to save:\n\n\(pending.request.detail ?? "")",
                        "Asistan bu sohbette web içeriği okudu ve şunu kaydetmek istiyor:\n\n\(pending.request.detail ?? "")"
                    ))
                } else {
                    Text(L(
                        "The assistant wants to run a tool that can change data:\n\n\(pending.request.detail ?? pending.request.toolName)\n\n\(approvalArguments(pending.request.arguments))",
                        "Asistan veri değiştirebilen bir araç çalıştırmak istiyor:\n\n\(pending.request.detail ?? pending.request.toolName)\n\n\(approvalArguments(pending.request.arguments))"
                    ))
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
            .sheet(item: Binding(
                get: { viewModel.pendingConnectorSetup },
                set: { _ in }
            )) { setup in
                ConnectorSetupSheet(
                    setup: setup,
                    connect: { try await viewModel.finishConnectorSetup(token: $0, clientID: $1) },
                    cancel: { viewModel.closeConnectorSetup() }
                )
            }
            .confirmationDialog(
                limitTitle,
                isPresented: Binding(
                    get: { viewModel.limitPrompt != nil },
                    set: { if !$0 { viewModel.dismissLimitPrompt() } }
                ),
                titleVisibility: .visible,
                presenting: viewModel.limitPrompt
            ) { prompt in
                ForEach(settings.allModels.filter { $0.model.id != prompt.model.id }) { option in
                    Button("\(option.model.name) · \(option.provider.name)") {
                        viewModel.chooseLimitFallback(option.model.id, using: settings)
                    }
                }
                Button(L("Cancel", "Vazgeç"), role: .cancel) { viewModel.dismissLimitPrompt() }
            } message: { _ in
                Text(L("Choose the model to continue with until the limit resets. It's saved as this model's fallback; you can change it in the model's settings.",
                       "Limit yenilenene kadar devam edilecek modeli seç. Bu modelin yedeği olarak kaydedilir; modelin ayarlarından değiştirebilirsin."))
            }
            .alert(L("Rename Chat", "Sohbeti yeniden adlandır"), isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField(L("Chat name", "Sohbet adı"), text: $renameText)
                Button(L("Cancel", "Vazgeç"), role: .cancel) { renaming = nil }
                Button(L("Save", "Kaydet")) {
                    if let renaming { rename(renaming, to: renameText) }
                    renaming = nil
                }
            }
            .confirmationDialog(
                L("Delete this chat?", "Bu sohbet silinsin mi?"),
                isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                titleVisibility: .visible,
                presenting: deleting
            ) { record in
                Button(L("Delete", "Sil"), role: .destructive) { delete(record) }
            } message: { _ in
                Text(L("This can't be undone.", "Bu işlem geri alınamaz."))
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
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: documentContentTypes) { result in
                guard case let .success(url) = result else { return }
                guard let text = extractDocumentText(from: url) else {
                    viewModel.errorMessage = L("Couldn't read the file.", "Dosya okunamadı.")
                    return
                }
                viewModel.addDocument(text: text, name: url.lastPathComponent)
            }
            .sheet(item: $sharedFile) { file in
                ShareSheet(items: [file.url])
                    .presentationDetents([.medium, .large])
            }
            .sheet(item: $newPrompt) { prompt in
                PromptEditor(original: prompt)
            }
            .sheet(item: $selectingText) { item in
                SelectableTextSheet(item: item)
            }
            .sheet(item: $openedDocument) { document in
                if document.isArtifact {
                    ArtifactView(document: document)
                } else {
                    NavigationStack {
                        DocumentView(document: document)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L("Close", "Kapat")) { openedDocument = nil }
                            }
                        }
                    }
                }
            }
            .onAppear {
                viewModel.attach(modelContext, usage: usage, skills: skills, connectors: connectors)
                if !settings.isConfigured {
                    showingSettings = true
                }
                runShortcutRequest()
            }
            .onReceive(NotificationCenter.default.publisher(for: ShortcutInbox.didReceive)) { _ in
                runShortcutRequest()
            }
            .onChange(of: scenePhase) {
                switch scenePhase {
                case .background: viewModel.appMovedToBackground()
                case .active:
                    viewModel.appBecameActive()
                    runShortcutRequest()
                default: break
                }
            }
        }
    }

    /// Kestirmeler'den gelen istek varsa seçilen modelle yeni sohbet başlatıp gönderir.
    private func runShortcutRequest() {
        guard !viewModel.isStreaming, let request = ShortcutInbox.take() else { return }
        // Bildirim ekran ilk kez görünmeden gelebilir; bağlam hazır olsun.
        viewModel.attach(modelContext, usage: usage, skills: skills, connectors: connectors)
        path = []
        // Kestirmenin modeli sadece bu sohbette kullanılır; Ayarlar'daki seçim değişmez.
        viewModel.startNewChat(modelOverride: request.modelID)
        // Kestirmeden gelen dosyalar: görseller görsel olarak, diğerleri metni çıkarılarak eklenir.
        var unreadable: [String] = []
        for file in request.files ?? [] {
            let url = ShortcutInbox.directory.appendingPathComponent(file.storedName)
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url) else {
                unreadable.append(file.originalName)
                continue
            }
            if UIImage(data: data) != nil {
                viewModel.addImage(data)
            } else if let text = extractDocumentText(from: url), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                viewModel.addDocument(text: text, name: file.originalName)
            } else {
                unreadable.append(file.originalName)
            }
        }
        viewModel.input = request.prompt
        viewModel.send(using: settings)
        // Gönderim hata mesajını temizlediği için okunamayan dosyalar en son bildirilir.
        if !unreadable.isEmpty {
            let note = L("Couldn't read the file: \(unreadable.joined(separator: ", "))",
                         "Dosya okunamadı: \(unreadable.joined(separator: ", "))")
            viewModel.errorMessage = [viewModel.errorMessage, note].compactMap { $0 }.joined(separator: "\n")
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(viewModel.items) { item in
                        switch item.role {
                        case .user:
                            UserMessage(
                                text: item.text,
                                attachments: item.attachments ?? [],
                                showImage: { viewedImage = ViewedImage(image: $0) },
                                edit: viewModel.canEdit(item) ? {
                                    viewModel.beginEditing(item)
                                    inputFocused = true
                                } : nil,
                                variant: viewModel.variantPosition(of: item),
                                showVariant: { viewModel.showVariant($0, at: item) },
                                isStreaming: viewModel.isStreaming
                            )
                            .id(item.id)
                        case .assistant:
                            AssistantMessage(
                                item: item,
                                isStreaming: viewModel.isStreaming && item.id == viewModel.items.last?.id,
                                openDocument: { openedDocument = $0 },
                                selectText: { selectingText = SelectableTextItem(text: $0) },
                                showImage: { viewedImage = ViewedImage(image: $0) },
                                regenerate: item.id == viewModel.items.last?.id && viewModel.canRegenerate ? { modelID in
                                    if let modelID {
                                        viewModel.clearModelOverride()
                                        settings.select(modelID)
                                    }
                                    viewModel.regenerate(using: settings)
                                } : nil,
                                variant: viewModel.variantPosition(of: item),
                                showVariant: { viewModel.showVariant($0, at: item) }
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
            if viewModel.editingItemID != nil {
                HStack {
                    Label(L("Editing message", "Mesaj düzenleniyor"), systemImage: "pencil")
                        .foregroundStyle(Palette.yellow)
                    Spacer()
                    Button(L("Cancel", "Vazgeç")) { viewModel.cancelEditing() }
                        .foregroundStyle(Palette.textMuted)
                }
                .font(.footnote)
            }
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
                ModelMenu(overrideID: viewModel.modelOverrideID, onSelect: viewModel.clearModelOverride)
                EffortMenu(overrideID: viewModel.modelOverrideID)
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
        let model = settings.selection(for: viewModel.modelOverrideID)?.model
        return Menu {
            Section {
                if model?.acceptsImages == true {
                    if CameraPicker.isAvailable {
                        Button(L("Camera", "Kamera"), systemImage: "camera") { showingCamera = true }
                    }
                    Button(L("Photo", "Fotoğraf"), systemImage: "photo") { showingPhotoPicker = true }
                }
                Button(L("Document (PDF, Word, Excel…)", "Doküman (PDF, Word, Excel…)"), systemImage: "doc.text") { showingFileImporter = true }
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
                Menu {
                    ForEach(prompts.prompts) { prompt in
                        Button(prompt.title) {
                            viewModel.input = prompt.text + viewModel.input
                            inputFocused = true
                        }
                    }
                    if !viewModel.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Divider()
                        Button(L("Save Text as Prompt", "Metni komut olarak kaydet"), systemImage: "plus") {
                            newPrompt = SavedPrompt(title: "", text: viewModel.input)
                        }
                    }
                } label: {
                    Label(L("Prompts", "Hazır komutlar"), systemImage: "text.badge.star")
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
                if !connectors.connectors.isEmpty {
                    Menu {
                        ForEach(connectors.connectors) { connector in
                            Toggle(isOn: Binding(
                                get: { viewModel.isConnectorActive(connector) },
                                set: { viewModel.setConnector(connector, active: $0) }
                            )) {
                                Text(connector.name)
                                if connectors.needsSignIn.contains(connector.id) {
                                    Text(L("Sign in required", "Giriş gerekiyor"))
                                }
                            }
                        }
                    } label: {
                        let active = connectors.connectors.filter(viewModel.isConnectorActive).count
                        Label(L("Connectors (\(active) on)", "Bağlayıcılar (\(active) açık)"), systemImage: "point.3.connected.trianglepath.dotted")
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

    /// Yoğunluk hatasında: yedek seçilmemişse uyarı ve seçim menüsü.
    private var fallbackPrompt: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(L("This provider has no fallback model.", "Bu sağlayıcı için yedek model seçilmemiş."))
                .foregroundStyle(Palette.yellow)
                .frame(maxWidth: .infinity, alignment: .leading)
            Menu(L("Choose", "Seç")) {
                ForEach(settings.allModels.filter { $0.model.generatesImages != true && $0.model.id != settings.selection(for: viewModel.modelOverrideID)?.model.id }) { option in
                    Button("\(option.model.name) · \(option.provider.name)") {
                        viewModel.chooseFallback(option.model.id, using: settings)
                    }
                }
            }
            .fontWeight(.semibold)
            .foregroundStyle(Palette.blue)
        }
        .font(.footnote)
        .padding(.horizontal, 20)
        .padding(.top, 6)
    }

    private var limitTitle: String {
        guard let prompt = viewModel.limitPrompt else { return "" }
        return L("\(prompt.model.name) reached its \(prompt.period.title) token limit",
                 "\(prompt.model.name) \(prompt.period.title) token limitini doldurdu")
    }

    // MARK: - Sohbet menüsü (sağ üst ve kenar menüsünde basılı tutunca)

    @ViewBuilder
    private func chatMenu(for record: ConversationRecord) -> some View {
        Button(record.isPinned ? L("Unpin", "Sabitlemeyi kaldır") : L("Pin", "Sabitle"),
               systemImage: record.isPinned ? "pin.slash" : "pin") {
            record.isPinned.toggle()
            try? modelContext.save()
        }
        Divider()
        Menu {
            Button("Markdown (.md)", systemImage: "doc.plaintext") { share(record, pdf: false) }
            Button("PDF", systemImage: "doc.richtext") { share(record, pdf: true) }
        } label: {
            Label(L("Share", "Paylaş"), systemImage: "square.and.arrow.up")
        }
        Button(L("Rename", "Yeniden adlandır"), systemImage: "pencil") {
            renameText = record.title
            renaming = record
        }
        Menu {
            if projects.isEmpty {
                Text(L("No projects yet", "Henüz proje yok"))
            }
            ForEach(projects) { project in
                Button(project.name, systemImage: record.projectID == project.id ? "checkmark" : "folder") {
                    move(record, to: project)
                }
            }
            if record.projectID != nil {
                Divider()
                Button(L("Remove from Project", "Projeden çıkar"), systemImage: "folder.badge.minus") {
                    move(record, to: nil)
                }
            }
        } label: {
            Label(L("Add to Project", "Projeye ekle"), systemImage: "folder.badge.plus")
        }
        Divider()
        Button(L("Delete", "Sil"), systemImage: "trash", role: .destructive) {
            deleting = record
        }
    }

    private func share(_ record: ConversationRecord, pdf: Bool) {
        let title = record.title
        let items = record.id == viewModel.conversationID ? viewModel.items : record.content.items
        do {
            let url = pdf
                ? try ChatExport.temporaryFile(named: title, extension: "pdf", data: ChatExport.pdf(title: title, items: items))
                : try ChatExport.temporaryFile(named: title, extension: "md", data: Data(ChatExport.markdown(title: title, items: items).utf8))
            sharedFile = SharedFile(url: url)
        } catch {
            viewModel.errorMessage = userFacingMessage(for: error)
        }
    }

    /// Boş ad verilirse ilk mesajdan üretilen başlığa döner.
    private func rename(_ record: ConversationRecord, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        record.customTitle = trimmed.isEmpty ? nil : trimmed
        record.title = trimmed.isEmpty ? ConversationRecord.title(for: record.content) : trimmed
        try? modelContext.save()
    }

    private func move(_ record: ConversationRecord, to project: ProjectRecord?) {
        record.projectID = project?.id
        try? modelContext.save()
        if record.id == viewModel.conversationID {
            viewModel.setProject(project)
        }
    }

    private func delete(_ record: ConversationRecord) {
        if record.id == viewModel.conversationID {
            viewModel.startNewChat()
        }
        // Sohbetteki görsellerin tam boyutlu kopyalarını da sil.
        AttachmentFiles.delete(record.content.allItems.flatMap { $0.attachments ?? [] }.compactMap(\.file))
        modelContext.delete(record)
        try? modelContext.save()
    }

    private func startRecording() {
        inputFocused = false
        Task {
            do {
                let granted = try await recorder.start()
                if !granted {
                    viewModel.errorMessage = L("Microphone access is off. Turn it on in Settings > CHAY.",
                                               "Mikrofon izni kapalı. Ayarlar > CHAY'dan açabilirsin.")
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
    /// `nil` ise mesaj düzenlenemez (ör. bağlam sıkıştırmasıyla özetlenmiş eski mesaj).
    let edit: (() -> Void)?
    /// Mesaj düzenlendiyse alternatiflerden kaçıncısı olduğu.
    let variant: (current: Int, count: Int)?
    let showVariant: (Int) -> Void
    let isStreaming: Bool

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
                        if let edit {
                            Button(L("Edit", "Düzenle"), systemImage: "pencil", action: edit)
                        }
                    }
            }
            if let variant {
                VariantPager(position: variant, show: showVariant)
                    .disabled(isStreaming)
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
    /// Son cevapta: aynı (`nil`) veya seçilen modelle yeniden üret.
    let regenerate: ((UUID?) -> Void)?
    /// Cevap yeniden üretildiyse alternatiflerden kaçıncısı olduğu.
    let variant: (current: Int, count: Int)?
    let showVariant: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let notice = item.notice {
                Label(notice, systemImage: "gauge.with.dots.needle.100percent")
                    .font(.caption)
                    .foregroundStyle(Palette.yellow)
            }

            if let reasoning = item.reasoning, !reasoning.isEmpty {
                ThinkingView(text: reasoning, isActive: isStreaming && item.text.isEmpty && item.preparing == nil)
            }

            if !item.activities.isEmpty {
                ToolLog(activities: item.activities, isStreaming: isStreaming)
            }

            if isStreaming, let preparing = item.preparing {
                PreparingRow(preparing: preparing)
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
            } else if isStreaming, item.preparing == nil, item.reasoning?.isEmpty ?? true,
                      item.activities.allSatisfy({ $0.state != .running }) {
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

            if !isStreaming, item.usage != nil || item.stopped == true || regenerate != nil || variant != nil {
                HStack(spacing: 12) {
                    if let variant {
                        VariantPager(position: variant, show: showVariant)
                    }
                    MessageFooter(usage: item.usage, stopped: item.stopped == true)
                    Spacer()
                    if let regenerate {
                        RegenerateMenu(regenerate: regenerate)
                    }
                }
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
                Image(systemName: document.isArtifact ? "play.rectangle" : "doc.richtext")
                    .font(.title3)
                    .foregroundStyle(document.isArtifact ? Palette.purple : Palette.blue)
                    .frame(width: 36, height: 36)
                    .background(Palette.background, in: .rect(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.name)
                        .lineLimit(1)
                        .foregroundStyle(Palette.textBright)
                    Text(document.isArtifact
                         ? L("Interactive page · tap to open", "Etkileşimli sayfa · dokun ve aç")
                         : L("Markdown · tap to open", "Markdown · dokun ve aç"))
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

/// Son cevabın altında: dokununca aynı modelle, menüden başka bir modelle yeniden üretir.
private struct RegenerateMenu: View {
    @Environment(AppSettings.self) private var settings
    let regenerate: (UUID?) -> Void

    var body: some View {
        Menu {
            Button(L("Regenerate", "Yeniden üret"), systemImage: "arrow.clockwise") { regenerate(nil) }
            ForEach(settings.providers) { provider in
                Section(L("With \(provider.name)", "\(provider.name) ile")) {
                    ForEach(provider.models) { model in
                        Button(model.name) { regenerate(model.id) }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.footnote)
                .foregroundStyle(Palette.textMuted)
                .padding(6)
        } primaryAction: {
            regenerate(nil)
        }
        .accessibilityLabel(L("Regenerate", "Yeniden üret"))
    }
}

/// Onay penceresinde araç argümanları: düzenli JSON, en fazla 600 karakter.
private func approvalArguments(_ arguments: String?) -> String {
    guard let arguments, !arguments.isEmpty else { return "" }
    var text = arguments
    if let object = try? JSONSerialization.jsonObject(with: Data(arguments.utf8)),
       let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
        text = String(decoding: data, as: UTF8.self)
    }
    return text.count > 600 ? String(text.prefix(600)) + "…" : text
}

/// Alternatifler arasında geçiş: ‹ 2/3 ›
private struct VariantPager: View {
    let position: (current: Int, count: Int)
    /// -1 önceki, +1 sonraki.
    let show: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            Button {
                show(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .disabled(position.current <= 1)
            .accessibilityLabel(L("Previous version", "Önceki sürüm"))
            Text(verbatim: "\(position.current)/\(position.count)")
                .monospacedDigit()
            Button {
                show(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 28, height: 28)
                    .contentShape(.rect)
            }
            .disabled(position.current >= position.count)
            .accessibilityLabel(L("Next version", "Sonraki sürüm"))
        }
        .font(.caption)
        .foregroundStyle(Palette.textMuted)
    }
}
