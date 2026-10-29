import AgentCore
import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    @State private var baseURL = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var tavilyKey = ""
    @State private var userInstructions = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    field("https://router.example.com/v1", text: $baseURL)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                    field("Model adı", text: $model)
                    SecureField("API key", text: $apiKey, prompt: prompt("API key"))
                        .foregroundStyle(Palette.textBright)
                } header: {
                    header("LLM sağlayıcısı")
                } footer: {
                    footer("OpenAI-uyumlu endpoint'in /v1 dahil adresi. Sadece HTTPS. Key yalnızca bu cihazın Keychain'inde saklanır.")
                }
                .listRowBackground(Palette.surface)

                Section {
                    TextField("Kişisel talimatlar", text: $userInstructions, prompt: prompt("Örn. Emoji kullanma. Kısa cevap ver."), axis: .vertical)
                        .lineLimit(3...10)
                        .foregroundStyle(Palette.textBright)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                } header: {
                    header("Kişisel talimatlar")
                } footer: {
                    footer("Her sohbette asistana iletilir.")
                }
                .listRowBackground(Palette.surface)

                Section {
                    SecureField("Tavily API key", text: $tavilyKey, prompt: prompt("Tavily API key (tvly-…)"))
                        .foregroundStyle(Palette.textBright)
                } header: {
                    header("Web araması")
                } footer: {
                    footer("tavily.com'dan ücretsiz alınır. Boş bırakılırsa asistan web'de arama yapamaz.")
                }
                .listRowBackground(Palette.surface)

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(Palette.red)
                    }
                    .listRowBackground(Palette.surface)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .tint(Palette.blue)
            .navigationTitle("Ayarlar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet", action: save)
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                baseURL = settings.baseURL
                model = settings.model
                apiKey = settings.apiKey
                tavilyKey = settings.tavilyKey
                userInstructions = settings.userInstructions
            }
        }
    }

    private func field(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text, prompt: prompt(placeholder))
            .foregroundStyle(Palette.textBright)
    }

    private func prompt(_ text: String) -> Text {
        Text(text).foregroundStyle(Palette.textMuted)
    }

    private func header(_ text: String) -> some View {
        Text(text).foregroundStyle(Palette.textMuted)
    }

    private func footer(_ text: String) -> some View {
        Text(text).foregroundStyle(Palette.textMuted)
    }

    private func save() {
        do {
            settings.save(
                try LLMConfiguration(baseURL: baseURL, apiKey: apiKey, model: model),
                tavilyKey: tavilyKey,
                userInstructions: userInstructions
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
