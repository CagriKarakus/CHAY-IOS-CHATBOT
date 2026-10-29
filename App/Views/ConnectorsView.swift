import AgentCore
import SwiftUI

/// Bağlayıcılar (uzak MCP sunucuları): listeleme, varsayılan açık/kapalı, ekleme.
struct ConnectorsView: View {
    @Environment(ConnectorLibrary.self) private var library

    var body: some View {
        List {
            Section {
                ForEach(library.connectors) { connector in
                    NavigationLink {
                        ConnectorEditorView(connector: connector)
                    } label: {
                        Toggle(isOn: Binding(
                            get: { connector.enabledByDefault },
                            set: { library.setEnabledByDefault($0, for: connector.id) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connector.name)
                                    .foregroundStyle(Palette.textBright)
                                Text(verbatim: "\(URL(string: connector.url)?.host ?? connector.url) · " + L(
                                    "\(connector.enabledTools.count) tools",
                                    "\(connector.enabledTools.count) araç"
                                ))
                                    .font(.caption)
                                    .foregroundStyle(Palette.textMuted)
                                if library.needsSignIn.contains(connector.id) {
                                    Text(L("Sign in required", "Giriş gerekiyor"))
                                        .font(.caption2)
                                        .foregroundStyle(Palette.yellow)
                                }
                            }
                        }
                    }
                }
                .onDelete { offsets in
                    offsets.map { library.connectors[$0].id }.forEach(library.delete)
                }
                NavigationLink {
                    ConnectorEditorView(connector: nil)
                } label: {
                    Label(L("Add Connector", "Bağlayıcı ekle"), systemImage: "plus")
                        .foregroundStyle(Palette.blue)
                }
            } footer: {
                footer(L(
                    "Connectors are remote MCP servers. Their tools are offered to the model like web search. The switch sets whether a connector is on in new chats; you can change it per chat from the + menu. Tools that change data ask you before they run.",
                    "Bağlayıcılar uzak MCP sunucularıdır; araçları modele web araması gibi sunulur. Anahtar, bağlayıcının yeni sohbetlerde açık olup olmadığını belirler; her sohbette + menüsünden değiştirebilirsin. Veri değiştiren araçlar çalışmadan önce sana sorar."
                ))
            }
            .listRowBackground(Palette.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(L("Connectors", "Bağlayıcılar"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Bağlayıcı ekleme/düzenleme: adres, giriş yöntemi, bağlantı testi ve araçlar.
struct ConnectorEditorView: View {
    @Environment(ConnectorLibrary.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Connector
    @State private var token = ""
    @State private var working = false
    @State private var message: String?
    @State private var failed = false
    private let isNew: Bool

    init(connector: Connector?) {
        _draft = State(initialValue: connector ?? Connector(name: "", url: ""))
        isNew = connector == nil
    }

    /// Kaydedilmiş hali (araç listesi ve giriş durumu buradan okunur).
    private var saved: Connector? { library.connector(draft.id) }

    private var canSave: Bool {
        !draft.name.trimmingCharacters(in: .whitespaces).isEmpty
            && draft.url.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("https://")
    }

    var body: some View {
        Form {
            Section {
                TextField(L("Name", "Ad"), text: $draft.name, prompt: prompt(L("e.g. GitHub", "örn. GitHub")))
                TextField(L("Server URL", "Sunucu adresi"), text: $draft.url, prompt: prompt("https://example.com/mcp"))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                footer(L("The MCP server's address (Streamable HTTP, HTTPS only). Servers that run on a computer with a command (npx …) can't be used on the phone.",
                         "MCP sunucusunun adresi (Streamable HTTP, sadece HTTPS). Bilgisayarda komutla çalışan (npx …) sunucular telefonda kullanılamaz."))
            }
            .listRowBackground(Palette.surface)

            Section {
                Picker(L("Authentication", "Kimlik doğrulama"), selection: $draft.auth) {
                    ForEach(Connector.Auth.allCases) { auth in
                        Text(auth.title).tag(auth)
                    }
                }
                switch draft.auth {
                case .none:
                    EmptyView()
                case .token:
                    SecureField(L("Access token", "Erişim token'ı"), text: $token, prompt: prompt(L("Token or API key", "Token veya API key")))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                case .oauth:
                    TextField("Client ID", text: Binding(
                        get: { draft.oauthClientID ?? "" },
                        set: { draft.oauthClientID = $0.isEmpty ? nil : $0 }
                    ), prompt: prompt(L("Optional", "İsteğe bağlı")))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if library.isSignedIn(draft.id) {
                        Label(L("Signed in", "Giriş yapıldı"), systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Palette.green)
                        Button(L("Sign Out", "Çıkış yap"), role: .destructive) {
                            library.signOut(draft.id)
                        }
                    } else {
                        Button {
                            run { try await library.signIn(draft.id) }
                        } label: {
                            Label(L("Sign In", "Giriş yap"), systemImage: "person.badge.key")
                        }
                        .disabled(!canSave || working)
                    }
                }
            } footer: {
                footer(authFooter)
            }
            .foregroundStyle(Palette.textBright)
            .listRowBackground(Palette.surface)

            Section {
                Button {
                    run { try await library.refreshTools(draft.id) }
                } label: {
                    HStack {
                        Label(L("Test Connection", "Bağlantıyı test et"), systemImage: "bolt.horizontal")
                        if working {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(!canSave || working)
                if let message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(failed ? Palette.red : Palette.green)
                } else if let error = library.lastErrors[draft.id] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(Palette.red)
                }
            }
            .listRowBackground(Palette.surface)

            if let saved, !saved.tools.isEmpty {
                Section {
                    ForEach(saved.tools, id: \.name) { tool in
                        Toggle(isOn: Binding(
                            get: { !(library.connector(draft.id)?.disabledTools.contains(tool.name) ?? false) },
                            set: { library.setTool(tool.name, enabled: $0, in: draft.id) }
                        )) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(tool.title ?? tool.name)
                                        .foregroundStyle(Palette.textBright)
                                    if !tool.readOnly {
                                        Image(systemName: "pencil.circle")
                                            .foregroundStyle(Palette.yellow)
                                            .accessibilityLabel(L("Asks before running", "Çalışmadan önce sorar"))
                                    }
                                }
                                if let description = tool.description {
                                    Text(description)
                                        .font(.caption)
                                        .lineLimit(2)
                                        .foregroundStyle(Palette.textMuted)
                                }
                            }
                        }
                    }
                } header: {
                    header(L("Tools (\(saved.enabledTools.count) of \(saved.tools.count) on)",
                             "Araçlar (\(saved.tools.count) araçtan \(saved.enabledTools.count) açık)"))
                } footer: {
                    footer(L("Tools marked with a pencil can change data and ask you before each run. Turning off tools you don't need keeps the model's context small.",
                             "Kalem işaretli araçlar veri değiştirebilir ve her çalışmadan önce sana sorar. Kullanmadığın araçları kapatmak modelin bağlamını küçük tutar."))
                }
                .listRowBackground(Palette.surface)
            }

            if !isNew {
                Section {
                    Button(L("Delete Connector", "Bağlayıcıyı sil"), role: .destructive) {
                        library.delete(draft.id)
                        dismiss()
                    }
                }
                .listRowBackground(Palette.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle(isNew ? L("New Connector", "Yeni bağlayıcı") : draft.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(L("Save", "Kaydet")) {
                    saveDraft()
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .onAppear {
            token = library.token(for: draft.id)
        }
    }

    private var authFooter: String {
        switch draft.auth {
        case .none:
            L("For public servers that don't need an account.", "Hesap gerektirmeyen, herkese açık sunucular için.")
        case .token:
            L("Sent as \"Authorization: Bearer …\". Stored in the Keychain on this device only.",
              "\"Authorization: Bearer …\" olarak gönderilir. Sadece bu cihazın Keychain'inde saklanır.")
        case .oauth:
            L("Opens the service's sign-in page, as in Claude's connectors. Leave Client ID empty unless the service requires one; if so, register an app with the redirect URL \(ConnectorLibrary.redirectURI).",
              "Claude'daki bağlayıcılar gibi servisin giriş sayfasını açar. Servis istemedikçe Client ID'yi boş bırak; isterse yönlendirme adresi \(ConnectorLibrary.redirectURI) olan bir uygulama kaydet.")
        }
    }

    private func saveDraft() {
        // Araç seçimleri doğrudan kütüphanede değişir; taslağın eski kopyası onları ezmesin.
        if let saved {
            draft.tools = saved.tools
            draft.disabledTools = saved.disabledTools
            draft.enabledByDefault = saved.enabledByDefault
        }
        library.save(draft, token: token)
    }

    /// Önce kaydeder, sonra işlemi çalıştırır ve sonucu gösterir.
    private func run(_ action: @escaping () async throws -> Void) {
        saveDraft()
        working = true
        message = nil
        Task {
            do {
                try await action()
                let count = library.connector(draft.id)?.tools.count ?? 0
                message = L("Connected: \(count) tools found.", "Bağlandı: \(count) araç bulundu.")
                failed = false
            } catch {
                message = connectorErrorMessage(error)
                failed = true
            }
            working = false
        }
    }
}
