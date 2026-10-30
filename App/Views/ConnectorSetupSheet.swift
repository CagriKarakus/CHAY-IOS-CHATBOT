import AgentCore
import SwiftUI

/// Asistanın önerdiği bağlayıcı için onay ve giriş penceresi. Token sadece burada yazılır:
/// doğrudan Keychain'e gider, sohbete veya modele hiç ulaşmaz. Bu pencere otomatik geçilemez.
struct ConnectorSetupSheet: View {
    let setup: PendingConnectorSetup
    /// Token ve Client ID ile bağlanır; hata fırlatırsa pencere açık kalır.
    let connect: (String, String) async throws -> Void
    let cancel: () -> Void

    @State private var token = ""
    @State private var clientID = ""
    @State private var showsClientID = false
    @State private var working = false
    @State private var errorMessage: String?

    private var proposal: ConnectorProposal { setup.proposal }

    private var canConnect: Bool {
        guard !working else { return false }
        return setup.auth != .token || setup.hasSavedToken
            || !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent(L("Service", "Servis"), value: proposal.name)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L("Server address", "Sunucu adresi"))
                            .font(.caption)
                            .foregroundStyle(Palette.textMuted)
                        Text(verbatim: proposal.url)
                            .font(.footnote.monospaced())
                            .foregroundStyle(Palette.textBright)
                            .textSelection(.enabled)
                    }
                    sourceRow
                } footer: {
                    footer(sourceFooter)
                }
                .listRowBackground(Palette.surface)

                authSection

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Palette.red)
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .foregroundStyle(Palette.textBright)
            .tint(Palette.blue)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .navigationTitle(L("Add Connector", "Bağlayıcı ekle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Cancel", "Vazgeç"), action: cancel)
                        .disabled(working)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button(setup.auth == .oauth ? L("Sign In", "Giriş yap") : L("Connect", "Bağlan"), action: start)
                            .fontWeight(.semibold)
                            .disabled(!canConnect)
                    }
                }
            }
        }
        // Yanlışlıkla kaydırıp kapatılmasın; karar açıkça verilsin.
        .interactiveDismissDisabled()
    }

    private var sourceRow: some View {
        Group {
            switch proposal.source {
            case .verified:
                Label(L("Verified", "Doğrulanmış"), systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Palette.green)
            case .registry:
                Label(L("Unverified · MCP registry", "Doğrulanmamış · MCP kataloğu"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.yellow)
            case .web:
                Label(L("Unverified · found on the web", "Doğrulanmamış · web'de bulundu"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(Palette.yellow)
            }
        }
        .font(.subheadline)
    }

    private var sourceFooter: String {
        proposal.source == .verified
            ? L("This address is on CHAY's checked list.", "Bu adres CHAY'in kontrol edilmiş listesinde.")
            : L("Anyone can publish a server. Make sure the address belongs to this service before continuing. The connector stays on only in this chat, and tools that may change data ask you first.",
                "Herkes sunucu yayınlayabilir. Devam etmeden önce adresin bu servise ait olduğundan emin ol. Bağlayıcı sadece bu sohbette açık olur; veri değiştirebilen araçlar önce sana sorar.")
    }

    @ViewBuilder
    private var authSection: some View {
        Section {
            switch setup.auth {
            case .none:
                Text(L("No sign-in needed.", "Giriş gerekmiyor."))
            case .token:
                if let page = proposal.tokenURL.flatMap(URL.init(string:)) {
                    Link(destination: page) {
                        Label(L("Open token page (\(page.host ?? ""))", "Token sayfasını aç (\(page.host ?? ""))"),
                              systemImage: "arrow.up.forward.app")
                    }
                }
                SecureField(L("Access token", "Erişim token'ı"), text: $token,
                            prompt: prompt(setup.hasSavedToken ? L("Saved; leave empty to keep", "Kayıtlı; korumak için boş bırak") : L("Paste the token", "Token'ı yapıştır")))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            case .oauth:
                Text(L("You'll sign in on the service's own page.", "Servisin kendi sayfasında giriş yapacaksın."))
            }
            if showsClientID {
                TextField("Client ID", text: $clientID, prompt: prompt("Client ID"))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Text(verbatim: ConnectorLibrary.redirectURI)
                    .font(.footnote.monospaced())
                    .textSelection(.enabled)
            }
        } header: {
            header(L("Sign-in", "Giriş"))
        } footer: {
            footer(authFooter)
        }
        .listRowBackground(Palette.surface)
    }

    private var authFooter: String {
        if showsClientID {
            return L("This service doesn't allow automatic registration. Register an app in its developer settings with the redirect address above, then enter its Client ID.",
                     "Bu servis otomatik kayda izin vermiyor. Geliştirici ayarlarında yukarıdaki yönlendirme adresiyle bir uygulama kaydet ve Client ID'sini gir.")
        }
        return setup.auth == .token
            ? L("The token is stored in this device's Keychain and sent only to the address above. The assistant never sees it.",
                "Token bu cihazın Keychain'inde saklanır ve sadece yukarıdaki adrese gönderilir. Asistan onu hiçbir zaman görmez.")
            : L("The assistant only learns whether the connection worked.", "Asistan sadece bağlantının çalışıp çalışmadığını öğrenir.")
    }

    private func start() {
        working = true
        errorMessage = nil
        Task {
            do {
                try await connect(token, clientID)
            } catch {
                errorMessage = connectorErrorMessage(error)
                if case MCPOAuthError.registrationUnsupported = error { showsClientID = true }
                if case MCPOAuthError.registrationFailed = error { showsClientID = true }
            }
            working = false
        }
    }
}
