import AgentCore
import SwiftUI

/// Bir sağlayıcının adresini, key'ini ve modellerini düzenler.
struct ProviderEditorView: View {
    /// `nil` ise yeni sağlayıcı.
    let provider: Provider?

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var draft = Provider(name: "", baseURL: "", models: [])
    @State private var apiKey = ""
    @State private var newModelName = ""
    @State private var errorMessage: String?
    @State private var isFetching = false
    @State private var fetchedModels: FetchedModels?
    @State private var confirmingDelete = false

    var body: some View {
        Form {
            Section {
                TextField(L("Name", "Ad"), text: $draft.name, prompt: prompt(L("Name (e.g. Evren)", "Ad (örn. Evren)")))
                TextField("Base URL", text: $draft.baseURL, prompt: prompt("https://router.example.com/v1"))
                    .keyboardType(.URL)
                    .textContentType(.URL)
                SecureField("API key", text: $apiKey, prompt: prompt("API key"))
            } header: {
                header(L("Connection", "Bağlantı"))
            } footer: {
                footer(L("Address of the OpenAI-compatible endpoint, including /v1. HTTPS only. The key is stored only in this device's Keychain.", "OpenAI-uyumlu endpoint'in /v1 dahil adresi. Sadece HTTPS. Key yalnızca bu cihazın Keychain'inde saklanır."))
            }
            .listRowBackground(Palette.surface)

            Section {
                ForEach($draft.models) { $model in
                    Toggle(isOn: $model.supportsEffort) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.name)
                                .foregroundStyle(Palette.textBright)
                            Text(model.supportsEffort ? L("Effort selectable", "Efor seçilebilir") : L("Effort selection off", "Efor seçimi kapalı"))
                                .font(.caption)
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                }
                .onDelete { draft.models.remove(atOffsets: $0) }

                HStack {
                    TextField(L("Model name", "Model adı"), text: $newModelName, prompt: prompt(L("Add model name", "Model adı ekle")))
                        .onSubmit(addModel)
                    Button(action: addModel) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .disabled(newModelName.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Button(action: fetchModels) {
                    HStack {
                        Label(L("Fetch Models from Server", "Sunucudan modelleri getir"), systemImage: "arrow.down.circle")
                        if isFetching {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isFetching)
            } header: {
                header(L("Models", "Modeller"))
            } footer: {
                footer(L("If a model supports reasoning_effort, turn on its switch to pick Low/Medium/High in the chat. Swipe left to delete.", "Model reasoning_effort destekliyorsa \"Efor\" anahtarını aç; sohbet ekranında Düşük/Orta/Yüksek seçebilirsin. Silmek için sola kaydır."))
            }
            .listRowBackground(Palette.surface)

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(Palette.red)
                }
                .listRowBackground(Palette.surface)
            }

            if provider != nil {
                Section {
                    Button(L("Delete Provider", "Sağlayıcıyı sil"), role: .destructive) { confirmingDelete = true }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .foregroundStyle(Palette.textBright)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(provider == nil ? L("New Provider", "Yeni sağlayıcı") : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Save", "Kaydet"), action: save)
                    .fontWeight(.semibold)
            }
        }
        .confirmationDialog(L("Delete this provider and its models?", "Sağlayıcı ve modelleri silinsin mi?"), isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button(L("Delete", "Sil"), role: .destructive) {
                if let provider { settings.deleteProvider(provider.id) }
                dismiss()
            }
        }
        .sheet(item: $fetchedModels) { fetched in
            ModelPickerSheet(available: fetched.names, existing: Set(draft.models.map(\.name))) { picked in
                draft.models += picked.map { ModelProfile(name: $0) }
            }
        }
        .onAppear {
            if let provider {
                draft = provider
                apiKey = settings.apiKey(for: provider.id)
            }
        }
    }

    private func addModel() {
        let name = newModelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !draft.models.contains(where: { $0.name == name }) else { return }
        draft.models.append(ModelProfile(name: name))
        newModelName = ""
    }

    private func fetchModels() {
        errorMessage = nil
        isFetching = true
        Task {
            defer { isFetching = false }
            do {
                let names = try await LLMClient.listModels(baseURL: draft.baseURL, apiKey: apiKey, transport: URLSessionTransport())
                if names.isEmpty {
                    errorMessage = L("The server returned no models; you can add model names manually.", "Sunucu model listesi döndürmedi; model adlarını elle ekleyebilirsin.")
                } else {
                    fetchedModels = FetchedModels(names: names)
                }
            } catch {
                errorMessage = userFacingMessage(for: error)
            }
        }
    }

    private func save() {
        do {
            try settings.save(draft, apiKey: apiKey)
            dismiss()
        } catch {
            errorMessage = userFacingMessage(for: error)
        }
    }
}

private struct FetchedModels: Identifiable {
    let id = UUID()
    let names: [String]
}

/// Sunucudan gelen modellerden eklenecekleri seçtirir.
private struct ModelPickerSheet: View {
    let available: [String]
    let existing: Set<String>
    let add: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: Set<String> = []
    @State private var search = ""

    private var filtered: [String] {
        search.isEmpty ? available : available.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered, id: \.self) { name in
                let alreadyAdded = existing.contains(name)
                Button {
                    if picked.contains(name) { picked.remove(name) } else { picked.insert(name) }
                } label: {
                    HStack {
                        Text(name)
                            .foregroundStyle(alreadyAdded ? Palette.textMuted : Palette.textBright)
                        Spacer()
                        if alreadyAdded {
                            Text(L("Added", "Ekli")).font(.caption).foregroundStyle(Palette.textMuted)
                        } else if picked.contains(name) {
                            Image(systemName: "checkmark").foregroundStyle(Palette.blue)
                        }
                    }
                }
                .disabled(alreadyAdded)
                .listRowBackground(Palette.surface)
            }
            .searchable(text: $search, prompt: L("Search models", "Model ara"))
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(L("Models", "Modeller"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Vazgeç")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Add (\(picked.count))", "Ekle (\(picked.count))")) {
                        add(available.filter(picked.contains))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(picked.isEmpty)
                }
            }
        }
    }
}
