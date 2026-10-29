import AgentCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var tavilyKey = ""
    @State private var userInstructions = ""
    @State private var language = AppLanguage.stored
    /// Ekran açıldığındaki seçim; değişirse yeniden başlatma uyarısı gösterilir.
    @State private var initialLanguage = AppLanguage.stored

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(settings.providers) { provider in
                        NavigationLink {
                            ProviderEditorView(provider: provider)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(provider.name)
                                    .foregroundStyle(Palette.textBright)
                                Text(verbatim: "\(URL(string: provider.baseURL)?.host ?? provider.baseURL) · " + L(
                                    provider.models.count == 1 ? "1 model" : "\(provider.models.count) models",
                                    "\(provider.models.count) model"
                                ))
                                    .font(.caption)
                                    .foregroundStyle(Palette.textMuted)
                            }
                        }
                    }
                    NavigationLink {
                        ProviderEditorView(provider: nil)
                    } label: {
                        Label(L("Add Provider", "Sağlayıcı ekle"), systemImage: "plus")
                            .foregroundStyle(Palette.blue)
                    }
                } header: {
                    header(L("Models and providers", "Modeller ve sağlayıcılar"))
                } footer: {
                    footer(L("Each provider is an OpenAI-compatible address and API key; add as many models under it as you like. The model is chosen in the chat screen.", "Her sağlayıcı bir OpenAI-uyumlu adres ve API key'dir; altına istediğin kadar model ekleyebilirsin. Model sohbet ekranından seçilir."))
                }
                .listRowBackground(Palette.surface)

                Section {
                    NavigationLink {
                        UsageView()
                    } label: {
                        Label(L("Token and search usage", "Token ve arama kullanımı"), systemImage: "chart.bar")
                            .foregroundStyle(Palette.textBright)
                    }
                }
                .listRowBackground(Palette.surface)

                Section {
                    Picker(L("Language", "Dil"), selection: $language) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(language.title).tag(language)
                        }
                    }
                    .foregroundStyle(Palette.textBright)
                    .onChange(of: language) { AppLanguage.store(language) }
                } header: {
                    header(L("Language", "Dil"))
                } footer: {
                    footer(language != initialLanguage
                        ? L("Close and reopen the app to apply the new language.", "Yeni dilin uygulanması için uygulamayı kapatıp yeniden aç.")
                        : L("System follows your iPhone's language.", "Sistem, iPhone'unun dilini kullanır."))
                }
                .listRowBackground(Palette.surface)

                Section {
                    TextField(L("Personal instructions", "Kişisel talimatlar"), text: $userInstructions, prompt: prompt(L("E.g. Don't use emoji. Keep answers short.", "Örn. Emoji kullanma. Kısa cevap ver.")), axis: .vertical)
                        .lineLimit(3...10)
                        .foregroundStyle(Palette.textBright)
                } header: {
                    header(L("Personal instructions", "Kişisel talimatlar"))
                } footer: {
                    footer(L("Shared with the assistant in every chat.", "Her sohbette asistana iletilir."))
                }
                .listRowBackground(Palette.surface)

                Section {
                    SecureField("Tavily API key", text: $tavilyKey, prompt: prompt("Tavily API key (tvly-…)"))
                        .foregroundStyle(Palette.textBright)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    header(L("Web search", "Web araması"))
                } footer: {
                    footer(L("Free at tavily.com. If left empty, the assistant can't search the web.", "tavily.com'dan ücretsiz alınır. Boş bırakılırsa asistan web'de arama yapamaz."))
                }
                .listRowBackground(Palette.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .tint(Palette.blue)
            .navigationTitle(L("Settings", "Ayarlar"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done", "Bitti")) {
                        settings.saveGeneral(tavilyKey: tavilyKey, userInstructions: userInstructions)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                tavilyKey = settings.tavilyKey
                userInstructions = settings.userInstructions
            }
        }
    }
}

/// Ayar ekranlarında ortak metin stilleri.
@MainActor func prompt(_ text: String) -> Text {
    Text(text).foregroundStyle(Palette.textMuted)
}

@MainActor func header(_ text: String) -> some View {
    Text(text).foregroundStyle(Palette.textMuted)
}

@MainActor func footer(_ text: String) -> some View {
    Text(text).foregroundStyle(Palette.textMuted)
}
