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
                    NavigationLink {
                        ModelSettingsView(model: $model)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.name)
                                .foregroundStyle(Palette.textBright)
                            CapabilityBadges(model: model)
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
                footer(L(
                    "Tap a model to set what it supports (effort, images, audio, image generation). Fetching from the server fills these in when the server reports them. Swipe left to delete.",
                    "Bir modele dokunarak neleri desteklediğini ayarla (efor, görsel, ses, görsel üretme). Sunucu bildiriyorsa sunucudan getirince bunlar otomatik dolar. Silmek için sola kaydır."
                ))
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
            ModelPickerSheet(available: fetched.models.map(\.id), existing: Set(draft.models.map(\.name))) { picked in
                let infos = Dictionary(fetched.models.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
                draft.models += picked.map { name in
                    var model = ModelProfile(name: name)
                    if let info = infos[name] { model.apply(info) }
                    return model
                }
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
                let models = try await LLMClient.listModels(baseURL: draft.baseURL, apiKey: apiKey, transport: URLSessionTransport())
                // Zaten ekli modellerin, sunucunun bildirdiği ama henüz ayarlanmamış yeteneklerini doldur.
                for index in draft.models.indices {
                    if let info = models.first(where: { $0.id == draft.models[index].name }) {
                        draft.models[index].apply(info, overwrite: false)
                    }
                }
                if models.isEmpty {
                    errorMessage = L("The server returned no models; you can add model names manually.", "Sunucu model listesi döndürmedi; model adlarını elle ekleyebilirsin.")
                } else {
                    fetchedModels = FetchedModels(models: models)
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
    let models: [ModelInfo]
}

/// Modelin desteklediği özellikler; sunucu bildirmediyse burada elle ayarlanır.
private struct ModelSettingsView: View {
    @Binding var model: ModelProfile

    var body: some View {
        Form {
            Section {
                TextField(L("Model name", "Model adı"), text: $model.name)
                    .foregroundStyle(Palette.textBright)
            }
            .listRowBackground(Palette.surface)

            Section {
                Toggle(L("Reasoning effort", "Düşünme eforu"), isOn: $model.supportsEffort)
                Toggle(L("Image input", "Görsel girdisi"), isOn: flag(\.acceptsImages))
                Toggle(L("Audio input", "Ses girdisi"), isOn: flag(\.acceptsAudio))
                Toggle(L("Generates images", "Görsel üretir"), isOn: flag(\.generatesImages))
            } header: {
                header(L("Capabilities", "Yetenekler"))
            } footer: {
                footer(L(
                    "Effort sends reasoning_effort. Image and audio input add attach buttons in the chat. Image generation sends your message to /images/generations instead of chat.",
                    "Efor, reasoning_effort gönderir. Görsel ve ses girdisi sohbette ekleme butonlarını açar. Görsel üretme, mesajını sohbet yerine /images/generations'a gönderir."
                ))
            }
            .listRowBackground(Palette.surface)
        }
        .foregroundStyle(Palette.textBright)
        .tint(Palette.blue)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(model.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func flag(_ keyPath: WritableKeyPath<ModelProfile, Bool?>) -> Binding<Bool> {
        Binding(
            get: { model[keyPath: keyPath] == true },
            set: { model[keyPath: keyPath] = $0 }
        )
    }
}

/// Model satırında desteklenen özelliklerin küçük simgeleri.
private struct CapabilityBadges: View {
    let model: ModelProfile

    var body: some View {
        let badges: [(String, String)] = [
            model.supportsEffort ? ("gauge.with.dots.needle.50percent", L("Effort", "Efor")) : nil,
            model.acceptsImages == true ? ("photo", L("Image", "Görsel")) : nil,
            model.acceptsAudio == true ? ("waveform", L("Audio", "Ses")) : nil,
            model.generatesImages == true ? ("paintbrush", L("Generates images", "Görsel üretir")) : nil,
        ].compactMap { $0 }

        if badges.isEmpty {
            Text(L("Text only", "Sadece metin"))
                .font(.caption)
                .foregroundStyle(Palette.textMuted)
        } else {
            HStack(spacing: 8) {
                ForEach(badges, id: \.0) { icon, title in
                    Label(title, systemImage: icon)
                }
            }
            .font(.caption)
            .foregroundStyle(Palette.cyan)
        }
    }
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
